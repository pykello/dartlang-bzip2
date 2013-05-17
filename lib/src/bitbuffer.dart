part of bzip2;

class BitBuffer {
  List<int> _buffer;
  int _maxBufferSize;
  int _bufferSize = 0;
  int _bufferIndex = 0;
  
  BitBuffer(int maxSize) {
    this._maxBufferSize = maxSize * 8;
    this._buffer = new Int8List(maxSize * 8);
  }
  
  int readBit() {
    if (_bufferIndex >= _bufferSize) {
      throw new StateError("out of data");
    }
    return _buffer[_bufferIndex++];
  }
  
  int readBits(int cnt) {
    int result = 0;
    for (int i = 0; i < cnt; i++) {
      result = (result << 1) + readBit();
    }
    return result;
  }
  
  void move(int cnt) {
    if (_bufferIndex + cnt > _bufferSize) {
      throw new StateError("out of data");
    }
    _bufferIndex += cnt;
  }
  
  int peekBits(int cnt) {
    int result = readBits(cnt);
    _bufferIndex -= cnt;
    return result;
  }
  
  int readByte() {
    return readBits(8);
  }
  
  List<int> readBytes(int cnt) {
    List<int> result = new List<int>(cnt);
    for (int i = 0; i < cnt; i++) {
      result[i] = readByte();
    }
    return result;
  }
  
  void writeBit(int bit) {
    if (_bufferSize >= _maxBufferSize) {
      if (_bufferIndex == 0) {
        throw new StateError("buffer full");
      }
      for (int i = 0; i < _bufferSize - _bufferIndex; i++) {
        _buffer[i] = _buffer[_bufferIndex + i];
      }
      _bufferSize -= _bufferIndex;
      _bufferIndex = 0;
    }
    _buffer[_bufferSize++] = (bit == 0 ? 0 : 1);
  }
  
  void writeBits(int value, int cnt) {
    for (int i = 0; i < cnt; i++) {
      int bitmask = (1 << (cnt - 1 - i));
      writeBit((value & bitmask) == 0 ? 0 : 1);
    }
  }
  
  void writeByte(int byte) {
    writeBits(byte, 8);
  }
  
  void writeBytes(List<int> bytes) {
    for(int byte in bytes) {
      writeByte(byte);
    }
  }
  
  bool isEmpty() {
    return usedBitCount() == 0;
  }
  
  int usedBitCount() {
    return _bufferSize - _bufferIndex;
  }
  
  int freeBitCount() {
    return _maxBufferSize - usedBitCount();
  }
}
