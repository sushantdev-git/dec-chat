/// Identifies the underlying network transport medium over which packets are routed.
enum TransportMedium {
  /// Local Bluetooth Low Energy dual-role Central/Peripheral mesh link.
  bleMesh,

  /// Global internet fallback via Nostr WebSocket relays.
  nostr,

  /// Local area network / Wi-Fi Direct link.
  lan,

  /// Headless in-memory virtual radio medium for testing and simulation.
  simulated,
}
