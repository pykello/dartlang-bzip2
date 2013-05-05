part of bzip2;

const int kMaxLen = 16;
const int NUM_BITS = 10;
const int MASK = ((1 << NUM_BITS) - 1);

const int NUM_COUNTERS = 64;


class _HuffmanCode {
  int code, len;
  _HuffmanCode(this.code, this.len);
}

class _HuffmanEncoder {
  int _symbolCount;
  int maxLen;
  
  _HuffmanEncoder(this._symbolCount, this.maxLen);
  
  List<_HuffmanCode> generate(List<int> freqs) {
    List<int> codes = new List<int>(_symbolCount);
    List<int> lens = new List<int>(_symbolCount);
    
    for (int i = 0; i < _symbolCount; i++) {
      codes[i] = i | (max(freqs[i], 1) << NUM_BITS);
    }
    codes.sort();
          
    int b, e, i;
    
    i = b = e = 0;
    do
    {
      int n, m, freq;
      n = (i != _symbolCount && (b == e || (codes[i] >> NUM_BITS) <= (codes[b] >> NUM_BITS))) ? i++ : b++;
      freq = (codes[n] & ~MASK);
      codes[n] = (codes[n] & MASK) | (e << NUM_BITS);
      m = (i != _symbolCount && (b == e || (codes[i] >> NUM_BITS) <= (codes[b] >> NUM_BITS))) ? i++ : b++;
      freq += (codes[m] & ~MASK);
      codes[m] = (codes[m] & MASK) | (e << NUM_BITS);
      codes[e] = (codes[e] & MASK) | freq;
      e++;
    }
    while (_symbolCount - e > 1);
    
    List<int> lenCounters = new List<int>.filled(kMaxLen + 1, 0);
    codes[--e] &= MASK;
    lenCounters[1] = 2;
    while (e > 0)
    {
      int len = (codes[codes[--e] >> NUM_BITS] >> NUM_BITS) + 1;
      codes[e] = (codes[e] & MASK) | (len << NUM_BITS);
      if (len >= maxLen)
        for (len = maxLen - 1; lenCounters[len] == 0; len--);
      lenCounters[len]--;
      lenCounters[len + 1] += 2;
    }
    
    {
      int len;
      i = 0;
      for (len = maxLen; len != 0; len--)
      {
        int num;
        for (num = lenCounters[len]; num != 0; num--)
          lens[codes[i++] & MASK] = len;
      }
    }
    
    {
      List<int> nextCodes = new List<int>.filled(kMaxLen + 1, 0);
      {
        int code = 0;
        int len;
        for (len = 1; len <= kMaxLen; len++)
          nextCodes[len] = code = (code + lenCounters[len - 1]) << 1;
      }

      for (int i = 0; i < _symbolCount; i++)
        codes[i] = nextCodes[lens[i]]++;
    }
    
    List<_HuffmanCode> result = new List<_HuffmanCode>.generate(_symbolCount, 
                                            (i) => new _HuffmanCode(codes[i], lens[i]));
    return result;
  }
}
