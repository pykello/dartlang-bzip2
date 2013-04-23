part of bzip2;

const int _TABLE_BITS  = 9;

class _HuffmanDecoder {
  int _maxBitCount;
  int _symbolCount;
  List<int> limits;
  List<int> positions;
  List<int> symbols;
  List<int> lengths;
  
  _HuffmanDecoder(this._maxBitCount, this._symbolCount) {
    limits = new List<int>(_maxBitCount + 1);
    positions = new List<int>(_maxBitCount + 1);
    symbols = new List<int>(_symbolCount);
    lengths = new List<int>(1 << _TABLE_BITS);
  }
  
  bool setCodeLengths(List<int> codeLengths) {
    List<int> lenCounts = new List<int>.filled(_maxBitCount + 1, 0);
    List<int> tmpPositions = new List<int>(_maxBitCount + 1);
    for (int symbol = 0; symbol < _symbolCount; symbol++)
    {
      int len = codeLengths[symbol];
      if (len > _maxBitCount)
        return false;
      lenCounts[len]++;
      symbols[symbol] = 0xFFFFFFFF;
    }
    lenCounts[0] = 0;
    positions[0] = limits[0] = 0;
    int startPos = 0;
    int index = 0;
    int kMaxValue = (1 << _maxBitCount);
    for (int i = 1; i <= _maxBitCount; i++)
    {
      startPos += lenCounts[i] << (_maxBitCount - i);
      if (startPos > kMaxValue)
        return false;
      limits[i] = (i == _maxBitCount) ? kMaxValue : startPos;
      positions[i] = positions[i - 1] + lenCounts[i - 1];
      tmpPositions[i] = positions[i];
      if(i <= _TABLE_BITS)
      {
        int limit = (limits[i] >> (_maxBitCount - _TABLE_BITS));
        for (; index < limit; index++)
          lengths[index] = i;
      }
    }
    for (int symbol = 0; symbol < _symbolCount; symbol++)
    {
      int len = codeLengths[symbol];
      if (len != 0)
        symbols[tmpPositions[len]++] = symbol;
    }
    return true;
  }
  
  int decodeSymbol(BitBuffer buffer) {
    int numBits;
    int value = buffer.peekBits(_maxBitCount);
    if (value < limits[_TABLE_BITS])
      numBits = lengths[value >> (_maxBitCount - _TABLE_BITS)];
    else
      for (numBits = _TABLE_BITS + 1; value >= limits[numBits]; numBits++);
    buffer.move(numBits);
    int index = positions[numBits] +
      ((value - limits[numBits - 1]) >> (_maxBitCount - numBits));
    if (index >= _symbolCount)
      return 0xFFFFFFFF;
    return symbols[index];
  }
}


