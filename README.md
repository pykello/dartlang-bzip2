#Bzip2 Compression/Decompression Library for Dart
[![Build Status](https://drone.io/github.com/pykello/dartlang-bzip2/status.png)](https://drone.io/github.com/pykello/dartlang-bzip2/latest)

The goal of this library is to implement [bzip2](http://www.bzip.org/) compression/decompression algorithms for [dartlang](http://www.dartlang.org/).

The algorithm used here is based on [7-zip](http://www.7-zip.org/)'s source code.

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

##Limitations
The following features hasn't been implemented yet:

* Randomized mode,
* Compression.

