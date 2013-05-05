part of bzip2;

class _Bzip2Compressor implements _Bzip2Coder {
  
  int _blockSizeFactor;
  bool _noMoreData = false;
  bool _isFirstStep = true;
  bool _isDone = false;
  
  List<int> _input = new List<int>(_MAX_BYTES_REQUIRED);
  int _inputIndex = 0;
  int _inputSize = 0;
  
  BitBuffer _outputBuffer = new BitBuffer(_MAX_BYTES_REQUIRED);
  
  _Bzip2Crc _blockCrc = new _Bzip2Crc();
  _Bzip2CombinedCrc _fileCrc = new _Bzip2CombinedCrc();
  
  int _originPointer;
  List<bool> _inUse;
  List<bool> _inUse16;
  int _alphaSize;
  List<List<int>> Lens = create2dList(_TABLE_COUNT_MAX, _MAX_ALPHA_SIZE);
  List<List<int>> Freqs = create2dList(_TABLE_COUNT_MAX, _MAX_ALPHA_SIZE);
  List<List<int>> Codes = create2dList(_TABLE_COUNT_MAX, _MAX_ALPHA_SIZE);
  List<int> selectors = new List<int>(_SELECTOR_COUNT_MAX);
  int _tableCount = 2;
  int _selectorCount;

  
  _Bzip2Compressor(this._blockSizeFactor) {
    if (this._blockSizeFactor < 1 || this._blockSizeFactor > 9) {
      throw new ArgumentError("invalid block size factor");
    }
  }

  void writeByte(int byte) {
    _input[_inputSize] = byte;
    _inputSize++;
  }
  
  bool canProcess() {
    return !_isDone && (_noMoreData || _inputSize >= _blockSizeFactor * _BLOCK_SIZE_STEP);
  }
  
  void process() {
    List<int> _buffer;
    
    if (_isFirstStep) {
      _writeHeader();
      _isFirstStep = false;
    }
    
    if (_inputIndex < _inputSize) {
      /* block header */
      _calculateBlockCrc();
      _fileCrc.update(_blockCrc.getDigest());
      _writeBlockHeader();
      
      /* compress block */
      _buffer = _readBlock();
      _buffer = _rleEncode1(_buffer);
      _buffer = _burrowsWheelerTransform(_buffer);
      _inUse = _calculateInUse(_buffer);
      _inUse16 = _calculateInUse16(_inUse);
      _alphaSize = _getAlphaSize(_inUse);
      _buffer = _mtf8Encode(_buffer);
      _buffer = _rleEncode2(_buffer);
      _createHuffmanTables(_buffer);
      _writeBlock(_buffer);      
    }
    
    if (_noMoreData) {
      _writeFooter();
      _isDone = true;
    }
    
    _inputSize = 0;
    _inputIndex = 0;
  }
  
  List<int> readOutput() {
    List<int> output = new List<int>(_MAX_BYTES_REQUIRED);
    int outputSize = 0;
    
    while (_outputBuffer.bitCount() >= 8) {
      output[outputSize] = _outputBuffer.readByte();
      outputSize++;
    }
    
    int remBits = _outputBuffer.bitCount();
    if (_isDone && remBits > 0) {
      output[outputSize] = _outputBuffer.readBits(remBits) << (8 - remBits);
      outputSize++;
    }
    
    output = output.sublist(0, outputSize);
    return output;
  }
  
  void setEndOfData() {
    _noMoreData = true;
  }
  
  int _nextByte() {
    return _input[_inputIndex++];
  }
  
  bool _endOfInput() {
    return _inputIndex == _inputSize;
  }  
  
