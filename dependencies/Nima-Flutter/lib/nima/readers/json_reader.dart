import "dart:collection";
import "dart:typed_data";

import "stream_reader.dart";

abstract class JSONReader implements StreamReader {
  int _blockType = 0;
  @override
  int get blockType => _blockType;
  @override
  set blockType(int value) => _blockType = value;
  late dynamic _readObject;
  late ListQueue _context;

  JSONReader(Map object) {
    _readObject = object["container"];
    _context = ListQueue<dynamic>();
    _context.addFirst(_readObject);
  }

  dynamic readProp(String label) {
    dynamic head = _context.first;
    if (head is Map) {
      dynamic prop = head[label];
      head.remove(label);
      return prop;
    } else if (head is List) {
      return head.removeAt(0);
    }
    return null;
  }

  @override
  double readFloat32(String label) {
    dynamic val = readProp(label);
    if (val is num) {
      return val.toDouble();
    }
    return 0.0;
  }

  // Reads the array into ar
  @override
  void readFloat32Array(Float32List ar, String label) {
    _readArray(ar, label);
  }

  @override
  void readFloat32ArrayOffset(
      Float32List ar, int length, int offset, String label) {
    _readArrayOffset(ar, length, offset, label);
  }

  void _readArrayOffset(List ar, int length, int offset, String label) {
    dynamic val = readProp(label);
    if (val is! List) {
      return;
    }
    List array = val;
    int end = offset + length;
    for (int i = offset; i < end && (i - offset) < array.length; i++) {
      num val = array[i - offset] as num;
      if (ar is Float32List || ar is Float64List || ar is List<double>) {
        ar[i] = val.toDouble();
      } else {
        ar[i] = val.toInt();
      }
    }
  }

  void _readArray(List ar, String label) {
    dynamic val = readProp(label);
    if (val is! List) {
      return;
    }
    List array = val;
    for (int i = 0; i < ar.length && i < array.length; i++) {
      ar[i] = array[i];
    }
  }

  @override
  double readFloat64(String label) {
    dynamic val = readProp(label);
    if (val is num) {
      return val.toDouble();
    }
    return 0.0;
  }

  @override
  int readUint8(String label) {
    dynamic val = readProp(label);
    if (val is num) {
      return val.toInt();
    }
    return 0;
  }

  @override
  int readUint8Length() {
    return _readLength();
  }

  @override
  bool isEOF() {
    return _context.length <= 1 &&
        (_readObject is List || _readObject is Map) &&
        _readObject.length == 0;
  }

  @override
  int readInt8(String label) {
    dynamic val = readProp(label);
    if (val is num) {
      return val.toInt();
    }
    return 0;
  }

  @override
  int readUint16(String label) {
    dynamic val = readProp(label);
    if (val is num) {
      return val.toInt();
    }
    return 0;
  }

  @override
  void readUint8Array(Uint8List ar, int length, int offset, String label) {
    _readArrayOffset(ar, length, offset, label);
  }

  @override
  void readUint16Array(Uint16List ar, int length, int offset, String label) {
    _readArrayOffset(ar, length, offset, label);
  }

  @override
  int readInt16(String label) {
    dynamic val = readProp(label);
    if (val is num) {
      return val.toInt();
    }
    return 0;
  }

  @override
  int readUint16Length() {
    return _readLength();
  }

  @override
  int readUint32Length() {
    return _readLength();
  }

  @override
  int readUint32(String label) {
    dynamic val = readProp(label);
    if (val is num) {
      return val.toInt();
    }
    return 0;
  }

  @override
  int readInt32(String label) {
    dynamic val = readProp(label);
    if (val is num) {
      return val.toInt();
    }
    return 0;
  }

  @override
  int readVersion() {
    dynamic val = readProp("version");
    if (val is num) {
      return val.toInt();
    }
    return 0;
  }

  @override
  String readString(String label) {
    dynamic val = readProp(label);
    if (val is String) {
      return val;
    }
    return "";
  }

  @override
  bool readBool(String label) {
    dynamic val = readProp(label);
    if (val is bool) {
      return val;
    }
    return false;
  }

  // @hasOffset flag is needed for older (up until version 14) files.
  // Since the JSON Reader has been added in version 15, the field
  // here is optional.
  @override
  int readId(String label) {
    dynamic val = readProp(label);
    return (val is num ? val + 1 : 0).toInt();
  }

  @override
  void openArray(String label) {
    dynamic array = readProp(label);
    if (array != null) {
      _context.addFirst(array);
    }
  }

  @override
  void closeArray() {
    _context.removeFirst();
  }

  @override
  void openObject(String label) {
    dynamic o = readProp(label);
    if (o != null) {
      _context.addFirst(o);
    }
  }

  @override
  void closeObject() {
    _context.removeFirst();
  }

  int _readLength() {
    dynamic first = _context.first;
    if (first is List) {
      return first.length;
    } else if (first is Map) {
      return first.length;
    }
    return 0;
  }
  @override
  String get containerType => "json";
  ListQueue get context => _context;
}
