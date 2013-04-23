library bzip2;

import 'dart:io';
import 'dart:async';
import 'dart:typeddata';

part 'src/bitbuffer.dart';
part 'src/crc.dart';
part 'src/decompressor.dart';
part 'src/huffmandecoder.dart';
part 'src/mtf8decoder.dart';

class Bzip2Decompressor extends StreamEventTransformer<List<int>, List<int>> {
  _Bzip2Decompressor _decompressor;
  
  Bzip2Decompressor({checkCrc: false}) {
    _decompressor = new _Bzip2Decompressor(checkCrc);
  }
  
  void handleData(List<int> data, EventSink<List<int>> sink) {
    for (int byte in data) {
      _decompressor.writeByte(byte);
      while (_decompressor.canProcess()) {
        _decompressor.process();
        sink.add(_decompressor.readOutput());
      }
    }
  }
  
  void handleDone(EventSink<List<int>> sink) {
    _decompressor.setEndOfData();
    while (_decompressor.canProcess()) {
      _decompressor.process();
      sink.add(_decompressor.readOutput());
    }
    sink.close();
  }
}
