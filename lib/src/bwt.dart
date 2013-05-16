part of bzip2;

/*
 * _BWTEncoder sorts all rotations of a given sequence, and puts the last column
 * in lastColumn, and it puts the index of unrotated sequence in the sorted sequences
 * in originPointer.
 */
class _BWTEncoder {
  int originPointer;
  List<int> lastColumn;
  
  List<int> _data;
  int _dataSize;
  
  _BWTEncoder(List<int> this._data) {
    _dataSize = _data.length;
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
    _BlockOrdering curResult = new _BlockOrdering(_dataSize);
    _BlockOrdering preResult = new _BlockOrdering(_dataSize);
    
    _sortByFirstSymbol(curResult);
    
    while (curResult.bucketCount != _data.length) {
      _BlockOrdering temp = preResult;
      preResult = curResult;
      curResult = temp;
      
      _merge(preResult, preResult, curResult);
    }
    
    return curResult;
  }
  
  /* 
   * Merge two block orderings and return a new block ordering which has 
   * blockSize == a.blockSize + b.blockSize.
   */
  void _merge(_BlockOrdering a, _BlockOrdering b, _BlockOrdering result) {
    result.blockSize = a.blockSize + b.blockSize;
    
    List<int> nextIndex = new List<int>(_dataSize);
    for (int i = _dataSize - 1; i >= 0; i--) {
      nextIndex[a.index2bucket[i]] = i;
    }
    
    /* sort */
    List<int> secondHalfBucket = new List<int>(_dataSize);
    for (int i = 0; i < _dataSize; i++) {
      int block = b.index2block[i] - a.blockSize;
      if (block < 0) {
        block += _dataSize;
      }
      
      int bucket = a.block2bucket[block];
      int resultIndex = nextIndex[bucket]++;
      result.index2block[resultIndex] = block;
      secondHalfBucket[resultIndex] = b.index2bucket[i];
    }
    
    /* update buckets */
    int currentBucket = 0;
    result.index2bucket[0] = 0;
    result.block2bucket[result.index2block[0]] = 0;
    int pre1stHalfBucket = a.index2bucket[0];
    int pre2ndHalfBucket = secondHalfBucket[0];
    for (int i = 1; i < _dataSize; i++) {
      int cur1stHalfBucket = a.index2bucket[i];
      int cur2ndHalfBucket = secondHalfBucket[i];
      
      if (cur1stHalfBucket != pre1stHalfBucket || pre2ndHalfBucket != cur2ndHalfBucket) {
        currentBucket++;
      }
      result.index2bucket[i] = currentBucket;
      result.block2bucket[result.index2block[i]] = currentBucket;
      
      pre1stHalfBucket = cur1stHalfBucket;
      pre2ndHalfBucket = cur2ndHalfBucket;
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
    
    /* sort */
    for (int block = 0; block < _dataSize; block++) {
      int index = nextIndex[_data[block]]++;
      result.index2block[index] = block;
    }
    
    /* update buckets */
    int currentBucket = 0;
    int preSymbol;
    for (int index = 0; index < _dataSize; index++) {
      int block = result.index2block[index];
      int curSymbol = _data[block];
      if (index != 0 && curSymbol != preSymbol) {
        currentBucket++;
      }
      
      result.block2bucket[block] = currentBucket;
      result.index2bucket[index] = currentBucket;
      
      preSymbol = curSymbol;
    }
    
    result.bucketCount = currentBucket + 1;
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
