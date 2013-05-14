import 'package:bzip2/bzip2.dart';
import 'dart:async';
import 'dart:io';

void main() {
  Options options = new Options();
  List<String> args = options.arguments;
  
  if (args.length != 2) {
    print("Syntax: ${options.executable} ${options.script} inputfile outputfile");
  }
  else {
    RandomAccessFile outputFile = new File(args[1]).openSync(mode: FileMode.WRITE);
    Stream inputStream = new File(args[0]).openRead();
    Stream compressedStream = inputStream.transform(new Bzip2Compressor());
    
    compressedStream.listen((var data) {
      outputFile.writeFrom(data, 0, data.length);
    }, onDone: () {
      outputFile.close();
    });
  }
}
