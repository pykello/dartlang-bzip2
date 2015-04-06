library bzip2;

import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

part 'src/bitbuffer.dart';
part 'src/compressor.dart';
part 'src/constants.dart';
part 'src/bzip2coder.dart';
part 'src/bwt.dart';
part 'src/crc.dart';
part 'src/decompressor.dart';
part 'src/huffmandecoder.dart';
part 'src/huffmanencoder.dart';

abstract class _Bzip2Transformer implements 
    StreamTransformer<List<int>, List<int>> {
      
  _Bzip2Coder _coder;
  _Bzip2Transformer(_Bzip2Coder this._coder);
  
  Stream bind(Stream stream) {
    return stream.transform(new StreamTransformer.fromHandlers(
      handleData: this.handleData,
      handleDone: this.handleDone
    ));
  }
  
  void handleData(List<int> data, EventSink<List<int>> sink) {
    for (int byte in data) {
      _coder.writeByte(byte);
      while (_coder.canProcess()) {
        _coder.process();
        sink.add(_coder.readOutput());
      }
    }
  }
  
  void handleDone(EventSink<List<int>> sink) {
    _coder.setEndOfData();
    while (_coder.canProcess()) {
      _coder.process();
      sink.add(_coder.readOutput());
    }
    sink.close();
  }
}

class Bzip2Decompressor extends _Bzip2Transformer {
  Bzip2Decompressor({bool checkCrc: false}) :
    super(new _Bzip2Decompressor(checkCrc));
}

class Bzip2Compressor extends _Bzip2Transformer {
  Bzip2Compressor({blockSizeFactor: 9}) :
    super(new _Bzip2Compressor(blockSizeFactor));
}