  List<int> _writeBlock(List<int> _buffer) {        
    _outputBuffer.writeBit(0); // not randomized
    _outputBuffer.writeBits(_originPointer, _ORIGIN_BIT_COUNT);
    for (int i = 0; i < 16; i++) {
      _outputBuffer.writeBit(_inUse16[i] ? 1 : 0);
    }
    for (int i = 0; i < 256; i++) {
      if (_inUse16[i >> 4]) {
        _outputBuffer.writeBit(_inUse[i] ? 1 : 0);
      }
    }
    _outputBuffer.writeBits(_tableCount, _TABLE_COUNT_BITS);
    _outputBuffer.writeBits(_selectorCount, _SELECTOR_COUNT_BITS);
    
    List<int> mtfSel = new List<int>.generate(_TABLE_COUNT_MAX, (x)=>x);
    for (int i = 0; i < _selectorCount; i++) {
      int sel = selectors[i];
      int pos;
      for (pos = 0; mtfSel[pos] != sel; pos++)
        _outputBuffer.writeBit(1);
      _outputBuffer.writeBit(0);
      for (; pos > 0; pos--)
        mtfSel[pos] = mtfSel[pos - 1];
      mtfSel[0] = sel;
    }
    
    for (int t = 0; t < _tableCount; t++) {
      List<int> lens = Lens[t];
      int len = lens[0];
      _outputBuffer.writeBits(len, _LEVEL_BITS);
      for (int i = 0; i < _alphaSize; i++) {
        int level = lens[i];
        while (len != level) {
          _outputBuffer.writeBit(1);
          if (len < level) {
            _outputBuffer.writeBit(0);
            len++;
          } else {
            _outputBuffer.writeBit(1);
            len--;
          }
        }
        _outputBuffer.writeBit(0);
      }
    }
    
    int groupSize = 0;
    int groupIndex = 0;
    List<int> lens;
    List<int> codes;
    int mtfPos = 0;
    do {
      int symbol = _buffer[mtfPos++];
      if (groupSize == 0) {
        groupSize = _GROUP_SIZE;
        int t = selectors[groupIndex++];
        lens = Lens[t];
        codes = Codes[t];
      }
      groupSize--;
      _outputBuffer.writeBits(codes[symbol], lens[symbol]);
    }
    while (mtfPos < _buffer.length);
  }
  
  void _writeHeader() {
    for (int byte in _BZIP_SIGNATURE) {
      _outputBuffer.writeByte(byte);
    }
    _outputBuffer.writeByte('0'.codeUnitAt(0) + _blockSizeFactor);
  }
  
  void _writeBlockHeader() {
    for (int byte in _BLOCK_SIGNATURE) {
      _outputBuffer.writeByte(byte);
    }
    _outputBuffer.writeBits(_blockCrc.getDigest(), 32);
  }
  
  void _writeCompressedBlock(List<int> buffer) {
    for (int byte in buffer) {
      _outputBuffer.writeByte(byte);
    }
  }
  
  void _calculateBlockCrc() {
    _blockCrc.reset();
    for(int i = 0; i < _inputSize; i++) {
      _blockCrc.updateByte(_input[i]);
    }
  }
  
  void _writeFooter() {
    for (int byte in _FINISH_SIGNATURE) {
      _outputBuffer.writeByte(byte);
    }
    _outputBuffer.writeBits(_fileCrc.getDigest(), 32);
  }
  
  List<int> _readBlock() {
    List<int> result = new List<int>(_MAX_BYTES_REQUIRED);
    int maxBlockSize = _blockSizeFactor * _BLOCK_SIZE_STEP;
    int resultIndex = 0;
    while (resultIndex < maxBlockSize && !_endOfInput()) {
      result[resultIndex++] = _nextByte();
    }
    result = result.sublist(0, resultIndex);
    return result;
  }
  
  List<int> _rleEncode1(List<int> block) {
    List<int> result = new List<int>(_MAX_BYTES_REQUIRED);
    int resultIndex = 0;
    int blockIndex = 0;
    while (blockIndex < block.length) {
      int runLength = 0;
      int currentByte = block[blockIndex];
      int maxRunLength = min(block.length - blockIndex, _RLE_MODE_REP_SIZE + 255);
      
      while (runLength < maxRunLength && block[blockIndex] == currentByte) {
        runLength++;
        blockIndex++;
      }
      
      for (int i = 0; i < min(runLength, _RLE_MODE_REP_SIZE); i++) {
        result[resultIndex++] = currentByte;
      }
      
      if (runLength >= _RLE_MODE_REP_SIZE) {
        result[resultIndex++] = runLength - _RLE_MODE_REP_SIZE;
      }
    }
    
    result = result.sublist(0, resultIndex);
    return result;
  }
  
  List<int> _burrowsWheelerTransform(List<int> _buffer) {
    List<int> y = _buffer.map((x) => x + 1).toList();
    String s = new String.fromCharCodes(y);
    SuffixArray suffixArray = new SuffixArray(s + s);
    List<int> sortedSuffixes = suffixArray.getSortedSuffixes();
    
    List<int> result = new List<int>(_buffer.length);
    int resultIndex = 0;
    
    for (int b in sortedSuffixes) {
      if (b < _buffer.length) {
        if (b == 0) {
          _originPointer = resultIndex;
        }
        result[resultIndex++] = _buffer[(b + _buffer.length - 1) % _buffer.length];
      }
    }
    
    return result;
  }
  
  List<bool> _calculateInUse(List<int> _buffer) {
    List<bool> inUse = new List<bool>.filled(256, false);
    for (int value in _buffer) {
      inUse[value] = true;
    }
    return inUse;
  }
  
