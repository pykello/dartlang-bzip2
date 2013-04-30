part of bzip2;

class _Mtf8Encoder {
  List<int> _buffer = new List<int>(256);

  int findAndMove(int v)
  {
    int pos;
    for (pos = 0; _buffer[pos] != v; pos++);
    int resPos = pos;
    for (; pos >= 8; pos -= 8)
    {
      _buffer[pos] = _buffer[pos - 1];
      _buffer[pos - 1] = _buffer[pos - 2];
      _buffer[pos - 2] = _buffer[pos - 3];
      _buffer[pos - 3] = _buffer[pos - 4];
      _buffer[pos - 4] = _buffer[pos - 5];
      _buffer[pos - 5] = _buffer[pos - 6];
      _buffer[pos - 6] = _buffer[pos - 7];
      _buffer[pos - 7] = _buffer[pos - 8];
    }
    for (; pos > 0; pos--)
      _buffer[pos] = _buffer[pos - 1];
    _buffer[0] = v;
    return resPos;
  }
  
  int set(int pos, int value) {
    _buffer[pos] = value;
  }
  
  int get(int pos) {
    return _buffer[pos];
  }
}