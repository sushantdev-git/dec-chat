import 'dart:typed_data';

/// A robust, big-endian (network byte order) binary stream reader.
/// Optimized for parsing compact protocol packets with strict bounds checking.
class BinaryReader {
  final Uint8List _bytes;
  final ByteData _byteData;
  int _offset = 0;

  BinaryReader(Uint8List bytes)
      : _bytes = bytes,
        _byteData = ByteData.sublistView(bytes);

  /// Current read offset.
  int get offset => _offset;

  /// Remaining unread bytes.
  int get remaining => _bytes.length - _offset;

  /// Whether the reader has reached the end of the byte stream.
  bool get isAtEnd => _offset >= _bytes.length;

  /// Reads a single 8-bit unsigned integer.
  int readUint8() {
    _ensureAvailable(1);
    final value = _byteData.getUint8(_offset);
    _offset += 1;
    return value;
  }

  /// Reads a 16-bit big-endian unsigned integer.
  int readUint16() {
    _ensureAvailable(2);
    final value = _byteData.getUint16(_offset, Endian.big);
    _offset += 2;
    return value;
  }

  /// Reads a 32-bit big-endian unsigned integer.
  int readUint32() {
    _ensureAvailable(4);
    final value = _byteData.getUint32(_offset, Endian.big);
    _offset += 4;
    return value;
  }

  /// Reads a 64-bit big-endian unsigned integer.
  int readUint64() {
    _ensureAvailable(8);
    final value = _byteData.getUint64(_offset, Endian.big);
    _offset += 8;
    return value;
  }

  /// Reads a slice of [length] bytes.
  Uint8List readBytes(int length) {
    if (length < 0) {
      throw ArgumentError.value(length, 'length', 'Length cannot be negative');
    }
    _ensureAvailable(length);
    final slice = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return slice;
  }

  /// Reads all remaining unread bytes.
  Uint8List readRemaining() {
    if (isAtEnd) return Uint8List(0);
    return readBytes(remaining);
  }

  /// Skips [count] bytes forward.
  void skip(int count) {
    _ensureAvailable(count);
    _offset += count;
  }

  void _ensureAvailable(int count) {
    if (_offset + count > _bytes.length) {
      throw FormatException(
        'Unexpected end of binary stream. Requested $count bytes, but only $remaining available at offset $_offset.',
      );
    }
  }
}
