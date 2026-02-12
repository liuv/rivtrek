import "dart:collection";
import 'dart:convert';
import "dart:typed_data";

import "stream_reader.dart";

abstract class JSONReader implements StreamReader {
  @override
  late int blockType;

  late dynamic _readObject;
  late ListQueue _context;

  JSONReader(Map object) {
    _readObject = object["container"];
    _context = ListQueue();
    _context.addFirst(_readObject);
  }

  dynamic readProp(String label) {
    var head = _context.first;
    if (head is Map) {
      var prop = head[label];
      head.remove(label);
      return prop;
    } else if (head is List) {
      return head.removeAt(0);
    }
    return null;
  }

  @override
  double readFloat32(String label) {
    num? f = this.readProp(label);
    return f?.toDouble() ?? 0.0;
  }

  // Reads the array into ar
  @override
  Float32List readFloat32Array(int length, String label) {
    var ar = Float32List(length);
    this._readArray(ar, label);
    return ar;
  }

  void _readArray(List ar, String label) {
    List? array = this.readProp(label);
    if (array == null) return;
    for (int i = 0; i < ar.length; i++) {
      num val = array[i];
      ar[i] = ar.first is double ? val.toDouble() : val.toInt();
    }
  }

  @override
  double readFloat64(String label) {
    num? f = this.readProp(label);
    return f?.toDouble() ?? 0.0;
  }

  @override
  int readUint8(String label) {
    return this.readProp(label) ?? 0;
  }

  @override
  int readUint8Length() {
    return this._readLength();
  }

  @override
  bool isEOF() {
    return _context.length <= 1 && (_readObject as List).isEmpty;
  }

  @override
  int readInt8(String label) {
    return this.readProp(label) ?? 0;
  }

  @override
  int readUint16(String label) {
    return this.readProp(label) ?? 0;
  }

  @override
  Uint8List readUint8Array(int length, String label) {
    var ar = Uint8List(length);
    this._readArray(ar, label);
    return ar;
  }

  @override
  Uint16List readUint16Array(int length, String label) {
    var ar = Uint16List(length);
    this._readArray(ar, label);
    return ar;
  }

  @override
  int readInt16(String label) {
    return this.readProp(label) ?? 0;
  }

  @override
  int readUint16Length() {
    return this._readLength();
  }

  @override
  int readUint32Length() {
    return this._readLength();
  }

  @override
  int readUint32(String label) {
    return this.readProp(label) ?? 0;
  }

  @override
  int readInt32(String label) {
    return this.readProp(label) ?? 0;
  }

  @override
  int readVersion() {
    return this.readProp("version") ?? 0;
  }

  @override
  String readString(String label) {
    return this.readProp(label) ?? "";
  }

  @override
  bool readBool(String label) {
    return this.readProp(label) ?? false;
  }

  @override
  int readId(String label) {
    var val = this.readProp(label);
    return val is num ? (val.toInt() + 1) : 0;
  }

  @override
  void openArray(String label) {
    var array = this.readProp(label);
    _context.addFirst(array);
  }

  @override
  void closeArray() {
    _context.removeFirst();
  }

  @override
  void openObject(String label) {
    var o = this.readProp(label);
    _context.addFirst(o);
  }

  @override
  void closeObject() {
    this._context.removeFirst();
  }

  int _readLength() =>
      _context.first.length; // Maps and Lists both have a `length` property.

  @override
  Uint8List readAsset() {
    String? encodedAsset =
        readString("data"); // are we sure we need a label here?
    if (encodedAsset == null) return Uint8List(0);
    return Base64Decoder().convert(encodedAsset);
  }

  @override
  String get containerType => "json";
  ListQueue get context => _context;
}
