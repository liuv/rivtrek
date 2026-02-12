import "dart:typed_data";
import "binary_reader.dart";

class BlockReader extends BinaryReader {
  int _blockType = 0;
  @override
  int get blockType => _blockType;
  @override
  set blockType(int value) => _blockType = value;

  BlockReader(ByteData data)
      : _blockType = 0,
        super(data);

  BlockReader.fromBlock(this._blockType, ByteData stream) : super(stream);

  // A binary block is defined as a TLV with type of one byte, length of 4
  // bytes, and then the value following.
  @override
  BlockReader? readNextBlock(Map<String, int> types) {
    if (isEOF()) {
      return null;
    }
    int blockType = readUint8("");
    int length = readUint32("");

    Uint8List buffer = Uint8List(length);
    readUint8Array(buffer, buffer.length, 0, "");

    return BlockReader.fromBlock(blockType, ByteData.view(buffer.buffer));
  }
}
