part of bzip2;

/* state codes */
const int _STATE_INIT                 = 0;
const int _STATE_READ_SIGNATURES      = 1;
const int _STATE_READ_BLOCK           = 2;
const int _STATE_STREAM_END           = 3;
const int _STATE_ERROR                = 4;

class _Bzip2Decompressor implements _Bzip2Coder {
  
  /* decompressor state */
  int _state = _STATE_INIT;
  bool _checkCrc;
  
  /* input state */
  BitBuffer _buffer = new BitBuffer(_MAX_BYTES_REQUIRED);
  bool _noMoreData = false;
  _Bzip2CombinedCrc _fileCrc = new _Bzip2CombinedCrc();
  
  /* output state */
  int _outputIndex;
  List<int> _output = [];
  
  /* decompressed block state */
  int _expectedBlockCrc;
  int _originPointer;
  List<int> _huffmanBlock;
  List<int> _symbols;
  
  _Bzip2Decompressor(this._checkCrc);
  
  void writeByte(int byte) {
    _buffer.writeByte(byte);
  }
  
  void setEndOfData() {
    _noMoreData = true;
  }
  
  List<int> readOutput() {
    List<int> result = _output;
    _output = [];
    return result;
  }
  
  bool canProcess() {
    bool result = false;
    switch (_state) {
      case _STATE_INIT:
      case _STATE_READ_SIGNATURES:
      case _STATE_READ_BLOCK:
        result = ((_noMoreData && !_buffer.isEmpty()) || _buffer.freeBitCount() < 8);
        break;
      default:
        result = false;
    }
    return result;
  }
  
  void process() {
    switch (_state) {
      case _STATE_INIT:
        _readHeaders();
        break;
      case _STATE_READ_SIGNATURES:
        _readSignatures();
        break;
      case _STATE_READ_BLOCK:
        _decompressBlock();
        break;
      case _STATE_STREAM_END:
        break;
    }
  }
  
  void _readHeaders() {
    int signature = _buffer.readBits(24);
    if (signature != _BZIP_SIGNATURE) {
      throw new StateError("invalid file signature");
    }
    
    int dicSize = (_buffer.readByte() - 0x30) * _BLOCK_SIZE_STEP;
    if (dicSize <= 0 || dicSize > _MAX_BLOCK_SIZE) {
      throw new StateError("invalid dic size");
    }
    
    _state = _STATE_READ_SIGNATURES;
  }
  
  void _readSignatures() {
    int sigHigh = _buffer.readBits(24);
    int sigLow = _buffer.readBits(24);
    int crc = _buffer.readBits(32);
    
    /* new block ? */
    if (sigHigh == _BLOCK_SIGNATURE_HIGH && sigLow == _BLOCK_SIGNATURE_LOW) {
      _expectedBlockCrc = crc;
      _state = _STATE_READ_BLOCK; 
    }
    
    /* file ended ? */
    else if(sigHigh == _FINISH_SIGNATURE_HIGH && sigLow == _FINISH_SIGNATURE_LOW) {
      if (_checkCrc && _fileCrc.getDigest() != crc) {
        throw new StateError("file crc failed");
      }
      _state = _STATE_STREAM_END;
    }
    
    /* invalid signature ? */
    else {
      throw new StateError("invalid block signature");
    }
  }
  
  void _decompressBlock() {
    _readCompressedBlock();
    
    _output = _decodeHuffmanBlock(_huffmanBlock, _symbols);
    
    if (_checkCrc) {
      int blockCrc = _calculateBlockCrc(_output);
      if (blockCrc != _expectedBlockCrc) {
        throw new StateError("block crc failed");
      }
      
      _fileCrc.update(blockCrc);
    }
    
    _state = _STATE_READ_SIGNATURES;
  }
  
