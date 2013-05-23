part of bzip2;

/*
 * This file implements the decoder and encoder for the burrows-wheeler
 * transformation. For more information on the theory behind the transformation
 * refer to "M. Burrows and D.J. Wheeler. A Block Sorting Lossless Data 
 * Compression Algorithm. SRC Research Report, 1994".
 */

/* output type of encoder and input type of decoder */
class _BWTResult {
  List<int> lastColumn;   /* last column in the matrix of sorted rotations */
  int originPointer;      /* index of original string in matrix of sorted rotations */
  
  _BWTResult([List<int> this.lastColumn, int this.originPointer]);
}

class _BWTDecoder {
  
  /* Calculate the inverse burrows-wheeler transformation. */
  List<int> decode(_BWTResult encodedData) {
    List<int> lastColumn = encodedData.lastColumn;
    
    /* calculate the first to last column mapping */
    List<int> symbolCount = new List<int>.filled(256, 0);
    for (int symbol in lastColumn) {
      symbolCount[symbol]++;
    }
    
    List<int> nextIndex = new List<int>(256);
    nextIndex[0] = 0;
    for (int i = 1; i < 256; i++) {
      nextIndex[i] = nextIndex[i - 1] + symbolCount[i - 1];
    }
    
    List<int> first2last = new List<int>(lastColumn.length);
    for (int i = 0; i < lastColumn.length; i++) {
      int symbol = lastColumn[i];
      first2last[nextIndex[symbol]++] = i;
    }
    
    /* decode the sequence */
    List<int> result = new List<int>(lastColumn.length);
    int currentIndex = first2last[encodedData.originPointer];
    for (int i = 0; i < lastColumn.length; i++) {
      result[i] = lastColumn[currentIndex];
      currentIndex = first2last[currentIndex];
    }
    
    return result;
  }
}

class _BWTEncoder {
  
  /* Calculate the burrows-wheeler transformation. */ 
  _BWTResult encode(List<int> data) {
    _BWTResult result = new _BWTResult();
    List<int> sortedRotations = _sortAllRotations(data);
     
    /* calculate last column */
    result.lastColumn = new List<int>(data.length);
    for (int i = 0; i < data.length; i++) {
      int rotationStart = sortedRotations[i];
      int rotationEnd = (rotationStart == 0 ? data.length - 1 : rotationStart - 1);
      result.lastColumn[i] = data[rotationEnd];
    }
    
    /* calculate origin pointer */
    result.originPointer = sortedRotations.indexOf(0);
    
    return result;
  }

  /* 
   * Sort all rotations of data and return the sorted rotations. Each rotation
   * is identified by its starting index.
   */
  List<int> _sortAllRotations(List<int> data) {
    _BlockOrdering blockOrdering = _sortByFirstSymbol(data);
    
    while (blockOrdering.bucketCount != data.length) {
      blockOrdering.doubleBlockSize();
    }
    
    return blockOrdering.index2block;
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
  
  void doubleBlockSize() {
    _sortBy2xBlockSize();
    _updateBucketsFor2xBlockSize();
    blockSize *= 2;
  }
  
  void _sortBy2xBlockSize() {
    List<int> nextIndex = new List<int>(dataSize);
    for (int i = dataSize - 1; i >= 0; i--) {
      nextIndex[index2bucket[i]] = i;
    }
  
    List<int> updatedIndex2Block = new List<int>(dataSize);
    for (int i = 0; i < dataSize; i++) {
      int block = index2block[i] - blockSize;
      if (block < 0) {
        block += dataSize;
      }
      
      int bucket = block2bucket[block];
      int resultIndex = nextIndex[bucket]++;
      updatedIndex2Block[resultIndex] = block;
    }
    index2block = updatedIndex2Block;
  }
  
  void _updateBucketsFor2xBlockSize() {
    List<int> secondHalfBucket = new List<int>.generate(dataSize, 
        (int i) => block2bucket[(index2block[i] + blockSize) % dataSize]);
    
    int currentBucket = 0;
    int pre1stHalfBucket;
    int pre2ndHalfBucket;
    for (int i = 0; i < dataSize; i++) {
      int cur1stHalfBucket = index2bucket[i];
      int cur2ndHalfBucket = secondHalfBucket[i];
      
      if (i != 0 && (cur1stHalfBucket != pre1stHalfBucket || 
                     pre2ndHalfBucket != cur2ndHalfBucket)) {
        currentBucket++;
      }
      index2bucket[i] = currentBucket;
      block2bucket[index2block[i]] = currentBucket;
      
      pre1stHalfBucket = cur1stHalfBucket;
      pre2ndHalfBucket = cur2ndHalfBucket;
    }
    
    bucketCount = currentBucket + 1;
  }
}
