import "json_reader.dart";

class JSONBlockReader extends JSONReader {
  @override
  int blockType;

  JSONBlockReader(Map object)
      : blockType = 0,
        super(object);

  JSONBlockReader.fromObject(int type, Map object)
      : blockType = type,
        super(object);

  @override
  JSONBlockReader? readNextBlock(Map<String, int> blockTypes) {
    if (isEOF()) {
      return null;
    }

    var obj = {};
    obj["container"] = _peek();
    var type = readBlockType(blockTypes);
    var c = context.first;
    if (c is Map) {
      c.remove(nextKey);
    } else if (c is List) {
      c.removeAt(0);
    }

    return JSONBlockReader.fromObject(type ?? 0, obj);
  }

  int? readBlockType(Map<String, int> blockTypes) {
    var next = _peek();
    int? bType;
    if (next is Map) {
      var c = context.first;
      if (c is Map) {
        bType = blockTypes[nextKey];
      } else if (c is List) {
        // Objects are serialized with "type" property.
        var nType = next["type"];
        bType = blockTypes[nType];
      }
    } else if (next is List) {
      // Arrays are serialized as "type": [Array].
      bType = blockTypes[nextKey];
    }
    return bType;
  }

  dynamic _peek() {
    var stream = context.first;
    var next;
    if (stream is Map) {
      next = stream[nextKey];
    } else if (stream is List) {
      next = stream[0];
    }
    return next;
  }

  dynamic get nextKey => context.first.keys.first;
}
