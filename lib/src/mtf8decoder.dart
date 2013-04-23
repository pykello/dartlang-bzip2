part of bzip2;

class _Mtf8Decoder {
  final List<int> _buffer = new List<int>.filled(256, 0);  
  
  void add(int pos, int value) {
    _buffer[pos] = value;
  }
  
  int getHead() {
    return _buffer[0];
  }
  
  int getAndMove(int pos) {
    int prev = _buffer[pos];
    for (int i = pos; i > 0; i--) {
      _buffer[i] = _buffer[i - 1];
    }
    _buffer[0] = prev;
    
    return _buffer[0];
  }
}

