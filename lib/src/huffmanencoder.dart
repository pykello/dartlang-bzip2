part of bzip2;

class _HuffmanEncoder {
  int maxLen;
  
  _HuffmanEncoder(int this.maxLen);
  
  /*
   * generate returns the huffman prefix-free code/length pairs for symbols 
   * with the given frequencies such that no symbol has a length greater than
   * maxLen.
   */
  List<_HuffmanCode> generate(List<int> freqs) {
    List<int> symbolLength = _getLengths(freqs);
    List<int> symbolCode = _getCodes(symbolLength);
    
    List<_HuffmanCode> huffmanCodes = new List<_HuffmanCode>(freqs.length);
    for (int symbol = 0; symbol < freqs.length; symbol++) {
      huffmanCodes[symbol] = new _HuffmanCode(symbolCode[symbol], symbolLength[symbol]);
    }

    return huffmanCodes;
  }
  
  /*
   * _getLengths returns the list of optimal lengths for each symbol with the 
   * given symbol frequencies in the height limited huffman tree. The returned
   * lengths are guaranteed to be less than maxLen. 
   * 
   * This function refines the frequency list until the standard huffman 
   * coding algorithm can generate a tree with height at most maxLen. 
   */
  List<int> _getLengths(List<int> symbolFreq) {
    List<int> symbolFreqCopy = new List<int>.from(symbolFreq);
    int symbolCount = symbolFreq.length;
    List<int> symbolLength;
    bool tooLong = true; 
    
    while (tooLong) {
      symbolLength = new List<int>.filled(symbolFreq.length, 0);
      
      /* initialize huffman subtrees */
      SplayTreeMap<_HuffmanSubtree, int> subtrees;
      subtrees = new SplayTreeMap<_HuffmanSubtree, int>();
      for (int symbol = 0; symbol < symbolCount; symbol++) {
        int weight = max(symbolFreqCopy[symbol], 1).toInt();
        subtrees[new _HuffmanSubtree([symbol], weight)] = 1;
        symbolLength[symbol] = 0;
      }
      
      /* construct the huffman tree */
      while (subtrees.length > 1) {
        _HuffmanSubtree first = subtrees.firstKey();
        _HuffmanSubtree second = subtrees.firstKeyAfter(first);
        _HuffmanSubtree merged = first.merge(second);
        
        for (int symbol in merged.symbols) {
          symbolLength[symbol]++;
        }
        
        subtrees.remove(first);
        subtrees.remove(second);
        subtrees[merged] = 1;
      }
      
      /* are all lengths <= maxLen? */
      if (symbolLength.where((int length) => length > maxLen).isEmpty) {
        tooLong = false;
      }
      
      /* refine the frequency list */
      if (tooLong) {
        for (int symbol = 0; symbol < symbolCount; symbol++) {
          symbolFreqCopy[symbol] = 1 + (symbolFreqCopy[symbol] ~/ 2); 
        }
      }
    }
    
    return symbolLength;
  }
  
  /* _getCodes returns the prefix-free codes for symbols with given lengths */ 
  List<int> _getCodes(List<int> symbolLength) {
    List<int> lengthCount = new List<int>.filled(maxLen + 1, 0);
    for (int length in symbolLength) {
      lengthCount[length]++;
    }
        
    List<int> nextCodeWithLength = new List<int>.filled(maxLen + 1, 0);
    for (int len = 1; len <= maxLen; len++) {
      nextCodeWithLength[len] = (nextCodeWithLength[len - 1] + lengthCount[len - 1]) * 2;
    }

    List<int> symbolCode = new List<int>(symbolLength.length);
    for (int symbol = 0; symbol < symbolLength.length; symbol++) {
      symbolCode[symbol] = nextCodeWithLength[symbolLength[symbol]]++;
    }
    
    return symbolCode;
  }
}

class _HuffmanCode {
  int code, len;
  _HuffmanCode(int this.code, int this.len);
}

class _HuffmanSubtree implements Comparable<_HuffmanSubtree> {
  List<int> symbols;
  int weight;
  _HuffmanSubtree(List<int> this.symbols, int this.weight);
  
  int compareTo(_HuffmanSubtree other) {
    int result = weight.compareTo(other.weight);
    if (result == 0) {
      result = symbols[0].compareTo(other.symbols[0]);
    }
    return result;
  }
  
  _HuffmanSubtree merge(_HuffmanSubtree other) {
    int mergedWeight = weight + other.weight;
    List<int> mergedSymbols = new List<int>.from(symbols)
                                  ..addAll(other.symbols)
                                  ..sort();
    
    return new _HuffmanSubtree(mergedSymbols, mergedWeight);
  }
}
