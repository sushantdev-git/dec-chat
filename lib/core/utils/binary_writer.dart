import 'dart:typed_data';

/// A dynamic, high-performance binary buffer builder.
/// Enforces big-endian (network byte order) encoding for multi-byte values.
class BinaryWriter {
  Uint8List _buffer;
  late ByteData _byteData;
  int _length = 0;

  BinaryWriter({int initialCapacity = 256})
      : _buffer = Uint8List(initialCapacity > 0 ? initialCapacity : 256) {
    _byteData = ByteData.view(_buffer.buffer);
  }

  /// Current written length in bytes.
  int get length => _length;

  /// Writes a single 8-bit unsigned integer.
  void writeUint8(int value) {
    _ensureCapacity(1);
    _byteData.setUint8(_length, value);
    _length += 1;
  }

  /// Writes a 16-bit big-endian unsigned integer.
  void writeUint16(int value) {
    _ensureCapacity(2);
    _byteData.setUint16(_length, value, Endian.big);
    _length += 2;
  }

  /// Writes a 32-bit big-endian unsigned integer.
  void writeUint32(int value) {
    _ensureCapacity(4);
    _byteData.setUint32(_length, value, Endian.big);
    _length += 4;
  }

  /// Writes a 64-bit big-endian unsigned integer.
  void writeUint64(int value) {
    _ensureCapacity(8);
    _byteData.setUint64(_length, value, Endian.big);
    _length += 8;
  }

  /// Writes a byte sequence.
  void writeBytes(List<int> bytes) {
    final count = bytes.length;
    if (count == 0) return;
    _ensureCapacity(count);
    _buffer.setRange(_length, _length + count, bytes);
    _length += count;
  }

  /// Returns the written bytes as a compact, sublist view or copy.
  Uint8List toBytes() {
    return Uint8List.fromList(_buffer.sublist(0, _length));
  }

  void _ensureCapacity(int additional) {
    final required = _length + additional;
    if (required > _buffer.length) {
      int newCapacity = _buffer.length * 2;
      while (newCapacity < required) {
        newCapacity *= 2;
      }
      final newBuffer = Uint8List(newCapacity);
      newBuffer.setRange(0, _length, _buffer);
      _buffer = newBuffer;
      _byteData = ByteData.sublistView(_buffer);
    }
  }
}
