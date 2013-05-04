import 'package:unittest/unittest.dart';
import 'package:bzip2/bzip2.dart';

import 'dart:async';
import 'dart:io';

void main() {
  List<String> decompressTests = ['random.1', 'random.2', 'pg1399.txt', 'pg689.txt', 'empty'];
  List<String> compressTests = ['random.1', 'random.2', 'empty'];
  String testDir = new Directory.current().path + "/test";
  
  testBitBuffer();
  
  group('bzip2 decompress (CRC disabled):', () {
    for(String test in decompressTests) {
      testBzip2Decompressor(test, '$testDir/data/$test.bz2', 
          '$testDir/expected/$test', false);
    }
  });
  
  group('bzip2 decompress (CRC enabled):', () {
    for(String test in decompressTests) {
      testBzip2Decompressor(test, '$testDir/data/$test.bz2', 
          '$testDir/expected/$test', true);
    }
  });
  
  group('bzip2 compress:', () {
    test('invalid block size factor', () {
      expect(() => new Bzip2Compressor(blockSizeFactor: 100), throwsA(new isInstanceOf<ArgumentError>()));
    });
    
    for(String test in compressTests) {
      testBzip2Compressor(test, '$testDir/expected/$test');
    }
  });
}

void testBzip2Decompressor(String testName, String inputFilename, 
                           String expectedFilename, bool checkCrc) {
  test('test $testName', () {
    Stream<List<int>> inputStream = new File(inputFilename).openRead();
    Stream<List<int>> decodedStream = inputStream.transform(new Bzip2Decompressor(checkCrc: checkCrc));
    
    verifyStreamOutput(decodedStream, expectedFilename);
  });
}

void testBzip2Compressor(String testName, String inputFilename) {
  test('test $testName', () {
    Stream<List<int>> inputStream = new File(inputFilename).openRead()
                                        .transform(new Bzip2Compressor(blockSizeFactor: 1))
                                        .transform(new Bzip2Decompressor());
    
    verifyStreamOutput(inputStream, inputFilename);
  });
}

void verifyStreamOutput(Stream inputStream, String expectedFilename) {
  RandomAccessFile expectedFile = new File(expectedFilename).openSync(mode: FileMode.READ);
  
  bool done = false;
  
  var dataCallback = (var data) {
    if (data.length > 0) {
      List<int> expectedData = expectedFile.readSync(data.length);
      expect(data, equals(expectedData));
    }
  };
  var asyncDataCallback = expectAsyncUntil1(dataCallback, () => done);
  
  var doneCallback = () {
    expect(expectedFile.readByteSync(), equals(-1));
    done = true;
    asyncDataCallback([]);
  };
  var asyncDoneCallback = expectAsync0(doneCallback);
  
  inputStream.listen(asyncDataCallback, onDone: asyncDoneCallback);
}

void testBitBuffer() {
  group('bitbuffer:', () {
    BitBuffer bitbuffer;
    
    setUp(() {
      bitbuffer = new BitBuffer(2);
    });
    
    test('write byte 1', () {
      bitbuffer.writeByte(255);
      expect(bitbuffer.readByte(), 255);
    });
    
    test('write byte 2', () {
      bitbuffer.writeByte(1);
      bitbuffer.writeByte(2);
      expect(bitbuffer.readByte(), 1);
      bitbuffer.writeByte(3);
      expect(bitbuffer.readByte(), 2);
      expect(bitbuffer.readByte(), 3);
    });
    
    test('overflow', () {
      bitbuffer.writeByte(1);
      bitbuffer.writeByte(1);
      expect(() => bitbuffer.writeByte(3), throws);
    });
    
    test('read bits 1', () {
      bitbuffer.writeByte(255);
      expect(bitbuffer.readBits(3), equals(7));
      expect(bitbuffer.readBits(5), equals(31));
    });
    
    test('read bits 2', () {
      bitbuffer.writeByte(1);
      bitbuffer.writeByte(1);
      expect(bitbuffer.readBits(1), equals(0));
      expect(bitbuffer.readBits(8), equals(2));
      expect(bitbuffer.readBits(7), equals(1));
    });
    
    test('out of data', () {
      bitbuffer.writeByte(1);
      expect(() => bitbuffer.readBits(9), throws);
    });
    
    test('read bytes', () {
      bitbuffer.writeByte(1);
      bitbuffer.writeByte(2);
      expect(bitbuffer.readBytes(2), equals([1, 2]));
    });
    
    test('peek bits', () {
      bitbuffer.writeByte(1);
      bitbuffer.writeByte(2);
      expect(bitbuffer.peekBits(8), equals(1));
      expect(bitbuffer.peekBits(8), equals(1));
      bitbuffer.move(8);
      expect(bitbuffer.peekBits(8), equals(2));
      expect(bitbuffer.readByte(), equals(2));
    });
  });
}
