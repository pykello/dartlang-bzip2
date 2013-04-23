part of bzip2;

class BitBuffer {
  int _maxSize;
  List<int> _buffer;
  int _bufferSize = 0;
  int _bufferIndex = 0;
  int _bufferBitmask = 0;
  
  BitBuffer(int maxSize) {
    this._maxSize = maxSize * 8;
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
      result = result * 2 + readBit();
    }
    return result;
  }
  
  void move(int cnt) {
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
  
  void writeByte(int byte) {
    if (_bufferSize >= _maxSize - 7) {
      if (_bufferIndex == 0) {
        throw new StateError("buffer full");
      }
      for (int i = 0; i < _bufferSize - _bufferIndex; i++) {
        _buffer[i] = _buffer[_bufferIndex + i];
      }
      _bufferSize -= _bufferIndex;
      _bufferIndex = 0;
    }
    for (int i = 7; i >= 0; i--) {
      _buffer[_bufferSize++] = (byte & (1 << i)) ~/ (1 << i);
    }
  }
  
  bool isFull() {
    return _bufferSize - _bufferIndex >= _maxSize - 7;
  }
  
  bool isEmpty() {
    return _bufferSize - _bufferIndex == 0;
  }
}