  void _readCompressedBlock() {
    bool randomized = (_buffer.readBit() == 1);
    if (randomized) {
      throw new StateError("randomized mode is deprecated");
    }
    
    int originPointer = _buffer.readBits(_ORIGIN_BIT_COUNT);
    if (originPointer >= _MAX_BLOCK_SIZE) {
      throw new StateError("invalid origin pointer");
    }
    
    List<bool> inUse16 = new List<bool>(16);
    for (int i = 0; i < 16; i++) {
      inUse16[i] = (_buffer.readBit() == 1);
    }
    
    List<bool> inUse = new List<bool>.filled(256, false);
    for (int i = 0; i < 256; i++) {
      if (inUse16[i >> 4]) {
        inUse[i] = (_buffer.readBit() == 1);
      }
    }
    
    int symbolCount = 0;
    List<int> symbols = new List<int>(256);
    for (int i = 0; i < 256; i++) {
      if (inUse[i]) {
        symbols[symbolCount++] = i;
      }
    }
    
    if (symbolCount == 0) {
      throw new StateError("symbols used cannot be zero");
    }
    
    int tableCount = _buffer.readBits(_TABLE_COUNT_BITS);
    if (tableCount < _TABLE_COUNT_MIN || tableCount > _TABLE_COUNT_MAX) {
      throw new StateError("invalid table count");
    }
    
    int selectorCount = _buffer.readBits(_SELECTOR_COUNT_BITS);
    if (selectorCount < 1 || selectorCount > _SELECTOR_COUNT_MAX) {
      throw new StateError("invalid selector count");
    }
    
    List<int> selectors = _readSelectors(selectorCount, tableCount);
    List<_HuffmanDecoder> huffmanDecoders = _readHuffmanTables(tableCount, 
                                                                symbolCount);
    
    List<int> huffmanBlock = _readHuffmanBlock(selectors, huffmanDecoders, 
                                               symbolCount);
    
    _originPointer = originPointer;
    _symbols = symbols;
    _huffmanBlock = huffmanBlock;
  }
  
  List<_HuffmanDecoder> _readHuffmanTables(int tableCount, int symbolCount) {
    List<_HuffmanDecoder> _huffmanDecoders = new List<_HuffmanDecoder>(tableCount);
    
    for(int table = 0; table < tableCount; table++) {
      List<int> lengthArray = new List<int>.filled(_MAX_ALPHA_SIZE, 0);
      int currentLevel = _buffer.readBits(_LEVEL_BITS);
      
      for (int symbol = 0; symbol < symbolCount + 2; symbol++) {
        while (_buffer.readBit() == 1) {
          currentLevel += 1 - (_buffer.readBit() * 2);
        }
        
        if (currentLevel < 1 || currentLevel > _MAX_HUFFMAN_LEN) {
          throw new StateError("invalid len");
        }
        
        lengthArray[symbol] = currentLevel;
      }
      
      _huffmanDecoders[table] = new _HuffmanDecoder(_MAX_HUFFMAN_LEN, _MAX_ALPHA_SIZE); 
      if (!_huffmanDecoders[table].setCodeLengths(lengthArray)) {
        throw new StateError("invalid len array");
      }
    }
    
    return _huffmanDecoders;
  }

  List<int> _readSelectors(int selectorCount, int tableCount) {
    List<int> mtfEncodedSelectorList = new List<int>(selectorCount);
    
    for (int i = 0; i < selectorCount; i++) {
      int mtfEncodedSelector = 0;
      while (_buffer.readBit() == 1) {
        mtfEncodedSelector++;
      }
      
      mtfEncodedSelectorList[i] = mtfEncodedSelector;
    }
    
    List<int> selectorsSymbols = new List<int>.generate(_TABLE_COUNT_MAX, (x)=>x);
    List<int> selectorList = _mtfDecode(mtfEncodedSelectorList, selectorsSymbols);
    
    for (int selector in selectorList) {
      if (selector >= tableCount) {
        throw new StateError("invalid selector");
      }
    }
    
    return selectorList;
  }
  
  List<int> _readHuffmanBlock(List<int> _selectors, 
      List<_HuffmanDecoder> _huffmanDecoders, 
      int symbolCount) {
    List<int> result = new List<int>(_GROUP_SIZE * _selectors.length + 2);
    int resultSize = 0;
    
    for (int group = 0; group < _selectors.length; group++) {
      bool isLastGroup = (group + 1 == _selectors.length);
      int selector = _selectors[group];
      _HuffmanDecoder huffmanDecoder = _huffmanDecoders[selector];
      
      for (int i = 0; i < _GROUP_SIZE; i++) {
        int symbol = huffmanDecoder.decodeSymbol(_buffer);
        
        if (symbol <= symbolCount) {
          result[resultSize++] = symbol;
        }
        else if (symbol == symbolCount + 1 && isLastGroup) {
          break;
        }
        else {
          throw new StateError("invalid next symbol");
        }
      }
    }
    
    result = result.sublist(0, resultSize);
    return result;
  }
  
