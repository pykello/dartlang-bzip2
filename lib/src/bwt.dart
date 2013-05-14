part of bzip2;

class _BWTEncoder {
  int originPointer;
  List<int> lastColumn;
  
  List<int> _data;
  int _dataSize;
  List<int> _nextIndex;
  List<int> _secondHalfBucket;
  
  _BWTEncoder(List<int> this._data) {
    _dataSize = _data.length;
    _nextIndex = new List<int>(max(_dataSize, 256 * 256).toInt());
    _secondHalfBucket = new List<int>(max(_dataSize, 256 * 256).toInt());
    _transform();
  }
  
  void _transform() {
     _BlockOrdering blockOrdering = _blockSort();
     
     lastColumn = new List<int>(_dataSize);
     for (int i = 0; i < _dataSize; i++) {
       int block = blockOrdering.index2block[i];
       int symbolIndex = (block == 0 ? _dataSize - 1 : block - 1);
       lastColumn[i] = _data[symbolIndex];
       
       if (block == 0) {
         originPointer = i;
       }
     }
  }
  
  /* _sortByBlockSize block sorts this._data by the specified block size */
  _BlockOrdering _blockSort() {
    _BlockOrdering currResult = new _BlockOrdering(_dataSize);
    _BlockOrdering prevResult = new _BlockOrdering(_dataSize);
    
    _sortByFirstSymbol(currResult);
    
    while (currResult.bucketCount != _data.length) {
      //print (_data.length - currResult.bucketCount);
      _BlockOrdering temp = prevResult;
      prevResult = currResult;
      currResult = temp;
      
      _merge(prevResult, prevResult, currResult);
    }
    
    return currResult;
  }
  
  /* 
   * Merge two block orderings and return a new block ordering which has 
   * blockSize == a.blockSize + b.blockSize.
   */
  void _merge(_BlockOrdering a, _BlockOrdering b, _BlockOrdering result) {
    result.blockSize = a.blockSize + b.blockSize;
    
    for (int i = _dataSize - 1; i >= 0; i--) {
      _nextIndex[a.index2bucket[i]] = i;
    }
    
    /* sort */
    for (int i = 0; i < _dataSize; i++) {
      int block = b.index2block[i] - a.blockSize;
      if (block < 0) {
        block += _dataSize;
      }
      
      int bucket = a.block2bucket[block];
      int resultIndex = _nextIndex[bucket]++;
      result.index2block[resultIndex] = block;
      _secondHalfBucket[resultIndex] = b.index2bucket[i];
    }
    
    /* update buckets */
    int currentBucket = 0;
    result.index2bucket[0] = 0;
    result.block2bucket[result.index2block[0]] = 0;
    int pre1stHalfBucket = a.index2bucket[0];
    int pre2ndHalfBucket2 = _secondHalfBucket[0];
    for (int i = 1; i < _dataSize; i++) {
      if (a.index2bucket[i] != pre1stHalfBucket || _secondHalfBucket[i] != pre2ndHalfBucket2) {
        currentBucket++;
      }
      result.index2bucket[i] = currentBucket;
      result.block2bucket[result.index2block[i]] = currentBucket;
      
      pre1stHalfBucket = a.index2bucket[i];
      pre2ndHalfBucket2 = _secondHalfBucket[i];
    }
    
    result.bucketCount = currentBucket + 1;
  }
  
  void _sortByFirstSymbol(_BlockOrdering result) {
    result.blockSize = 1;
    
    List<int> symbolFreq = new List<int>.filled(256, 0);
    for (int symbol in _data) {
      symbolFreq[symbol]++;
    }
    
    List<int> nextIndex = new List<int>(256);
    int sum = 0;
    for (int symbol = 0; symbol < 256; symbol++) {
      nextIndex[symbol] = sum;
      sum += symbolFreq[symbol];
    }
    
    for (int block = 0; block < _dataSize; block++) {
      int symbol = _data[block];
      int index = nextIndex[symbol]++;
      result.index2block[index] = block;
      result.block2bucket[block] = symbol;
      result.index2bucket[index] = symbol;
    }
    
    result.bucketCount = symbolFreq.where((v) => v > 0).length;
  }
}

class _BlockOrdering {
  List<int> index2block;
  List<int> block2bucket;
  List<int> index2bucket;
  int blockSize;
  int bucketCount;
  
  _BlockOrdering(int size) {
    index2block = new List<int>(size);
    block2bucket = new List<int>(size);
    index2bucket = new List<int>(size);
  }
}
