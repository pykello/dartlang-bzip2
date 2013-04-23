part of bzip2;

const int _MAX_BYTES_REQUIRED          = 1048576;
const int _BLOCK_SIZE_STEP             = 100000;
const int _MAX_BLOCK_SIZE              = 900000;
const int _MAX_ALPHA_SIZE              = 258;
const int _LEVEL_BITS                  = 5;
const int _MAX_HUFFMAN_LEN             = 20;
const int _RLE_MODE_REP_SIZE           = 4;

/* state codes */
const int _STATE_INIT                 = 0;
const int _STATE_READ_SIGNATURES      = 1;
const int _STATE_READ_BLOCK           = 2;
const int _STATE_DECODE_BLOCK_1       = 3;
const int _STATE_DECODE_BLOCK_2       = 4;
const int _STATE_DECODE_BLOCK_2_RAND  = 5;
const int _STATE_STREAM_END           = 6;
const int _STATE_ERROR                = 7;

/* signatures */
final List<int> _BZIP_SIGNATURE       = [0x42, 0x5a, 0x68];
final List<int> _FINISH_SIGNATURE     = [0x17, 0x72, 0x45, 0x38, 0x50, 0x90];
final List<int> _BLOCK_SIGNATURE      = [0x31, 0x41, 0x59, 0x26, 0x53, 0x59];

const int _ORIGIN_BIT_COUNT           = 24;

const int _TABLE_COUNT_BITS           = 3;
const int _TABLE_COUNT_MIN            = 2;
const int _TABLE_COUNT_MAX            = 6;

const int _GROUP_SIZE                 = 50;

const int _SELECTOR_COUNT_BITS        = 15;
const int _SELECTOR_COUNT_MAX         = (2 + (_MAX_BLOCK_SIZE ~/ _GROUP_SIZE));

class _Bzip2Decompressor {
  int _state = _STATE_INIT;
  bool _noMoreData = false;
  int _dicSize;
  int _tableCount;
  int _blockSize;
  int _alphaSize;
  _Mtf8Decoder _mtf;
  int _symbolsUsed;
  
  bool _randomized;
  int _originPointer;
  int _selectorCount;
  List<int> _selectors;
  List<_HuffmanDecoder> _huffmanDecoders; 
  List<int> _charCounters = new List<int>(256 + _MAX_BLOCK_SIZE);
  
