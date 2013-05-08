part of bzip2;

/* state codes */
const int _STATE_INIT                 = 0;
const int _STATE_READ_SIGNATURES      = 1;
const int _STATE_READ_BLOCK           = 2;
const int _STATE_DECODE_BLOCK_1       = 3;
const int _STATE_DECODE_BLOCK_2       = 4;
const int _STATE_STREAM_END           = 6;
const int _STATE_ERROR                = 7;

class _Bzip2Decompressor implements _Bzip2Coder {
  int _state = _STATE_INIT;
  bool _noMoreData = false;
  int _blockSize;
  
  int _originPointer;
  List<int> _charCounters = new List<int>(256 + _MAX_BLOCK_SIZE);
  List<int> _huffmanBlock;
  List<int> _symbols;
  
  BitBuffer _buffer = new BitBuffer(_MAX_BYTES_REQUIRED);
  int _outputIndex;
  List<int> _output = [];
  
  bool _checkCrc;
  _Bzip2Crc _crcCoder = new _Bzip2Crc();
  _Bzip2CombinedCrc _combinedCrc = new _Bzip2CombinedCrc();
  int _blockCrc;
  
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
        result = ((_noMoreData && !_buffer.isEmpty()) || _buffer.isFull());
        break;
      case _STATE_DECODE_BLOCK_1:
      case _STATE_DECODE_BLOCK_2:
        result = true;
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
        _readBlock();
        break;
      case _STATE_DECODE_BLOCK_1:
        _decodeBlock1();
        break;
      case _STATE_DECODE_BLOCK_2:
        _decodeBlock2();
        break;
      case _STATE_STREAM_END:
        break;
    }
  }
  
  void _readHeaders() {
    List<int> signature = _buffer.readBytes(3);
    if (!_listsMatch(signature, _BZIP_SIGNATURE)) {
      throw new StateError("invalid file signature");
    }
    
    int dicSize = (_buffer.readByte() - 0x30) * _BLOCK_SIZE_STEP;
    if (dicSize <= 0 || dicSize > _MAX_BLOCK_SIZE) {
      throw new StateError("invalid dic size");
    }
    
    _state = _STATE_READ_SIGNATURES;
  }
  
  void _readSignatures() {
    List<int> signature = _buffer.readBytes(6);
    int crc = _buffer.readBits(32);
    if (_listsMatch(signature, _BLOCK_SIGNATURE)) {
      if (_checkCrc) {
        _blockCrc = crc;
        _combinedCrc.update(_blockCrc);
      }
      _state = _STATE_READ_BLOCK; 
    }
    else if(_listsMatch(signature, _FINISH_SIGNATURE)) {
      if (_checkCrc && _combinedCrc.getDigest() != crc) {
        throw new StateError("file CRC failed");
      }
      _state = _STATE_STREAM_END;
    }
    else {
      throw new StateError("invalid block signature");
    }
  }
  
  void _readBlock() {
    _readCompressedBlock();
    _decodeSymbols();
    
    _state = _STATE_DECODE_BLOCK_1;
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
    
    int symbolCount = 0;
    List<int> symbols = new List<int>(256);
    
    List<bool> inUse16 = new List<bool>(16);
    List<bool> inUse = new List<bool>.filled(256, false);
    
    for (int i = 0; i < 16; i++) {
      inUse16[i] = (_buffer.readBit() == 1);
    }
    
    for (int i = 0; i < 256; i++) {
      if (inUse16[i >> 4]) {
        inUse[i] = (_buffer.readBit() == 1);
        if (inUse[i]) {
          symbols[symbolCount++] = i;
        }
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
  
  void _decodeSymbols() {
    List<int> rleDecodedBlock = _rleDecode2(_huffmanBlock);
    List<int> mtfDecodedBlock = _mtfDecode(rleDecodedBlock, _symbols);
    for (int i = 0; i < 256; i ++) 
      _charCounters[i] = 0;
    _blockSize = 0;
    for (int symbol in mtfDecodedBlock) {
      _charCounters[symbol]++;
      _charCounters[256 + _blockSize++] = symbol;
    }
  }

  void _decodeBlock1() {
    if (_originPointer >= _blockSize) {
      throw new StateError("block size and origin pointer don't match");
    }
    
    int sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += _charCounters[i];
      _charCounters[i] = sum - _charCounters[i];
    }
    int i = 0;
    do {
      _charCounters[256 + _charCounters[_charCounters[256 + i] & 0xFF]++] |= (i << 8);
    } while(++i < _blockSize);
    
    _state = _STATE_DECODE_BLOCK_2;
  }
  
  void _decodeBlock2() {
    int idx = _charCounters[256 + _originPointer] >> 8;
    int tPos = _charCounters[256 + idx];
    int prevByte = (tPos & 0xFF);
    int numReps = 0;
    
    int remainingSymbols = _blockSize;
    List<int> bwt = _charCounters.sublist(256, 256 + _blockSize).map((x) => (x >> 8)).toList();
    
    _beginOutput();
    
    do {
      int b = (tPos & 0xFF);
      tPos = _charCounters[256 + (tPos >> 8)];
      
      if (numReps == _RLE_MODE_REP_SIZE)
      {
        for (; b > 0; b--) {
          _writeOutput(prevByte);
        }
        numReps = 0;
        continue;
      }
      if (b != prevByte)
        numReps = 0;
      numReps++;
      prevByte = b;
      _writeOutput(b);
      
    } while(--remainingSymbols != 0);
    
    _endOutput();
        
    _state = _STATE_READ_SIGNATURES;
  }
  
  void _beginOutput() {
    _outputIndex = 0;
    _output = new Uint8List(_MAX_BLOCK_SIZE);
    if (_checkCrc) {
      _crcCoder.reset();
    }
  }
  
  void _writeOutput(int byte) {
    if (_outputIndex == _output.length) {
      Uint8List newOutput = new Uint8List(_output.length * 2);
      newOutput.setRange(0, _output.length, _output);
      _output = newOutput;
    }
    _output[_outputIndex++] = byte;
    if (_checkCrc) {
      _crcCoder.updateByte(byte);
    }
  }
  
  void _endOutput() {
    _output = _output.sublist(0, _outputIndex);
    if (_checkCrc && _crcCoder.getDigest() != _blockCrc) {
      throw new StateError("block CRC failed");
    }
  }
}

bool _listsMatch(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
