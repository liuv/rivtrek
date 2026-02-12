import "json_reader.dart";

class JSONBlockReader extends JSONReader {
  int _blockType = 0;
  @override
  int get blockType => _blockType;
  @override
  set blockType(int value) => _blockType = value;

  JSONBlockReader(Map object)
      : _blockType = 0,
        super(object);

  JSONBlockReader.fromObject(this._blockType, Map object)
      : super(object);

  @override
  JSONBlockReader? readNextBlock(Map<String, int> blockTypes) {
    if (isEOF()) {
      return null;
    }

    var obj = <dynamic, dynamic>{};
    obj["container"] = _peek();
    int type = readBlockType(blockTypes);
    dynamic c = context.first;
    if (c is Map) {
      c.remove(nextKey);
    } else if (c is List) {
      c.removeAt(0);
    }

    return JSONBlockReader.fromObject(type, obj);
  }

  int readBlockType(Map<String, int> blockTypes) {
    dynamic next = _peek();
    int bType = 0;
    if (next is Map) {
      dynamic c = context.first;
      if (c is Map) {
        bType = blockTypes[nextKey] ?? 0;
      } else if (c is List) {
        // Objects are serialized with "type" property.
        dynamic nType = next["type"];
        bType = blockTypes[nType] ?? 0;
      }
    } else if (next is List) {
      // Arrays are serialized as "type": [Array].
      bType = blockTypes[nextKey] ?? 0;
    }
    return bType;
  }

  dynamic _peek() {
    dynamic stream = context.first;
    dynamic next;
    if (stream is Map) {
      next = stream[nextKey];
    } else if (stream is List) {
      next = stream[0];
    }
    return next;
  }

  dynamic get nextKey {
    dynamic first = context.first;
    if (first is Map) {
      return first.keys.first;
    }
    return null;
  }
}
