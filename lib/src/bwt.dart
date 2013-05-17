part of bzip2;

class _BWTResult {
  List<int> lastColumn;
  int originPointer;
  
  _BWTResult([List<int> this.lastColumn, int this.originPointer]);
}

class _BWTDecoder {
  List<int> decode(_BWTResult encodedData) {
    List<int> lastColumn = encodedData.lastColumn;
    
    List<int> charCounters = new List<int>.filled(256, 0);
    for (int symbol in lastColumn) {
      charCounters[symbol]++;
    }
    
    List<int> nextIndex = new List<int>(256);
    nextIndex[0] = 0;
    for (int i = 1; i < 256; i++) {
      nextIndex[i] = nextIndex[i - 1] + charCounters[i - 1];
    }
    
    List<int> firstColumn = new List<int>(lastColumn.length);
    for (int i = 0; i < lastColumn.length; i++) {
      int symbol = lastColumn[i];
      firstColumn[nextIndex[symbol]++] = i;
    }
    
    List<int> result = new List<int>(lastColumn.length);
    int currentIndex = firstColumn[encodedData.originPointer];
    for (int i = 0; i < lastColumn.length; i++) {
      result[i] = lastColumn[currentIndex];
      currentIndex = firstColumn[currentIndex];
    }
    
    return result;
  }
}

class _BWTEncoder {
  
  /* Calculate the burrows-wheeler transformation */ 
  _BWTResult encode(List<int> data) {
    _BWTResult result = new _BWTResult();
    _BlockOrdering blockOrdering = _blockSort(data);
     
    /* calculate last column */
    result.lastColumn = new List<int>(data.length);
    for (int i = 0; i < data.length; i++) {
      int block = blockOrdering.index2block[i];
      int symbolIndex = (block == 0 ? data.length - 1 : block - 1);
      result.lastColumn[i] = data[symbolIndex];
    }
    
    /* calculate origin pointer */
    result.originPointer = blockOrdering.index2block.indexOf(0);
    
    return result;
  }
  
  /* _sortByBlockSize block sorts this._data by the specified block size */
  _BlockOrdering _blockSort(List<int> data) {
    _BlockOrdering blockOrdering = _sortByFirstSymbol(data);
    
    while (blockOrdering.bucketCount != data.length) {
      blockOrdering = _merge(blockOrdering, blockOrdering);
    }
    
    return blockOrdering;
  }
  
  /* 
   * Merge two block orderings and return a new block ordering which has 
   * blockSize equal to a.blockSize + b.blockSize.
   */
  _BlockOrdering _merge(_BlockOrdering a, _BlockOrdering b) {
    _BlockOrdering result = new _BlockOrdering(a.dataSize, a.blockSize + b.blockSize);
    
    List<int> nextIndex = new List<int>(result.dataSize);
    for (int i = result.dataSize - 1; i >= 0; i--) {
      nextIndex[a.index2bucket[i]] = i;
    }
    
    /* sort */
    List<int> secondHalfBucket = new List<int>(result.dataSize);
    for (int i = 0; i < result.dataSize; i++) {
      int block = b.index2block[i] - a.blockSize;
      if (block < 0) {
        block += result.dataSize;
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
    for (int i = 1; i < result.dataSize; i++) {
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
    return result;
  }
  
  /*
   * Calculate the block ordering of all rotations of data when they are sorted
   * by the first symbol.
   */
  _BlockOrdering _sortByFirstSymbol(List<int> data) {
    _BlockOrdering result = new _BlockOrdering(data.length, 1);
    
    List<int> symbolFreq = new List<int>.filled(256, 0);
    for (int symbol in data) {
      symbolFreq[symbol]++;
    }
    
    List<int> nextIndex = new List<int>(256);
    int sum = 0;
    for (int symbol = 0; symbol < 256; symbol++) {
      nextIndex[symbol] = sum;
      sum += symbolFreq[symbol];
    }
    
    /* sort */
    for (int block = 0; block < data.length; block++) {
      int index = nextIndex[data[block]]++;
      result.index2block[index] = block;
    }
    
    /* update buckets */
    int currentBucket = 0;
    int preSymbol;
    for (int index = 0; index < data.length; index++) {
      int block = result.index2block[index];
      int curSymbol = data[block];
      if (index != 0 && curSymbol != preSymbol) {
        currentBucket++;
      }
      
      result.block2bucket[block] = currentBucket;
      result.index2bucket[index] = currentBucket;
      
      preSymbol = curSymbol;
    }
    
    result.bucketCount = currentBucket + 1;
    return result;
  }
}

class _BlockOrdering {
  List<int> index2block;
  List<int> block2bucket;
  List<int> index2bucket;
  int blockSize;
  int dataSize;
  int bucketCount;
  
  _BlockOrdering(int this.dataSize, int this.blockSize) {
    index2block = new List<int>(dataSize);
    block2bucket = new List<int>(dataSize);
    index2bucket = new List<int>(dataSize);
  }
}
