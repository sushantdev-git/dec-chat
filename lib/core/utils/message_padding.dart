import 'dart:typed_data';

/// Provides privacy-preserving message padding to obscure actual packet length.
/// Implements PKCS#7 padding toward fixed block sizes: {256, 512, 1024, 2048}.
class MessagePadding {
  static const List<int> blockSizes = [256, 512, 1024, 2048];

  /// Adds PKCS#7-style padding to reach the [targetSize].
  /// Declines padding if needed padding is > 255 bytes (fits 1-byte length marker).
  static Uint8List pad(Uint8List data, int targetSize) {
    if (data.length >= targetSize) return data;

    final paddingNeeded = targetSize - data.length;
    if (paddingNeeded <= 0 || paddingNeeded > 255) return data;

    final padded = Uint8List(targetSize);
    padded.setRange(0, data.length, data);
    for (int i = data.length; i < targetSize; i++) {
      padded[i] = paddingNeeded;
    }
    return padded;
  }

  /// Convenience method that pads data to its optimal bucket size.
  static Uint8List padToBucket(Uint8List data) {
    final target = optimalBlockSize(data.length);
    return pad(data, target);
  }

  /// Removes PKCS#7-style padding from data if valid.
  /// If padding is invalid or absent, returns the original data unchanged.
  static Uint8List unpad(Uint8List data) {
    if (data.isEmpty) return data;

    final padLength = data.last;
    if (padLength <= 0 || padLength > data.length) return data;

    final start = data.length - padLength;
    for (int i = start; i < data.length; i++) {
      if (data[i] != padLength) {
        return data; // Invalid PKCS#7 padding
      }
    }

    return Uint8List.fromList(data.sublist(0, start));
  }

  /// Calculates the optimal target block size for a given payload size.
  static int optimalBlockSize(int dataSize) {
    // Accounts for encryption overhead (~16 bytes tag)
    final totalSize = dataSize + 16;
    for (final size in blockSizes) {
      if (totalSize <= size) {
        return size;
      }
    }
    return dataSize;
  }
}
