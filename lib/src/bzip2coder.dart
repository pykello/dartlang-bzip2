part of bzip2;

abstract class _Bzip2Coder {
  void writeByte(int byte);
  void setEndOfData();
  bool canProcess();
  void process();
  List<int> readOutput();
}

