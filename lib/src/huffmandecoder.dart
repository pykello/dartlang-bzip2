part of bzip2;

const int _TABLE_BITS  = 9;

class _HuffmanDecoder {
  int _maxLength;
  int _symbolCount;
  List<int> maxValueWithLength;
  List<int> minPosWithLength;
  List<int> symbols;
  List<int> lengths;
  
  _HuffmanDecoder(this._maxLength, this._symbolCount) {
    maxValueWithLength = new List<int>(_maxLength + 1);
    minPosWithLength = new List<int>(_maxLength + 1);
    symbols = new List<int>(_symbolCount);
    lengths = new List<int>(1 << _TABLE_BITS);
  }
  
  bool setCodeLengths(List<int> codeLengths) {
    List<int> lengthCount = new List<int>.filled(_maxLength + 1, 0);
    for (int symbol = 0; symbol < _symbolCount; symbol++) {
      lengthCount[codeLengths[symbol]]++;    
    }
    
    minPosWithLength[0] = 0;
    maxValueWithLength[0] = -1;
    int startValue = 0;
    int treeSize = (1 << _maxLength);
    
    for (int length = 1; length <= _maxLength; length++) {
      int subtreeSize = 1 << (_maxLength - length);
      int valueCount = lengthCount[length] * subtreeSize;
      maxValueWithLength[length] = startValue + valueCount - 1;
      minPosWithLength[length] = minPosWithLength[length - 1] + lengthCount[length - 1];
      
      startValue += valueCount;
      if (startValue > treeSize)
        return false;
    }
    
    int index = 0;
    for (int i = 1; i <= _TABLE_BITS; i++) {
      int limit = ((maxValueWithLength[i] + 1) >> (_maxLength - _TABLE_BITS));
      for (; index < limit; index++)
        lengths[index] = i;
    }
    
    List<int> nextPosWithLength = new List<int>.from(minPosWithLength);
    for (int symbol = 0; symbol < _symbolCount; symbol++) {
      int length = codeLengths[symbol];
      if (length != 0) {
        symbols[nextPosWithLength[length]++] = symbol;
      }
    }
    
    return true;
  }
  
  int decodeSymbol(BitBuffer buffer) {
    int length;
    int value = buffer.peekBits(_maxLength);
    if (value < (maxValueWithLength[_TABLE_BITS] + 1))
      length = lengths[value >> (_maxLength - _TABLE_BITS)];
    else
      for (length = _TABLE_BITS + 1; value > maxValueWithLength[length]; length++);
    buffer.move(length);
    int index = minPosWithLength[length] +
      ((value - (maxValueWithLength[length - 1] + 1)) >> (_maxLength - length));
    if (index >= _symbolCount)
      return 0xFFFFFFFF;
    return symbols[index];
  }
}


