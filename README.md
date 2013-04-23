#Bzip2 Compression/Decompression Library for Dart

The goal of this library is to implement [bzip2](http://www.bzip.org/) compression/decompression algorithms for [dartlang](http://www.dartlang.org/).

##Example Usage
The following code reads a compressed text file and prints it line by line:

    import 'package:bzip2/bzip2.dart';
    import 'dart:async';
    import 'dart:io';

    ...
    new File('compressedFile.bz2').openRead()
        .transform(new Bzip2Decompressor())
        .transform(new StringDecoder())
        .transform(new LineTransformer())
        .listen((var line) => print(line));
