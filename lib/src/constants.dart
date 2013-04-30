part of bzip2;

final List<int> _BZIP_SIGNATURE       = [0x42, 0x5a, 0x68];
final List<int> _FINISH_SIGNATURE     = [0x17, 0x72, 0x45, 0x38, 0x50, 0x90];
final List<int> _BLOCK_SIGNATURE      = [0x31, 0x41, 0x59, 0x26, 0x53, 0x59];

const int _MAX_BYTES_REQUIRED          = 1048576;
const int _BLOCK_SIZE_STEP             = 100000;
const int _MAX_BLOCK_SIZE              = 900000;
const int _MAX_ALPHA_SIZE              = 258;
const int _LEVEL_BITS                  = 5;
const int _MAX_HUFFMAN_LEN             = 20;
const int _RLE_MODE_REP_SIZE           = 4;

const int _ORIGIN_BIT_COUNT           = 24;

const int _TABLE_COUNT_BITS           = 3;
const int _TABLE_COUNT_MIN            = 2;
const int _TABLE_COUNT_MAX            = 6;

const int _GROUP_SIZE                 = 50;
const int _HUFFMAN_PASSES             = 4;
const int _MAX_HUFFMAN_LEN_FOR_ENCODING = 16;

const int _SELECTOR_COUNT_BITS        = 15;
const int _SELECTOR_COUNT_MAX         = (2 + (_MAX_BLOCK_SIZE ~/ _GROUP_SIZE));