  List<int> _decodeHuffmanBlock(List<int> huffmanBlock, List<int> symbols) {
    List<int> rle2DecodedBlock = _rleDecode2(huffmanBlock);
    List<int> mtfDecodedBlock = _mtfDecode(rle2DecodedBlock, symbols);
    List<int> bwtDecodedBlock = _bwtDecode(mtfDecodedBlock);
    List<int> rle1DecodedBlock = _rleDecode1(bwtDecodedBlock);
    
    return rle1DecodedBlock;
  }
  
  List<int> _mtfDecode(List<int> buffer, List<int> symbols) {
    List<int> result = new List<int>(buffer.length);
    List<int> mtf = new List<int>.from(symbols);
    
    for (int index = 0; index < buffer.length; index++) {
      int symbolIndex = buffer[index];
      result[index] = mtf[symbolIndex];
      
      for (int index = symbolIndex; index > 0; index--) {
        mtf[index] = mtf[index - 1];
      }
      mtf[0] = result[index];
    }
    
    return result;
  }
  
  List<int> _rleDecode2(List<int> block) {
    List<int> result = new List<int>(_MAX_BLOCK_SIZE);
    int resultSize = 0;
    int runPower = 0;
    int runLength = 0;
    
    for (int symbol in block) {
      if (symbol < 2) {
        runLength += (symbol + 1) << runPower;
        runPower++;
      }
      else {
        for (int i = 0; i < runLength; i++) {
          result[resultSize++] = 0;
        }
        result[resultSize++] = symbol - 1;
        runLength = 0;
        runPower = 0;
      }
    }
    
    for (int i = 0; i < runLength; i++) {
      result[resultSize++] = 0;
    }
    
    result = result.sublist(0, resultSize);
    return result;
  }
  
  List<int> _bwtDecode(List<int> block) {
    List<int> charCounters = new List<int>.filled(256, 0);
    for (int symbol in block) {
      charCounters[symbol]++;
    }
    
    List<int> nextIndex = new List<int>(256);
    nextIndex[0] = 0;
    for (int i = 1; i < 256; i++) {
      nextIndex[i] = nextIndex[i - 1] + charCounters[i - 1];
    }
    
    List<int> sorted = new List<int>(block.length);
    for (int i = 0; i < block.length; i++) {
      int symbol = block[i];
      sorted[nextIndex[symbol]++] = i;
    }
    
    List<int> result = new List<int>(block.length);
    int currentIndex = sorted[_originPointer];
    for (int i = 0; i < block.length; i++) {
      result[i] = block[currentIndex];
      currentIndex = sorted[currentIndex];
    }
    
    return result;
  }
  
  List<int> _rleDecode1(List<int> block) {
    List<int> result = new List<int>(_MAX_BLOCK_SIZE);
    int resultSize = 0;
    int lastSymbol = 0;
    int repeatCount = 0;
    
    for (int symbol in block) {
      /* make sure we have enough room */
      if (result.length < resultSize + 256) {
        List<int> newResult = new List<int>(result.length * 2);
        newResult.setRange(0, result.length, result);
        result = newResult;
      }
      
      /* rle sequence ? */
      if (repeatCount == _RLE_MODE_REP_SIZE) {
        for (int i = 0; i < symbol; i++) {
          result[resultSize++] = lastSymbol;
        }
        repeatCount = 0;
        lastSymbol = -1;
      }
      /* symbol ? */
      else {
        result[resultSize++] = symbol;
        repeatCount = (symbol == lastSymbol) ? repeatCount + 1 : 1;
        lastSymbol = symbol;
      }
    }
    
    result = result.sublist(0, resultSize);
    return result;
  }
}
