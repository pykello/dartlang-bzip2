import 'package:unittest/unittest.dart';
import 'package:bzip2/bzip2.dart';

import 'dart:async';
import 'dart:io';

void main() {
  List<String> decompressTests = ['random.1', 'random.2', 'repeat.1', 
                                  'pg1399.txt', 'pg689.txt', 'empty'];
  List<String> compressTests = ['random.1', 'random.2', 'repeat.1', 'empty'];
  
  String testScript = new Options().script;
  String testDir = testScript.substring(0, testScript.indexOf("test.dart"));
    
  group('bzip2 decompress (CRC disabled):', () {
    for(String test in decompressTests) {
      testBzip2Decompressor(test, '${testDir}data/$test.bz2', 
          '${testDir}expected/$test', false);
    }
  });
  
  group('bzip2 decompress (CRC enabled):', () {
    for(String test in decompressTests) {
      testBzip2Decompressor(test, '${testDir}data/$test.bz2', 
          '${testDir}expected/$test', true);
    }
  });
  
  group('bzip2 compress:', () {
    test('invalid block size factor', () {
      expect(() => new Bzip2Compressor(blockSizeFactor: 100), throwsA(new isInstanceOf<ArgumentError>()));
    });
    
    for(String test in compressTests) {
      testBzip2Compressor(test, '${testDir}expected/$test');
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
                                        .transform(new Bzip2Decompressor(checkCrc: true));
    
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

