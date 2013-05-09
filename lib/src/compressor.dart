part of bzip2;

class _Bzip2Compressor implements _Bzip2Coder {
  int _blockSizeFactor;
  
  /* input state */
  List<int> _input = new List<int>(_MAX_BYTES_REQUIRED);
  int _inputSize = 0;
  bool _noMoreData = false;
  
  /* file state */
  bool _isFirstBlock = true;
  bool _isDone = false;
  _Bzip2CombinedCrc _fileCrc = new _Bzip2CombinedCrc();
  
  /* block compression information */
  List<int> _compressedBlock;
  int _blockCrc;
  int _originPointer;
  List<bool> _inUse;
  List<bool> _inUse16;
  List<List<_HuffmanCode>> _huffmanTables;
  List<int> _selectors;
  
  /* output state */
  BitBuffer _outputBuffer = new BitBuffer(_MAX_BYTES_REQUIRED);

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
    if (_isFirstBlock) {
      _writeHeader();
      _isFirstBlock = false;
    }
    
    if (_inputSize != 0) {
      List<int> block = _readBlock();
      
      _blockCrc = _calculateBlockCrc(block);
      _fileCrc.update(_blockCrc);
      
      _compressBlock(block);
      _writeCompressedBlock();
    }
    
    if (_noMoreData) {
      _writeFooter();
      _isDone = true;
    }
  }
  
  List<int> readOutput() {
    List<int> output = new List<int>(_MAX_BYTES_REQUIRED);
    int outputSize = 0;
    
    while (_outputBuffer.bitCount() >= 8) {
      output[outputSize++] = _outputBuffer.readByte();
    }
    
    int remainingBits = _outputBuffer.bitCount();
    if (_isDone && remainingBits > 0) {
      int padding = 8 - remainingBits;
      output[outputSize++] = _outputBuffer.readBits(remainingBits) << padding;
    }
    
    output = output.sublist(0, outputSize);
    return output;
  }
  
  void setEndOfData() {
    _noMoreData = true;
  }
  
  void _compressBlock(List<int> block) {
    List<int> blockRleEncoded = _rleEncode1(block);
    
    var bwtResult = _burrowsWheelerTransform(blockRleEncoded);
    List<int> blockSorted = bwtResult[0];
    _originPointer = bwtResult[1];
    
    _inUse = _calculateInUse(blockSorted);
    _inUse16 = _calculateInUse16(_inUse);
    List<int> symbols = _calculateSymbols(_inUse);
    int alphaSize = _getAlphaSize(_inUse);
    
    List<int> blockMtfEncoded = _mtfEncode(blockSorted, symbols);
    
    List<int> blockRleEncoded2 = _rleEncode2(blockMtfEncoded, alphaSize);
    
    _huffmanTables = _calculateHuffmanTables(blockRleEncoded2, alphaSize);
    _selectors = _calculateSelectors(blockRleEncoded2, _huffmanTables);
    
    _compressedBlock = blockRleEncoded2;
  }
  
  void _writeCompressedBlock() {
    _outputBuffer.writeBits(_BLOCK_SIGNATURE_HIGH, 24);
    _outputBuffer.writeBits(_BLOCK_SIGNATURE_LOW, 24);
    _outputBuffer.writeBits(_blockCrc, 32);
    
    _outputBuffer.writeBit(0); /* not randomized */
    
    /* write inUse information */
    _outputBuffer.writeBits(_originPointer, _ORIGIN_BIT_COUNT);
    for (int i = 0; i < 16; i++) {
      _outputBuffer.writeBit(_inUse16[i] ? 1 : 0);
    }
    for (int i = 0; i < 256; i++) {
      if (_inUse16[i >> 4]) {
        _outputBuffer.writeBit(_inUse[i] ? 1 : 0);
      }
    }
    
    _outputBuffer.writeBits(_huffmanTables.length, _TABLE_COUNT_BITS);
    _outputBuffer.writeBits(_selectors.length, _SELECTOR_COUNT_BITS);
    
    /* write table selectors */
    List<int> selectorsSymbols = new List<int>.generate(_TABLE_COUNT_MAX, (x)=>x);
    List<int> selectorsEncoded = _mtfEncode(_selectors, selectorsSymbols);
    
    for (int selectorCode in selectorsEncoded) {
      for (int i = 0; i < selectorCode; i++) {
        _outputBuffer.writeBit(1);
      }
      _outputBuffer.writeBit(0);
    }
    
    /* write huffman tables */
    for (List<_HuffmanCode> huffmanTable in _huffmanTables) {
      int currentLevel = huffmanTable[0].len;
      _outputBuffer.writeBits(currentLevel, _LEVEL_BITS);
      
      for (_HuffmanCode huffmanCode in huffmanTable) {
        while (currentLevel < huffmanCode.len) {
          _outputBuffer.writeBits(2, 2);
          currentLevel++;
        }
        while (currentLevel > huffmanCode.len) {
          _outputBuffer.writeBits(3, 2);
          currentLevel--;
        }
        
        _outputBuffer.writeBit(0);
      }
    }
    
    /* write symbols */
    for (int group = 0, bufferIndex = 0; group < _selectors.length; group++) {
      int table = _selectors[group];
      int groupSize = min(_GROUP_SIZE, _compressedBlock.length - bufferIndex);
      
      for (int groupIndex = 0; groupIndex < groupSize; groupIndex++) {
        int symbol = _compressedBlock[bufferIndex++];
        _HuffmanCode huffmanCode = _huffmanTables[table][symbol];
        _outputBuffer.writeBits(huffmanCode.code, huffmanCode.len);
      }
    }
  }
  
  void _writeFooter() {
    _outputBuffer.writeBits(_FINISH_SIGNATURE_HIGH, 24);
    _outputBuffer.writeBits(_FINISH_SIGNATURE_LOW, 24);
    _outputBuffer.writeBits(_fileCrc.getDigest(), 32);
  }
  
  void _writeHeader() {
    _outputBuffer.writeBits(_BZIP_SIGNATURE, 24);
    _outputBuffer.writeByte('0'.codeUnitAt(0) + _blockSizeFactor);
  }
  
  List<int> _readBlock() {
    List<int> result =  _input.sublist(0, _inputSize);
    _inputSize = 0;
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
  
  List _burrowsWheelerTransform(List<int> _buffer) {
    List<int> y = _buffer.map((x) => x + 1).toList();
    String s = new String.fromCharCodes(y);
    SuffixArray suffixArray = new SuffixArray(s + s);
    List<int> sortedSuffixes = suffixArray.getSortedSuffixes();
    
    int originPointer;
    List<int> result = new List<int>(_buffer.length);
    int resultIndex = 0;
    
    for (int b in sortedSuffixes) {
      if (b < _buffer.length) {
        if (b == 0) {
          originPointer = resultIndex;
        }
        result[resultIndex++] = _buffer[(b + _buffer.length - 1) % _buffer.length];
      }
    }
    
    return [result, originPointer];
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
  
  List<int> _calculateSymbols(List<bool> inUse) {
    List<int> symbols = new List<int>(256);
    int symbolIndex = 0;
    for (int i = 0; i < 256; i++) {
      if (inUse[i]) {
        symbols[symbolIndex++] = i;
      }
    }
    symbols = symbols.sublist(0, symbolIndex);
    return symbols;
  }
  
  List<int> _mtfEncode(List<int> buffer, List<int> symbols) {
    List<int> result = new List<int>(buffer.length);
    List<int> mtf = new List<int>.from(symbols);
    
    for (int index = 0; index < buffer.length; index++) {
      int symbolIndex = mtf.indexOf(buffer[index]);
      
      for (int index = symbolIndex; index > 0; index--) {
        mtf[index] = mtf[index - 1];
      }
      mtf[0] = buffer[index];
      
      result[index] = symbolIndex;
    }
    
    return result;
  }

  List<int> _rleEncode2(List<int> buffer, int alphaSize) {
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
    
    result[resultIndex++] = alphaSize - 1;
    
    result = result.sublist(0, resultIndex);
    return result;
  }
    
  List _calculateHuffmanTables(List<int> block, int alphaSize) {
    /* initialize */
    List<List<_HuffmanCode>> huffmanTables = _initialHuffmanTables(block, alphaSize);
    int tableCount = huffmanTables.length;
 
    for (int pass = 0; pass < _HUFFMAN_PASSES; pass++) {
      List<List<int>> frequencyTables = new List<List<int>>.generate(tableCount, 
                                            (_) => new List<int>.filled(alphaSize, 0));
      List<int> selectors = _calculateSelectors(block, huffmanTables);
      
      /* update frequency table */
      for (int group = 0; group < selectors.length; group++) {
        for (int symbol in _getGroupData(block, group)) {
          frequencyTables[selectors[group]][symbol]++;
        }
      }
      
      /* generate new tables */
      for (int table = 0; table < tableCount; table++) {
        _HuffmanEncoder encoder = new _HuffmanEncoder(alphaSize, _MAX_HUFFMAN_LEN_FOR_ENCODING);
        huffmanTables[table] = encoder.generate(frequencyTables[table]);
      }
    }
    
    return huffmanTables;
  }
  
  List<int> _calculateSelectors(List<int> block, List<List<_HuffmanCode>> huffmanTables) {
    int selectorCount = (block.length + _GROUP_SIZE - 1) ~/ _GROUP_SIZE;
    List<int> selectors = new List<int>(selectorCount);
    
    for (int group = 0; group < selectorCount; group++) {
      selectors[group] = _selectHuffmanTable(_getGroupData(block, group), huffmanTables);
    }
    
    return selectors;
  }
  
  List<List<_HuffmanCode>> _initialHuffmanTables(List<int> _buffer, int alphaSize) {
    List<List<_HuffmanCode>> huffmanTables;
    int tableCount = _TABLE_COUNT_MAX;
    
    int totalSymbolCount = 0;
    List<int> symbolCounts = new List<int>.filled(_MAX_ALPHA_SIZE, 0);
    for (int value in _buffer) {
      symbolCounts[value]++;
      totalSymbolCount++;
    }
    
    huffmanTables = new List<List<_HuffmanCode>>(tableCount);
    
    int remainingSymbols = totalSymbolCount;
    int groupStart = 0;
    for (int table = tableCount - 1; table >= 0; table--) {
      int targetCount = remainingSymbols ~/ (table + 1);
      int groupEnd = groupStart;
      int currentCount = 0;
      while (currentCount < targetCount) {
        currentCount += symbolCounts[groupEnd++];
      }
      
      huffmanTables[table] = new List<_HuffmanCode>.generate(alphaSize, (i) => new _HuffmanCode(0, 
                                                     (groupStart <= i && i < groupEnd) ? 0 : 1));
      
      groupStart = groupEnd;
      remainingSymbols -= currentCount;
    }
    
    return huffmanTables;
  }

  List<int> _getGroupData(List<int> block, int group) {
    int groupStart = group * _GROUP_SIZE;
    int groupEnd = min(groupStart + _GROUP_SIZE, block.length);
    List<int> groupSymbols = block.sublist(groupStart, groupEnd);
    
    return groupSymbols;
  }
  
  int _selectHuffmanTable(List<int> groupData, List<List<_HuffmanCode>> huffmanTables) {
    int bestTable = 0;
    int bestCost = 0xFFFFFFFF;
    
    for (int table = 0; table < huffmanTables.length; table++) {
      int tableCost = 0;
      for (int symbol in groupData) {
        tableCost += huffmanTables[table][symbol].len;
      }
      if (tableCost < bestCost) {
        bestTable = table;
        bestCost = tableCost;
      }
    }
    
    return bestTable;
  }
  
}
