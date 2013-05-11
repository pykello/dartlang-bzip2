part of bzip2;

class _HuffmanDecoder {
  int _maxLength;
  int _symbolCount;
  List<int> _maxValueWithLength;
  List<int> _minPosWithLength;
  List<int> _symbols;
  
  _HuffmanDecoder(this._maxLength, this._symbolCount) {
    _maxValueWithLength = new List<int>(_maxLength + 1);
    _minPosWithLength = new List<int>(_maxLength + 1);
    _symbols = new List<int>(_symbolCount);
  }
  
  bool setCodeLengths(List<int> codeLengths) {
    List<int> symbolCountWithLength = new List<int>.filled(_maxLength + 1, 0);
    for (int symbol = 0; symbol < _symbolCount; symbol++) {
      symbolCountWithLength[codeLengths[symbol]]++;    
    }
    
    _minPosWithLength[0] = 0;
    _maxValueWithLength[0] = -1;
    int startValue = 0;
    int treeSize = (1 << _maxLength);
    
    for (int length = 1; length <= _maxLength; length++) {
      int subtreeSize = 1 << (_maxLength - length);
      int valueCount = symbolCountWithLength[length] * subtreeSize;
      _maxValueWithLength[length] = startValue + valueCount - 1;
      
      _minPosWithLength[length] = _minPosWithLength[length - 1] + 
                                 symbolCountWithLength[length - 1];
      
      startValue += valueCount;
      if (startValue > treeSize) {
        throw new StateError("invalid length array");
      }
    }
    
    List<int> nextPosWithLength = new List<int>.from(_minPosWithLength);
    for (int symbol = 0; symbol < _symbolCount; symbol++) {
      int length = codeLengths[symbol];
      if (length != 0) {
        _symbols[nextPosWithLength[length]++] = symbol;
      }
    }
    
    return true;
  }
  
  int decodeSymbol(BitBuffer buffer) {
    int value = buffer.peekBits(_maxLength);

    int length = 1;
    while (value > _maxValueWithLength[length]) {
      length++;
    }
    buffer.move(length);
    
    int valueOffset = (value - (_maxValueWithLength[length - 1] + 1));
    int symbolOffset = valueOffset >> (_maxLength - length);  
    int symbolPos = _minPosWithLength[length] + symbolOffset;
    
    if (symbolPos >= _symbolCount) {
      throw new StateError("invalid symbol");
    }
    
    return _symbols[symbolPos];
  }
}
