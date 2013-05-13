part of bzip2;


class _BWTEncoder {
  List<int> _data;
  int _dataSize;
  List<int> _nextIndex;
  _BlockOrdering _firstSymbolOrdering;
  
  int originPointer;
  List<int> blockSorted;
  
  _BWTEncoder(List<int> this._data) {
    _dataSize = _data.length;
    _nextIndex = new List<int>(max(_dataSize, 256).toInt());
    _transform();
  }
  
  void _transform() {
     _firstSymbolOrdering = _sortByFirstSymbol();
     _BlockOrdering blockOrdering = _sortByBlockSize(_dataSize);
     
     blockSorted = new List<int>(_dataSize);
     for (int i = 0; i < _dataSize; i++) {
       int block = blockOrdering.index2block[i];
       int symbolIndex = (block == 0 ? _dataSize - 1 : block - 1);
       blockSorted[i] = _data[symbolIndex];
       
       if (block == 0) {
         originPointer = i;
       }
     }
  }
  
  /* _sortByBlockSize block sorts this._data by the specified block size */
  _BlockOrdering _sortByBlockSize(int blockSize) {
    if (blockSize == 1) {
      return _firstSymbolOrdering;
    }
    
    _BlockOrdering halfSizeOrdering = _sortByBlockSize(blockSize ~/ 2);
    
    _BlockOrdering blockOrdering = _merge(halfSizeOrdering, halfSizeOrdering);
    if (blockSize % 2 == 1) {
      blockOrdering = _merge(blockOrdering, _firstSymbolOrdering);
    }
    
    return blockOrdering;
  }
  
  /* 
   * Merge two block orderings and return a new block ordering which has 
   * blockSize == a.blockSize + b.blockSize.
   */
  _BlockOrdering _merge(_BlockOrdering a, _BlockOrdering b) {
    if (a.bucketCount == _dataSize) {
      a.blockSize += b.blockSize;
      return a;
    }
    
    _BlockOrdering result = new _BlockOrdering.from(a);
    result.blockSize = a.blockSize + b.blockSize;
    
    for (int i = 0; i < _dataSize; i++) {
      if (i == 0 || result.index2bucket[i] != result.index2bucket[i - 1]) {
        _nextIndex[result.index2bucket[i]] = i;
      }
    }
    
    /* sort */
    for (int i = 0; i < _dataSize; i++) {
      int block = b.index2block[i] - a.blockSize;
      if (block < 0) {
        block += _dataSize;
      }
      
      int index = result.block2index[block];
      int bucket = result.index2bucket[index];
      result.swap(_nextIndex[bucket]++, index);
    }
    
    /* update buckets */
    int currentBucket = 0;
    result.index2bucket[0] = 0;
    for (int i = 1; i < _dataSize; i++) {
      bool isNewBlock;
      
      int curBlock = result.index2block[i];
      int preBlock = result.index2block[i - 1];
      
      if (a.getBlockBucket(curBlock) == a.getBlockBucket(preBlock)) {
        int curBlock2H = (curBlock + a.blockSize) % _dataSize;
        int preBlock2H = (preBlock + a.blockSize) % _dataSize;
        isNewBlock = b.getBlockBucket(curBlock2H) != b.getBlockBucket(preBlock2H); 
      }
      else {
        isNewBlock = true;
      }

      if (isNewBlock) {
        currentBucket++;
      }
      
      result.index2bucket[i] = currentBucket;
    }
    
    result.bucketCount = currentBucket + 1;
    
    return result;
  }
  
  _BlockOrdering _sortByFirstSymbol() {
    _BlockOrdering blockOrdering = new _BlockOrdering(_dataSize, 1);
    
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
      blockOrdering.index2block[index] = block;
      blockOrdering.block2index[block] = index;
      blockOrdering.index2bucket[index] = symbol;
    }
    
    blockOrdering.bucketCount = symbolFreq.where((v) => v > 0).length;
    
    return blockOrdering;
  }
}

class _BlockOrdering {
  List<int> index2block;
  List<int> block2index;
  List<int> index2bucket;
  int blockSize;
  int bucketCount;
  
  _BlockOrdering(int size, int this.blockSize) {
    index2block = new List<int>(size);
    block2index = new List<int>(size);
    index2bucket = new List<int>(size);
  }
  
  _BlockOrdering.from(_BlockOrdering a) {
    index2block = new List<int>.from(a.index2block);
    block2index = new List<int>.from(a.block2index);
    index2bucket = new List<int>.from(a.index2bucket);
    blockSize = a.blockSize;
    bucketCount = a.bucketCount;
  }
  
  int getBlockBucket(int block) {
    return index2bucket[block2index[block]];
  }
  
  void swap(int index1, int index2) {
    if (index2bucket[index1] != index2bucket[index2] || index1 > index2) {
      throw new StateError("invalid swap 1");
    }
    int tmp = index2block[index1];
    index2block[index1] = index2block[index2];
    index2block[index2] = tmp;
    
    block2index[index2block[index1]] = index1;
    block2index[index2block[index2]] = index2;
  }
}
