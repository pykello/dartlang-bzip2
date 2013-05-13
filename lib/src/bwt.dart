part of bzip2;


class _BWTEncoder {
  List<int> _data;
  int _dataSize;
  List<int> _nextIndex;
  _BlockOrdering _firstSymbolOrdering;
  
  ListQueue<_BlockOrdering> _blockOrderingPool = new ListQueue<_BlockOrdering>();
  
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
    if (halfSizeOrdering.bucketCount == _dataSize) {
      return halfSizeOrdering;
    }
    
    _BlockOrdering blockOrdering = _merge(halfSizeOrdering, halfSizeOrdering);

    if (halfSizeOrdering != _firstSymbolOrdering) {
      _blockOrderingPool.addFirst(halfSizeOrdering);
    }
    
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
    _BlockOrdering result = _newBlockOrdering(a.blockSize + b.blockSize);
    
    for (int i = 0; i < _dataSize; i++) {
      if (i == 0 || a.index2bucket[i] != a.index2bucket[i - 1]) {
        _nextIndex[a.index2bucket[i]] = i;
      }
    }
    
    /* sort */
    for (int i = 0; i < _dataSize; i++) {
      int block = b.index2block[i] - a.blockSize;
      if (block < 0) {
        block += _dataSize;
      }
      
      int index = a.block2index[block];
      int bucket = a.index2bucket[index];
      
      int resultIndex = _nextIndex[bucket]++;
      result.index2block[resultIndex] = block;
      result.block2index[block] = resultIndex;
    }
    
    /* update buckets */
    int currentBucket = 0;
    result.index2bucket[0] = 0;
    int preBlock = result.index2block[0];
    for (int i = 1; i < _dataSize; i++) {
      bool isNewBlock;
      
      int curBlock = result.index2block[i];
      
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
      
      preBlock = curBlock;
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
  
  _BlockOrdering _newBlockOrdering(int blockSize) {
    _BlockOrdering result;
    
    if (_blockOrderingPool.isEmpty) {
      result = new _BlockOrdering(_dataSize, blockSize);
    }
    else {
      result = _blockOrderingPool.removeFirst();
      result.blockSize = blockSize;
    }
    
    return result;
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
  
  int getBlockBucket(int block) {
    return index2bucket[block2index[block]];
  }
}
