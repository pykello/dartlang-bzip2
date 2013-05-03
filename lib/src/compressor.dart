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
      _buffer = _createRleBlock();
      _buffer = _encodeBlock3(_buffer);      
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
  
  List<int> _createRleBlock() {
    List<int> buffer = new List<int>(_MAX_BYTES_REQUIRED);
    int prevByte = _nextByte();
    int blockSize = _blockSizeFactor * _BLOCK_SIZE_STEP - 1;
    int numReps = 1;
    int i = 0;
    buffer[i++] = prevByte;
    while (i < blockSize) // "- 1" to support RLE
    {
      if (endOfInput()) {
        break;
      }
      int b = _nextByte();
      if (b != prevByte)
      {
        if (numReps >= _RLE_MODE_REP_SIZE)
          buffer[i++] = (numReps - _RLE_MODE_REP_SIZE);
        buffer[i++] = b;
        numReps = 1;
        prevByte = b;
        continue;
      }
      numReps++;
      if (numReps <= _RLE_MODE_REP_SIZE)
        buffer[i++] = b;
      else if (numReps == _RLE_MODE_REP_SIZE + 255)
      {
        buffer[i++] = (numReps - _RLE_MODE_REP_SIZE);
        numReps = 0;
      }
    }
    // it's to support original BZip2 decoder
    if (numReps >= _RLE_MODE_REP_SIZE)
      buffer[i++] = (numReps - _RLE_MODE_REP_SIZE);
    
    buffer = buffer.sublist(0, i);
    return buffer;
  }
  
  int _nextByte() {
    return _input[_inputIndex++];
  }
  
  bool endOfInput() {
    return _inputIndex == _inputSize;
  }
  
  List<int> _encodeBlock3(List<int> _buffer) {
    int blockSize = _buffer.length;
    
    List<List<int>> Lens = create2dList(_TABLE_COUNT_MAX, _MAX_ALPHA_SIZE);
    List<List<int>> Freqs = create2dList(_TABLE_COUNT_MAX, _MAX_ALPHA_SIZE);
    List<List<int>> Codes = create2dList(_TABLE_COUNT_MAX, _MAX_ALPHA_SIZE);
    List<int> selectors = new List<int>(_SELECTOR_COUNT_MAX);
    
    List<int> blockSort = _blockSort(_buffer);
    int _originPointer = blockSort.indexOf(0);
    blockSort[_originPointer] = blockSize;
    
    int numInUse = 0;
    List<bool> inUse = new List<bool>.filled(256, false);
    List<bool> inUse16 = new List<bool>.filled(16, false);
    for (int byte in _buffer) {
      inUse[byte] = true;
    }
    for (int i = 0; i < 256; i++) {
      if (inUse[i]) {
        inUse16[i >> 4] = true;
        numInUse++;
      }
    }
    int alphaSize = numInUse + 2;
    
    _Mtf8Encoder mtf = new _Mtf8Encoder();
    int current = 0;
    for (int i = 0; i < 256; i++) {
      if (inUse[i]) {
        mtf.set(current, i);
        current++;
      }
    }
    
    List<int> mtfs = new List<int>(_MAX_BLOCK_SIZE + 2);
    int mtfArraySize = 0;
    List<int> symbolCounts = new List<int>.filled(_MAX_ALPHA_SIZE, 0);
    
    int rleSize = 0;
    for (int i = 0; i < blockSize; i++) {
      int index = blockSort[i] - 1;
      int pos = mtf.findAndMove(_buffer[index]);
      if (pos == 0) {
        rleSize++;
      } else
      {
        while (rleSize != 0)
        {
          rleSize--;
          mtfs[mtfArraySize++] = (rleSize & 1);
          symbolCounts[rleSize & 1]++;
          rleSize >>= 1;
        }
        if (pos >= 0xFE)
        {
          mtfs[mtfArraySize++] = 0xFF;
          mtfs[mtfArraySize++] = (pos - 0xFE);
        }
        else
          mtfs[mtfArraySize++] = (pos + 1);
        symbolCounts[pos + 1]++;
      }
    }
    
    while (rleSize != 0)
    {
      rleSize--;
      mtfs[mtfArraySize++] = (rleSize & 1);
      symbolCounts[rleSize & 1]++;
      rleSize >>= 1;
    }
    
    if (alphaSize < 256)
      mtfs[mtfArraySize++] = (alphaSize - 1);
    else
    {
      mtfs[mtfArraySize++] = 0xFF;
      mtfs[mtfArraySize++] = (alphaSize - 256);
    }
    symbolCounts[alphaSize - 1]++;
    
    int numSymbols = 0;
    for (int i = 0; i < _MAX_ALPHA_SIZE; i++)
      numSymbols += symbolCounts[i];
    
    int numTables = 2;
    int numSelectors = (numSymbols + _GROUP_SIZE - 1) ~/ _GROUP_SIZE;
    
    {
      int remFreq = numSymbols;
      int gs = 0;
      int t = numTables;
      do
      {
        int tFreq = remFreq ~/ t;
        int ge = gs;
        int aFreq = 0;
        while (aFreq < tFreq) //  && ge < alphaSize)
          aFreq += symbolCounts[ge++];
        
        if (ge - 1 > gs && t != numTables && t != 1 && (((numTables - t) & 1) == 1))
          aFreq -= symbolCounts[--ge];
        
        List<int> lens = Lens[t - 1];
        int i = 0;
        do
          lens[i] = (i >= gs && i < ge) ? 0 : 1;
        while (++i < alphaSize);
        gs = ge;
        remFreq -= aFreq;
      }
      while(--t != 0);
    }
    
    for (int pass = 0; pass < _HUFFMAN_PASSES; pass++)
    {
      
      {
        int mtfPos = 0;
        int g = 0;
        do
        {
          List<int> symbols = new List<int>(_GROUP_SIZE);
          int i = 0;
          for (int i = 0; i < _GROUP_SIZE && mtfPos < mtfArraySize; i++)
          {
            int symbol = mtfs[mtfPos++];
            if (symbol >= 0xFF)
              symbol += mtfs[mtfPos++];
            symbols[i] = symbol;
          }
          
          int bestPrice = 0xFFFFFFFF;
          for (int t = 0; t < numTables; t++)
          {
            List<int> lens = Lens[t];
            int price = 0;
            for (int j = 0; j < i; j++)
              price += lens[symbols[j]];
            if (price < bestPrice)
            {
              selectors[g] = t;
              bestPrice = price;
            }
          }
          List<int> freqs = Freqs[selectors[g++]];
          for (int j = 0; j < i; j++)
            freqs[symbols[j]]++;
        }
        while (mtfPos < mtfArraySize);
      }
      
      for (int t = 0; t < numTables; t++)
      {
        List<int> freqs = Freqs[t];
        for (int i = 0; i < alphaSize; i++) {
          if (freqs[i] == 0)
            freqs[i] = 1;
        }
        _HuffmanEncoder encoder = new _HuffmanEncoder(_MAX_ALPHA_SIZE, _MAX_HUFFMAN_LEN_FOR_ENCODING);
        encoder.generate(freqs, Codes[t], Lens[t]);
      }
    }
    
    _outputBuffer.writeBit(0); // not randomized
    _outputBuffer.writeBits(_originPointer, _ORIGIN_BIT_COUNT);
    for (int i = 0; i < 16; i++) {
      _outputBuffer.writeBit(inUse16[i] ? 1 : 0);
    }
    for (int i = 0; i < 256; i++) {
      if (inUse16[i >> 4]) {
        _outputBuffer.writeBit(inUse[i] ? 1 : 0);
      }
    }
    _outputBuffer.writeBits(numTables, _TABLE_COUNT_BITS);
    _outputBuffer.writeBits(numSelectors, _SELECTOR_COUNT_BITS);
    
    List<int> mtfSel = new List<int>.generate(_TABLE_COUNT_MAX, (x)=>x);
    for (int i = 0; i < numSelectors; i++) {
      int sel = selectors[i];
      int pos;
      for (pos = 0; mtfSel[pos] != sel; pos++)
        _outputBuffer.writeBit(1);
      _outputBuffer.writeBit(0);
      for (; pos > 0; pos--)
        mtfSel[pos] = mtfSel[pos - 1];
      mtfSel[0] = sel;
    }
    
    for (int t = 0; t < numTables; t++) {
      List<int> lens = Lens[t];
      int len = lens[0];
      _outputBuffer.writeBits(len, _LEVEL_BITS);
      for (int i = 0; i < alphaSize; i++) {
        int level = lens[i];
        while (len != level)
        {
          _outputBuffer.writeBit(1);
          if (len < level)
          {
            _outputBuffer.writeBit(0);
            len++;
          }
          else
          {
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
    do
    {
      int symbol = mtfs[mtfPos++];
      if (symbol >= 0xFF)
        symbol += mtfs[mtfPos++];
      if (groupSize == 0)
      {
        groupSize = _GROUP_SIZE;
        int t = selectors[groupIndex++];
        lens = Lens[t];
        codes = Codes[t];
      }
      groupSize--;
      _outputBuffer.writeBits(codes[symbol], lens[symbol]);
    }
    while (mtfPos < mtfArraySize);
    return [];
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
  
  List<int> _blockSort(List<int> _buffer) {
    List<int> y = _buffer.map((x) => x + 1).toList();
    String s = new String.fromCharCodes(y);
    SuffixArray suffixArray = new SuffixArray(s + s);
    List<int> result = new List<int>(_buffer.length);
    int resultIndex = 0;
    List<int> sortedSuffixes = suffixArray.getSortedSuffixes();
    for (int b in sortedSuffixes) {
      if (b < _buffer.length) {
        result[resultIndex++] = b;
      }
    }
    return result;
  }
  
}

List<List<int>> create2dList(int n, int m) {
  List<List<int>> result = new List<List<int>>.generate(n, (_) => new List<int>.filled(m, 0));
  return result;
}
