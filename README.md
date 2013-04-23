#Bzip2 Compression/Decompression Library for Dart

The goal of this library is to implement [bzip2](http://www.bzip.org/) compression/decompression algorithms for [dartlang](http://www.dartlang.org/).

The algorithm used here is based on [7-zip](http://www.7-zip.org/)'s source code.

##Install

###Depend on it
Add this to your package's pubspec.yaml file:

    dependencies:
      bzip2: 0.0.1

If your package is an [application package](http://pub.dartlang.org/doc/glossary.html#application-package) you should use **any** as the [version constraint](http://pub.dartlang.org/doc/glossary.html#version-constraint).

###Install it
If you're using the Dart Editor, choose:

    Menu > Tools > Pub Install

Or if you want to install from the command line, run:

    $ pub install

###Import it
Now in your Dart code, you can use:

    import 'package:bzip2/bzip2.dart';

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

