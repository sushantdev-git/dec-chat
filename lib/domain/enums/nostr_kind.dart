/// Enumeration of Nostr protocol event kinds as defined in NIP-01, NIP-04, NIP-28,
/// and extended with ephemeral kinds for BitChat decentralized mesh carriers.
enum NostrKind {
  /// User metadata (NIP-01).
  setMetadata(0),

  /// Short text note (NIP-01).
  textNote(1),

  /// Recommend relay (NIP-01).
  recommendServer(2),

  /// Contact list and petnames (NIP-02).
  contactList(3),

  /// Encrypted direct message (NIP-04).
  encryptedDirectMessage(4),

  /// Public chat channel creation (NIP-28).
  channelCreation(40),

  /// Public chat channel metadata (NIP-28).
  channelMetadata(41),

  /// Public chat channel message (NIP-28).
  channelMessage(42),

  /// Public chat channel hide message (NIP-28).
  channelHideMessage(43),

  /// Public chat channel mute user (NIP-28).
  channelMuteUser(44),

  /// Ephemeral BitChat mesh packet carrier (NIP-16 ephemeral range: 20000-29999).
  /// Relayed to connected clients but not persisted in relay databases.
  ephemeralCarrier(20000),

  /// Ephemeral BitChat geohash location broadcast carrier.
  locationBroadcast(20001),

  /// Unknown or unsupported event kind.
  unknown(-1);

  final int rawValue;

  const NostrKind(this.rawValue);

  /// Resolves an integer kind code into a known [NostrKind], or returns [unknown].
  static NostrKind fromValue(int value) {
    for (final kind in NostrKind.values) {
      if (kind.rawValue == value) {
        return kind;
      }
    }
    return NostrKind.unknown;
  }

  /// Whether this event kind is ephemeral (NIP-16: 20000 <= kind < 30000).
  /// Ephemeral events are forwarded by relays but never stored.
  bool get isEphemeral => rawValue >= 20000 && rawValue < 30000;

  /// Whether this event kind is regular (NIP-16: 1000 <= kind < 10000 or kind == 1).
  bool get isRegular => (rawValue >= 1000 && rawValue < 10000) || rawValue == 1;

  /// Whether this event is a channel-related event (NIP-28).
  bool get isChannel => rawValue >= 40 && rawValue <= 44;
}