  BitBuffer _buffer = new BitBuffer(_MAX_BYTES_REQUIRED);
  List<int> _output = [];
  List<int> _outputTemp = new Uint8List(_MAX_BLOCK_SIZE * 2);
  
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
      case _STATE_DECODE_BLOCK_2_RAND:
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
      case _STATE_DECODE_BLOCK_2_RAND:
        _decodeBlock2Rand();
        break;
      case _STATE_STREAM_END:
        print("done");
        break;
    }
  }
  
  void _readHeaders() {
    List<int> signature = _buffer.readBytes(3);
    if (!_listsMatch(signature, _BZIP_SIGNATURE)) {
      throw new StateError("invalid file signature");
    }
    
    _dicSize = (_buffer.readByte() - 0x30) * _BLOCK_SIZE_STEP;
    if (_dicSize <= 0 || _dicSize > _MAX_BLOCK_SIZE) {
      throw new StateError("invalid dic size");
    }
    
    _state = _STATE_READ_SIGNATURES;
  }
  
  void _readSignatures() {
    List<int> signature = _buffer.readBytes(6);
    List<int> crc32 = _buffer.readBytes(4);
    
    if (_listsMatch(signature, _BLOCK_SIGNATURE)) {
      _state = _STATE_READ_BLOCK; 
    }
    else if(_listsMatch(signature, _FINISH_SIGNATURE)) {
      _state = _STATE_STREAM_END;
    }
    else {
      throw new StateError("invalid block signature");
    }
  }
  
  void _readBlock() {
    _randomized = (_buffer.readBit() == 1);
    
    _originPointer = _buffer.readBits(_ORIGIN_BIT_COUNT);
    if (_originPointer >= _MAX_BLOCK_SIZE) {
      throw new StateError("invalid origin pointer");
    }
    
    _initializeMtfDecoder();
    _computeTableCount();
    _computeSelectorList();
    _initializeHuffmanDecoders();
    _decodeSymbols();
        
    if (_originPointer >= _blockSize) {
      throw new StateError("block size and origin pointer don't match");
    }
    
    _state = _STATE_DECODE_BLOCK_1;
  }
  
  void _initializeMtfDecoder() {
    _mtf = new _Mtf8Decoder();
    _symbolsUsed = 0;
    {
      List<bool> inUse16 = new List<bool>(16);
      for (int i = 0; i < 16; i++) {
        inUse16[i] = (_buffer.readBit() == 1);
      }
      for (int i = 0; i < 256; i++) {
        if (inUse16[i >> 4])
        {
          if (_buffer.readBit() == 1)
            _mtf.add(_symbolsUsed++, i);
        }
      }
      if (_symbolsUsed == 0) {
        throw new StateError("numInUse cannot be zero");
      }
    }
    _alphaSize = _symbolsUsed + 2;
  }

  void _computeTableCount() {
    _tableCount = _buffer.readBits(_TABLE_COUNT_BITS);
    if (_tableCount < _TABLE_COUNT_MIN || _tableCount > _TABLE_COUNT_MAX) {
      throw new StateError("invalid table count");
    }
    _huffmanDecoders = new List<_HuffmanDecoder>.generate(
          _tableCount, (int index) => new _HuffmanDecoder(_MAX_HUFFMAN_LEN, _MAX_ALPHA_SIZE));
  }

  void _computeSelectorList() {
    _selectorCount = _buffer.readBits(_SELECTOR_COUNT_BITS);
    if (_selectorCount < 1 || _selectorCount > _SELECTOR_COUNT_MAX) {
      throw new StateError("invalid selector count");
    }
    
    _selectors = new List<int>(_selectorCount);
    
    List<int> mtfPos = new List<int>(_TABLE_COUNT_MAX);
    for (int i = 0; i < _tableCount; i++) {
      mtfPos[i] = i;
    }
    
    for (int i = 0; i < _selectorCount; i++) {
      int j = 0;
      while (_buffer.readBit() == 1) {
        j++;
        if (j > _tableCount) {
          throw new StateError("error while parsing");
        }
      }
      int tmp = mtfPos[j];
      for (;j > 0; j--) {
        mtfPos[j] = mtfPos[j - 1];
      }
      mtfPos[0] = tmp;
      _selectors[i] = tmp;
    }
  }
  
  void _initializeHuffmanDecoders() {
    for(int t = 0; t < _tableCount; t++)
    {
      List<int> lens = new List<int>.filled(_MAX_ALPHA_SIZE, 0);
      int len = _buffer.readBits(_LEVEL_BITS);
      for (int i = 0; i < _alphaSize; i++)
      {
        for (;;)
        {
          if (len < 1 || len > _MAX_HUFFMAN_LEN) {
            throw new StateError("invalid len");
          }
          if (_buffer.readBit() == 0) {
            break;
          }
          len += 1 - (_buffer.readBit() * 2);
        }
        lens[i] = len;
      }
      if (!_huffmanDecoders[t].setCodeLengths(lens)) {
        throw new StateError("invalid len array");
      }
    }
  }


  void _decodeSymbols() {
    for (int i = 0; i < 256; i ++) 
      _charCounters[i] = 0;
    _blockSize = 0;
    int groupIndex = 0;
    int groupSize = 0;
    _HuffmanDecoder huffmanDecoder;
    int runPower = 0;
    int runCounter = 0;
    
    while (true) {
      if (groupSize == 0)
      {
        if (groupIndex >= _selectorCount) {
          throw new StateError("invalid group index");
        }
        groupSize = _GROUP_SIZE;
        huffmanDecoder = _huffmanDecoders[_selectors[groupIndex++]];
      }
      groupSize--;
      int nextSym = huffmanDecoder.decodeSymbol(_buffer);
      
      if (nextSym < 2)
      {
        runCounter += ((nextSym + 1) << runPower++);
        if (_MAX_BLOCK_SIZE - _blockSize < runCounter) {
          throw new StateError("invalid run counter");
        }
        continue;
      }
      if (runCounter != 0)
      {
        int b = _mtf.getHead();
        _charCounters[b] += runCounter;
        do {
          _charCounters[256 + _blockSize++] = b;
        } 
        while(--runCounter != 0);
        runPower = 0;
      }
      if (nextSym <= _symbolsUsed)
      {
        int b = _mtf.getAndMove(nextSym - 1);
        if (_blockSize >= _MAX_BLOCK_SIZE) {
          throw new StateError("invalid block size");
        }
        _charCounters[b]++;
        _charCounters[256 + _blockSize++] = b;
      }
      else if (nextSym == _symbolsUsed + 1)
        break;
      else {
        throw new StateError("invalid next symbol");
      }
    }
  }

  void _decodeBlock1() {
    int sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += _charCounters[i];
      _charCounters[i] = sum - _charCounters[i];
    }
    int i = 0;
    do {
      _charCounters[256 + _charCounters[_charCounters[256 + i] & 0xFF]++] |= (i << 8);
    } while(++i < _blockSize);
    
    _state = (_randomized ? _STATE_DECODE_BLOCK_2_RAND : _STATE_DECODE_BLOCK_2);
  }
  
  void _decodeBlock2() {
    int idx = _charCounters[256 + _originPointer] >> 8;
    int tPos = _charCounters[256 + idx];
    int prevByte = (tPos & 0xFF);
    int numReps = 0;
    int blockIndex = 0;
    
    int blockSize = _blockSize;
    
    do {
      int b = (tPos & 0xFF);
      tPos = _charCounters[256 + (tPos >> 8)];
      
      if (numReps == _RLE_MODE_REP_SIZE)
      {
        for (; b > 0; b--) {
          _outputTemp[blockIndex++] = prevByte;
        }
        numReps = 0;
        continue;
      }
      if (b != prevByte)
        numReps = 0;
      numReps++;
      prevByte = b;
      _outputTemp[blockIndex++] = b;
      
    } while(--blockSize != 0);
    
    _output = _outputTemp.sublist(0, blockIndex);
        
    _state = _STATE_READ_SIGNATURES;
  }
  
  void _decodeBlock2Rand() {
    throw new StateError("randomized not implemented yet");
    _state = _STATE_READ_SIGNATURES;
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
