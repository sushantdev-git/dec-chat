import 'dart:collection';

/// High-performance Least-Recently-Used (LRU) seen-cache for packet deduplication.
///
/// Implements the BitChat mesh specification:
/// - 1,000-entry capacity
/// - 5-minute time-to-live (TTL) expiry
/// - Immediate duplicate suppression to halt broadcast storm loops
class SeenPacketCache {
  final int capacity;
  final Duration ttl;
  final LinkedHashMap<String, DateTime> _entries = LinkedHashMap<String, DateTime>();

  SeenPacketCache({
    this.capacity = 1000,
    this.ttl = const Duration(minutes: 5),
  });

  /// Checks if a packet identifier has already been seen.
  bool contains(String packetId, {DateTime? currentTime}) {
    _pruneExpired(now: currentTime);
    return _entries.containsKey(packetId);
  }

  /// Atomic test-and-set operation:
  ///
  /// Returns `true` if the packet is NEW and was successfully added to the cache.
  /// Returns `false` if the packet was ALREADY SEEN within the TTL window (duplicate).
  bool checkAndAdd(String packetId, {DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();
    _pruneExpired(now: now);

    final existingTimestamp = _entries[packetId];
    if (existingTimestamp != null) {
      if (now.difference(existingTimestamp) <= ttl) {
        // Move to most recently used
        _entries.remove(packetId);
        _entries[packetId] = existingTimestamp;
        return false; // Duplicate packet!
      } else {
        _entries.remove(packetId);
      }
    }

    // Evict oldest entry if at capacity
    if (_entries.length >= capacity) {
      _entries.remove(_entries.keys.first);
    }

    _entries[packetId] = now;
    return true; // Fresh packet
  }

  /// Manually removes a packet identifier from the cache.
  void remove(String packetId) {
    _entries.remove(packetId);
  }

  /// Number of active non-expired entries in the cache.
  int get size {
    _pruneExpired();
    return _entries.length;
  }

  /// Clears all entries from the cache.
  void clear() {
    _entries.clear();
  }

  void _pruneExpired({DateTime? now}) {
    final current = now ?? DateTime.now();
    _entries.removeWhere((_, timestamp) => current.difference(timestamp) > ttl);
  }
}
