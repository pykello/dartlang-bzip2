part of bzip2;

const int _BZIP2_CRC_POLY = 0x04c11db7;

class _Bzip2Crc
{
  int _value;
  List<int> _crcTable = new List<int>(256);
  
  _Bzip2Crc() {
    _initCrcTable();
    reset();
  }
  
  void reset() { 
    _value = 0xFFFFFFFF; 
  }
  
  void updateByte(int b) {
    _value = _crcTable[(_value >> 24) ^ b] ^ ((_value << 8) & 0xFFFFFFFF); 
  }
  
  int getDigest() { 
    return _value ^ 0xFFFFFFFF; 
  }
  
  void _initCrcTable() {
    for (int i = 0; i < 256; i++)
    {
      int r = (i << 24) & 0xFFFFFFFF;
      for (int j = 8; j > 0; j--) {
        int sr = (r << 1) & 0xFFFFFFFF;
        r = ((r & 0x80000000) != 0) ? (sr ^ _BZIP2_CRC_POLY) : sr;
      }
      _crcTable[i] = r;
    }
  }
}

class _Bzip2CombinedCrc
{
  int _value;

  _Bzip2CombinedCrc() {
    reset();
  }
  
  void reset() { 
    _value = 0; 
  }
  
  void update(int v) {
    int a = (_value << 1) & 0xFFFFFFFF;
    _value = (a | (_value >> 31)) ^ v; 
  }
  
  int getDigest() { 
    return _value ; 
  }
}

int _calculateBlockCrc(List<int> block) {
  _Bzip2Crc blockCrc = new _Bzip2Crc();
  
  for (int symbol in block) {
    blockCrc.updateByte(symbol);
  }
  
  return blockCrc.getDigest();
}