  List<bool> _calculateInUse16(List<bool> inUse) {
    List<bool> inUse16 = new List<bool>.filled(16, false);
    for (int i = 0; i < 256; i++) {
      if (inUse[i]) {
        inUse16[i >> 4] = true;
      }
    }
    return inUse16;
  }
  
  int _getAlphaSize(List<bool> inUse) {
    int alphaSize = inUse.where((v) => v).length + 2;
    return alphaSize;
  }
  
  List<int> _mtf8Encode(List<int> _buffer) {
    List<int> _result = new List<int>(_buffer.length);
    
    _Mtf8Encoder mtf8Encoder = new _Mtf8Encoder();
    int current = 0;
    for (int i = 0; i < 256; i++) {
      if (_inUse[i]) {
        mtf8Encoder.set(current, i);
        current++;
      }
    }
    
    for (int i = 0; i < _buffer.length; i++) {
      _result[i] = mtf8Encoder.findAndMove(_buffer[i]);
    }
    
    return _result;
  }

  List<int> _rleEncode2(List<int> buffer) {
    List<int> result = new List<int>(_MAX_BLOCK_SIZE + 2);
    int resultIndex = 0;
    int bufferIndex = 0;
    
    while (bufferIndex < buffer.length) {
      int runLength = 0;
      
      while (bufferIndex < buffer.length && buffer[bufferIndex] == 0) {
        runLength++;
        bufferIndex++;
      }
      
      if (runLength != 0) {
        while (runLength != 0) {
          runLength--;
          result[resultIndex++] = (runLength & 1);
          runLength >>= 1;
        }
      } else {
        int value = buffer[bufferIndex++] + 1;
        result[resultIndex++] = value;
      }
    }
    
    result[resultIndex++] = _alphaSize - 1;
    
    result = result.sublist(0, resultIndex);
    return result;
  }
  
  void _createHuffmanTables(List<int> _buffer) {
    List<int> symbolCounts = new List<int>.filled(_MAX_ALPHA_SIZE, 0);
    for (int value in _buffer) {
      symbolCounts[value]++;
    }
    
    int _symbolCount = 0;
    for (int i = 0; i < _MAX_ALPHA_SIZE; i++)
      _symbolCount += symbolCounts[i];
    
    _tableCount = 2;
    _selectorCount = (_symbolCount + _GROUP_SIZE - 1) ~/ _GROUP_SIZE;
    
    int remFreq = _symbolCount;
    int gs = 0;
    int t = _tableCount;
    do
    {
      int tFreq = remFreq ~/ t;
      int ge = gs;
      int aFreq = 0;
      while (aFreq < tFreq)
        aFreq += symbolCounts[ge++];
      
      List<int> lens = Lens[t - 1];
      int i = 0;
      do
        lens[i] = (i >= gs && i < ge) ? 0 : 1;
      while (++i < _alphaSize);
      gs = ge;
      remFreq -= aFreq;
    }
    while(--t != 0);
    
    for (int pass = 0; pass < _HUFFMAN_PASSES; pass++) {
      int mtfPos = 0;
      int g = 0;
      do {
        List<int> symbols = new List<int>(_GROUP_SIZE);
        int i = 0;
        for (; i < _GROUP_SIZE && mtfPos < _buffer.length; i++) {
          symbols[i] = _buffer[mtfPos++];
        }
        
        int bestPrice = 0xFFFFFFFF;
        for (int t = 0; t < _tableCount; t++) {
          List<int> lens = Lens[t];
          int price = 0;
          for (int j = 0; j < i; j++)
            price += lens[symbols[j]];
          if (price < bestPrice) {
            selectors[g] = t;
            bestPrice = price;
          }
        }
        List<int> freqs = Freqs[selectors[g++]];
        for (int j = 0; j < i; j++)
          freqs[symbols[j]]++;
      }
      while (mtfPos < _buffer.length);
      
      for (int t = 0; t < _tableCount; t++) {
        List<int> freqs = Freqs[t];
        for (int i = 0; i < _alphaSize; i++) {
          if (freqs[i] == 0)
            freqs[i] = 1;
        }
        _HuffmanEncoder encoder = new _HuffmanEncoder(_MAX_ALPHA_SIZE, _MAX_HUFFMAN_LEN_FOR_ENCODING);
        encoder.generate(freqs, Codes[t], Lens[t]);
      }
    }
  }
}

List<List<int>> create2dList(int n, int m) {
  List<List<int>> result = new List<List<int>>.generate(n, (_) => new List<int>.filled(m, 0));
  return result;
}
