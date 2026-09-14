import 'dart:typed_data';
import 'package:collection/collection.dart';
import '../../core/utils/binary_reader.dart';
import '../../core/utils/binary_writer.dart';

/// Represents a single decoded fragment of a larger BitChat packet.
class FragmentPayload {
  /// 8-byte unique fragment assembly identifier.
  final Uint8List fragmentId;

  /// 0-based index of this fragment.
  final int index;

  /// Total number of fragments in this assembly.
  final int total;

  /// Raw byte slice belonging to the original packet.
  final Uint8List chunk;

  const FragmentPayload({
    required this.fragmentId,
    required this.index,
    required this.total,
    required this.chunk,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final eq = const ListEquality().equals;
    return other is FragmentPayload &&
        eq(other.fragmentId, fragmentId) &&
        other.index == index &&
        other.total == total &&
        eq(other.chunk, chunk);
  }

  @override
  int get hashCode => Object.hash(
        const ListEquality().hash(fragmentId),
        index,
        total,
        const ListEquality().hash(chunk),
      );
}

/// Slices large packets into MTU-safe fragments and reassembles them.
class FragmentCodec {
  static const int fragmentHeaderSize = 12; // 8 bytes ID + 2 bytes index + 2 bytes total

  /// Standard fragment payload capacity targeting BLE MTU limits (512 - ATT overhead).
  static const int defaultMaxFragmentPayloadSize = 469;

  /// Encodes a single fragment into binary wire bytes.
  static Uint8List encode(FragmentPayload fragment) {
    final writer = BinaryWriter(initialCapacity: fragmentHeaderSize + fragment.chunk.length);

    // 8-byte fragment ID
    final id = fragment.fragmentId.length >= 8
        ? fragment.fragmentId.sublist(0, 8)
        : (Uint8List(8)..setRange(0, fragment.fragmentId.length, fragment.fragmentId));
    writer.writeBytes(id);

    // 2-byte index & 2-byte total
    writer.writeUint16(fragment.index);
    writer.writeUint16(fragment.total);

    // Payload chunk
    writer.writeBytes(fragment.chunk);

    return writer.toBytes();
  }

  /// Decodes raw fragment bytes into a [FragmentPayload].
  static FragmentPayload? decode(Uint8List bytes) {
    if (bytes.length < fragmentHeaderSize) return null;

    final reader = BinaryReader(bytes);
    try {
      final fragmentId = reader.readBytes(8);
      final index = reader.readUint16();
      final total = reader.readUint16();

      if (total <= 0 || index >= total) return null;

      final chunk = reader.readRemaining();
      return FragmentPayload(
        fragmentId: fragmentId,
        index: index,
        total: total,
        chunk: chunk,
      );
    } catch (_) {
      return null;
    }
  }

  /// Slices an encoded packet byte array into a list of [FragmentPayload] instances.
  static List<FragmentPayload> slice(
    Uint8List packetBytes, {
    required Uint8List fragmentId,
    int maxChunkSize = defaultMaxFragmentPayloadSize,
  }) {
    if (packetBytes.isEmpty) return [];

    final totalChunks = (packetBytes.length + maxChunkSize - 1) ~/ maxChunkSize;
    final fragments = <FragmentPayload>[];

    for (int i = 0; i < totalChunks; i++) {
      final start = i * maxChunkSize;
      final end = (start + maxChunkSize > packetBytes.length) ? packetBytes.length : start + maxChunkSize;
      final chunk = Uint8List.fromList(packetBytes.sublist(start, end));

      fragments.add(
        FragmentPayload(
          fragmentId: fragmentId,
          index: i,
          total: totalChunks,
          chunk: chunk,
        ),
      );
    }

    return fragments;
  }
}
