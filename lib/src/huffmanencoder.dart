part of bzip2;

const int kMaxLen = 16;
const int NUM_BITS = 10;
const int MASK = ((1 << NUM_BITS) - 1);

const int NUM_COUNTERS = 64;


class _HuffmanEncoder {
  int numSymbols;
  int maxLen;
  
  _HuffmanEncoder(this.numSymbols, this.maxLen);
  
  void generate(List<int> freqs, List<int> p, List<int> lens) {
    int num = 0;
    {
      for (int i = 0; i < numSymbols; i++)
      {
        int freq = freqs[i];
        if (freq == 0)
          lens[i] = 0;
        else
          p[num++] = i | (freq << NUM_BITS);
      }
      List<int> sublist = p.sublist(0, num);
      sublist.sort();
      p.setRange(0, num, sublist);
    }
    if (num < 2)
    {
      int minCode = 0;
      int maxCode = 1;
      if (num == 1)
      {
        maxCode = p[0] & MASK;
        if (maxCode == 0)
          maxCode++;
      }
      p[minCode] = 0;
      p[maxCode] = 1;
      lens[minCode] = lens[maxCode] = 1;
      return;
    }
    
    int b, e, i;
    
    i = b = e = 0;
    do
    {
      int n, m, freq;
      n = (i != num && (b == e || (p[i] >> NUM_BITS) <= (p[b] >> NUM_BITS))) ? i++ : b++;
      freq = (p[n] & ~MASK);
      p[n] = (p[n] & MASK) | (e << NUM_BITS);
      m = (i != num && (b == e || (p[i] >> NUM_BITS) <= (p[b] >> NUM_BITS))) ? i++ : b++;
      freq += (p[m] & ~MASK);
      p[m] = (p[m] & MASK) | (e << NUM_BITS);
      p[e] = (p[e] & MASK) | freq;
      e++;
    }
    while (num - e > 1);
    
    List<int> lenCounters = new List<int>.filled(kMaxLen + 1, 0);
    p[--e] &= MASK;
    lenCounters[1] = 2;
    while (e > 0)
    {
      int len = (p[p[--e] >> NUM_BITS] >> NUM_BITS) + 1;
      p[e] = (p[e] & MASK) | (len << NUM_BITS);
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
          lens[p[i++] & MASK] = len;
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
      /* if (code + lenCounters[kMaxLen] - 1 != (1 << kMaxLen) - 1) throw 1; */

      {
        int i;
        for (i = 0; i < numSymbols; i++)
          p[i] = nextCodes[lens[i]]++;
      }
    }
  }
}