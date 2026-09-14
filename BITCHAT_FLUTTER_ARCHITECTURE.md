# BitChat Mobile: Architecture Blueprint & Technical Specification (Flutter)

**Document Version:** 1.0.0  
**Author:** Principal Distributed Systems & Mobile Security Architect  
**Target Platform:** Flutter (iOS & Android)  
**Reference Protocol:** [permissionlesstech/bitchat](https://github.com/permissionlesstech/bitchat) (Protocol v2.0 / BLE Architecture v3)  

---

## 1. Executive Summary & Vision

BitChat is a decentralized, peer-to-peer, dual-transport messaging protocol engineered for secure, censorship-resistant communication operating in adversarial, partitioned, or zero-connectivity environments. 

Its architecture rests upon five foundational tenets:
1. **Zero Infrastructure & Zero Accounts:** No phone numbers, servers, registration, or accounts. Identity is derived strictly from cryptographic key pairs.
2. **Dual Transport Harmony:** Ad-hoc local communication runs over a **Bluetooth Low Energy (BLE) multi-hop mesh network** (offline). Distant communication falls back seamlessly to **Nostr relays over WebSockets** (internet).
3. **End-to-End Encryption (E2EE) with Forward Secrecy:** Private sessions negotiate keys using the **Noise Protocol Framework (`Noise_XX_25519_ChaChaPoly_SHA256`)**. 
4. **Controlled Flooding & Opportunistic Store-and-Forward:** Multi-hop mesh routing employs degree-dependent TTL clamping, LRU deduplication, fanout subsetting, randomized jitter, and opportunistic couriers (spray-and-wait).
5. **Ephemerality by Default & Panic Wipe:** Chat timelines reside purely in volatile memory. All persisted artifacts (outbox mail, identity keys) are cryptographically sealed or wiped instantly upon a panic trigger.

This document specifies the complete architectural design, engineering trade-offs, and implementation blueprint for building a **production-grade Flutter client** faithful to the BitChat specification and binary protocol.

---

## 2. BitChat Protocol Specifications (Under the Hood)

### 2.1 Wire Format & Binary Protocol

BitChat rejects heavy serialization formats (JSON, Protobuf) on the BLE mesh in favor of an optimized, big-endian binary packet format designed for constrained MTU limits (≤ 512 bytes):

#### Packet Wire Layout

```
Header (Fixed: 14 bytes for v1, 16 bytes for v2):
+--------+------+-----+-------------------+-------+------------------+
|Version | Type | TTL | Timestamp (UInt64)| Flags |  PayloadLength   |
| 1 byte |1 byte|1byte|      8 bytes      | 1 byte| 2 bytes (4 for v2|
+--------+------+-----+-------------------+-------+------------------+

Variable Section:
+----------+-----------------------+---------------------+-------------------+---------------------+
| SenderID | RecipientID (Optional)| Route (Optional)    | Payload (Variable)| Signature (Optional)|
| 8 bytes  | 8 bytes (flag 0x01)   | (flag 0x08)         | N bytes           | 64 bytes (flag 0x02)|
+----------+-----------------------+---------------------+-------------------+---------------------+
```

#### Flags Bitmask
* `0x01`: `hasRecipient` — Directed packet.
* `0x02`: `hasSignature` — Packet carries a 64-byte Ed25519 signature.
* `0x04`: `isCompressed` — Payload is compressed (zlib/deflate if > 256 bytes). Preceded by 2-byte uncompressed length.
* `0x08`: `hasRoute` — Source routing enabled (sequence of 8-byte intermediate peer IDs).
* `0x10`: `isRSR` — Reverse Source Route flag.

#### Packet Types (`MessageType`)
| Hex | Identifier | Description |
|---|---|---|
| `0x01` | `announce` | Peer presence announcement (TLV encoded: nickname, Noise key, Ed25519 key, neighbors, capabilities) |
| `0x02` | `message` | Broadcast public chat message (plain text) |
| `0x03` | `leave` | Graceful peer departure notice |
| `0x04` | `courierEnvelope` | Sealed store-and-forward bundle carried by intermediate nodes |
| `0x10` | `noiseHandshake` | Ephemeral Noise XX key exchange message |
| `0x11` | `noiseEncrypted` | E2EE ciphertext (padded to 256/512/1024/2048 bytes) |
| `0x20` | `fragment` | Packet fragment (8-byte frag ID, 2-byte index, 2-byte total) |
| `0x21` | `requestSync` | Gossip history synchronization request |
| `0x22` | `fileTransfer` | Large binary file chunk transfer |
| `0x23` | `boardPost` | Signed geohash bulletin board post |
| `0x24` | `prekeyBundle` | Gossiped one-time prekeys for asynchronous messaging |
| `0x25` | `groupMessage` | Group-encrypted message (group ID + ChaChaPoly ciphertext) |
| `0x26` / `0x27` | `ping` / `pong` | Directed latency/topology diagnostics |
| `0x28` | `nostrCarrier` | Nostr event ferried between mesh-only peer and gateway |
| `0x29` | `voiceFrame` | Live push-to-talk voice frame (signed broadcast) |
| `0x2C` | `announceV2` | Identity-free rotating peer ID presence |

#### Inner Noise Payload Types (Decrypted from `0x11`)
When an `0x11` (`noiseEncrypted`) payload is decrypted, its first byte reveals the real application payload:
* `0x01`: `privateMessage`
* `0x02`: `readReceipt`
* `0x03`: `delivered`
* `0x06`: `groupInvite`
* `0x07`: `groupKeyUpdate`
* `0x08`: `voiceFrame`
* `0x10` / `0x11`: `verifyChallenge` / `verifyResponse` (In-person QR verification)
* `0x12`: `vouch` (Web-of-trust attestation)
* `0x20`: `privateFile`
* `0x21`: `authenticatedPeerState`

### 2.2 Identity & Cryptographic Primitives

Each client generates two primary asymmetric key pairs:
1. **Curve25519 Key Pair:** Used for Noise Protocol Diffie-Hellman key exchange.
2. **Ed25519 Key Pair:** Used for signing public announcements, packets, and identity binding.

* **Peer ID:** The first 8 bytes of `SHA-256(Curve25519_Static_Public_Key)`. This 8-byte identifier is used in all mesh packet headers.
* **Signing Envelope:** Signatures are computed over the packet representation with `TTL = 0`, stripping the mutable TTL byte so relays can decrement TTL in transit without breaking the cryptographic signature.

### 2.3 Mesh Routing & Controlled Flooding Algorithm

To prevent broadcast storms while ensuring delivery across lossy radio links:
1. **TTL Clamping:** Packets originate with `TTL = 7`. Relays adaptively clamp TTL:
   - High density ($\ge 6$ active links): Cap broadcast TTL at $5$.
   - Low density ($\le 2$ active links): Relay at incoming TTL $- 1$.
2. **Deduplication LRU Seen-Set:** A cache of 1,000 recent packet identifiers with a 5-minute expiry. An incoming duplicate instantly cancels any pending relay.
3. **Randomized Relay Jitter:** Nodes delay relaying by a pseudo-random interval between $10\text{ ms}$ and $220\text{ ms}$ (wider window in dense topologies). This prevents simultaneous packet collisions over the 2.4 GHz ISM band and lets duplicate suppression take effect.
4. **Degree-Based Fanout Subsetting:** Broadcast traffic is forwarded to a deterministic, pseudo-random subset ($\approx \log_2(\text{degree})$) of connected peers, seeded by the packet ID.
5. **Split-Horizon Rule:** A packet is never relayed back out through the link on which it arrived.
6. **Directed Routing:** Packets with a target `recipientID` follow recorded source routes (derived from 1-hop neighbor lists in recent `announce` packets). If no route exists, they fall back to flooding with full fanout.

### 2.4 Nostr Dual-Transport Fallback

When two peers are mutual favorites or direct messaging out of radio range:
* Transport seamlessly pivots to Nostr relays (`wss://...`).
* The message is packaged inside a BitChat encrypted envelope and published as an ephemeral Nostr event.
* Geographic channels leverage geohashes (e.g. `9q8yy` for San Francisco) as channel identifiers published to public relays.

---

## 3. Flutter Architectural Challenge & Core Solution

### 3.1 The Mobile Bluetooth Mesh Dilemma in Flutter

In Flutter, standard BLE plugins (`flutter_blue_plus`, `reactive_ble`) **only support BLE Central mode** (scanning and connecting to devices). They cannot:
1. Act as a **BLE Peripheral** (broadcasting GATT advertisements).
2. Host a **GATT Server** with read/write characteristics.
3. Handle incoming MTU negotiations or peripheral-side connection events.

A peer-to-peer mesh node **must simultaneously act as both Central and Peripheral** on the same radio:
* **As a Peripheral:** Advertise BitChat Service UUID (`F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C`), listen for connections from nearby nodes, receive incoming packet writes, and dispatch notifications.
* **As a Central:** Scan for BitChat Service UUID advertisements, connect to discovered peers, discover characteristics, write packets, and subscribe to notifications.

### 3.2 Architectural Solution: The Radio Link Port Pattern

Following the clean separation of BitChat V3 (CoreBluetooth isolation), we decouple the system into:
1. **A Thin Native Link Layer (`BLELinkLayer`):**
   - iOS: Swift module importing `CoreBluetooth` (`CBCentralManager` + `CBPeripheralManager`).
   - Android: Kotlin module importing `android.bluetooth` (`BluetoothLeScanner`, `BluetoothLeAdvertiser`, `BluetoothGattServer`, `BluetoothGatt`).
   - Zero protocol knowledge: It deals strictly with raw bytes, link connection events, and MTU limits.
2. **A Pure Dart Mesh Core:**
   - 100% of the mesh algorithms (packet encoding, fragmentation, TTL, deduplication, routing, jitter, Noise crypto, Nostr, and state machines) are implemented in Dart.
   - Communicates with native radios via a typed Platform Channel / FFI interface.
3. **The Simulation Superpower (`SimulatedLinkLayer`):**
   - Because the mesh engine is pure Dart and depends only on an abstract `LinkLayerPort`, we can construct headless virtual mesh simulations! We can spin up 20 virtual nodes in automated Dart integration tests, simulate multi-hop delivery, packet drops, and partitions—**completely independent of physical Bluetooth hardware.**

```
+-----------------------------------------------------------------------------------+
|                               FLUTTER PRESENTATION                                |
|  Terminal/IRC Console, Peer Radar, Geohash Picker, QR Verification, Panic Trigger  |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|                             APPLICATION & STATE LAYER                             |
|  TimelineState, PeerRegistryState, ActiveChannelState, PanicWipeCoordinator       |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|                                 DOMAIN MESH CORE                                  |
|  +--------------------+  +----------------------+  +---------------------------+  |
|  | MessageRouter      |  | MeshEngine (Flood)   |  | NoiseSessionManager       |  |
|  | - Direct Mesh      |  | - TTL / Jitter       |  | - Noise_XX Handshake      |  |
|  | - Nostr Fallback   |  | - Dedup LRU (1000)   |  | - ChaCha20-Poly1305       |  |
|  | - Courier Outbox   |  | - Fanout Subsetting  |  | - Curve25519 / Ed25519    |  |
|  +--------------------+  +----------------------+  +---------------------------+  |
|  +--------------------+  +----------------------+  +---------------------------+  |
|  | FragmentationBuffer|  | WireCodec (Binary)   |  | NostrRelayPool            |  |
|  | - Slice (469 bytes)|  | - BitchatPacket v1/2 |  | - WebSocket Connections   |  |
|  | - Reassembly       |  | - TLV Announcement   |  | - Geohash Channels        |  |
|  +--------------------+  +----------------------+  +---------------------------+  |
+-----------------------------------------------------------------------------------+
                                         │
                                         ▼
+-----------------------------------------------------------------------------------+
|                               PORTS & ADAPTERS LAYER                              |
|   LinkLayerPort              CryptoPort             StoragePort       LocationPort|
+-----------------------------------------------------------------------------------+
         │                           │                     │                  │
         ▼                           ▼                     ▼                  ▼
+─────────────────+         +─────────────────+   +────────────────+   +────────────+
|   NATIVE RADIO  |         | Dart Cryptography|  | Secure KeyRing |   | GPS Sensor |
|  Method/Event   |         | (X25519/Ed25519/ |  | (Keychain /    |   | -> Geohash |
|    Channels     |         | ChaChaPoly)      |  |  Keystore)     |   +────────────+
+─────────────────+         +─────────────────+   +────────────────+
   │           │
   ▼           ▼
[iOS Swift] [Android Kotlin]
CoreBluetooth  BluetoothGatt
```

---

## 4. Target Directory Structure (Clean Architecture)

```
bitchat_flutter/
├── android/app/src/main/kotlin/com/bitchat/mesh/
│   ├── ble/
│   │   ├── BleAdvertiserManager.kt     # BLE Peripheral advertiser
│   │   ├── BleGattServerManager.kt     # GATT Server (accept writes, send notify)
│   │   ├── BleScannerManager.kt        # BLE Central scanner
│   │   ├── BleGattClientManager.kt     # Central connections (write, receive notify)
│   │   └── BleRadioCoordinator.kt      # Coordinates dual-role radio state
│   └── BlePlatformChannel.kt           # Method/Event channel bridge
├── ios/Runner/
│   ├── BLE/
│   │   ├── BLEPeripheralController.swift # CBPeripheralManager & GATT Server
│   │   ├── BLECentralController.swift    # CBCentralManager & Scanner
│   │   └── BLERadioBridge.swift          # CoreBluetooth coordination
│   └── BlePlatformChannel.swift          # Flutter channel bindings
├── lib/
│   ├── app/
│   │   ├── app.dart                    # App root & theme config
│   │   └── routes.dart                 # Navigation & dialogs
│   ├── core/
│   │   ├── constants/
│   │   │   ├── ble_constants.dart      # Service UUID, Characteristic UUID, MTU
│   │   │   └── protocol_constants.dart # Limits, timeouts, retry counts
│   │   ├── error/
│   │   │   └── failure.dart            # Typed failure classes
│   │   └── utils/
│   │       ├── binary_reader.dart      # Network byte order binary parser
│   │       ├── binary_writer.dart      # Big-endian binary buffer builder
│   │       └── geohash.dart            # Geohash base32 encoding/decoding
│   ├── domain/
│   │   ├── entities/
│   │   │   ├── bitchat_packet.dart     # Protocol wire packet
│   │   │   ├── message.dart            # Domain chat message
│   │   │   ├── peer.dart               # Peer identity & state
│   │   │   ├── channel.dart            # Mesh / Geohash / DM channels
│   │   │   └── courier_envelope.dart   # Store-and-forward sealed payload
│   │   ├── enums/
│   │   │   ├── message_type.dart       # Announce, message, noise, fragment...
│   │   │   └── noise_payload_type.dart # Private message, receipt, file...
│   │   ├── ports/
│   │   │   ├── link_layer_port.dart    # BLE Radio interface (events & commands)
│   │   │   ├── nostr_port.dart         # Nostr transport interface
│   │   │   ├── crypto_port.dart        # Noise & signature interface
│   │   │   ├── secure_storage_port.dart# Identity persistence port
│   │   │   └── location_port.dart      # Geolocation port
│   │   └── services/
│   │       ├── mesh_engine.dart        # Controlled flooding, dedup, jitter
│   │       ├── fragmentation_engine.dart# Slicing & reassembly
│   │       ├── noise_session_manager.dart# Noise XX handshake & cipher states
│   │       ├── message_router.dart     # Transport selection (Mesh vs Nostr)
│   │       ├── courier_service.dart    # Spray-and-wait outbox
│   │       └── irc_command_parser.dart # Parsing /msg, /who, /slap, /ping
│   ├── infrastructure/
│   │   ├── adapters/
│   │   │   ├── native_ble_link_adapter.dart # Calls platform channels
│   │   │   ├── simulated_link_adapter.dart  # In-memory virtual mesh test radio
│   │   │   ├── nostr_relay_adapter.dart     # WebSocket Nostr client
│   │   │   ├── cryptography_adapter.dart    # X25519, Ed25519, ChaChaPoly
│   │   │   ├── secure_storage_adapter.dart  # flutter_secure_storage / Keychain
│   │   │   └── geolocator_adapter.dart      # Geolocator plugin adapter
│   │   └── codecs/
│   │       ├── binary_protocol_codec.dart   # BitchatPacket <-> Uint8List
│   │       ├── announcement_codec.dart      # TLV Announcement encode/decode
│   │       └── fragment_codec.dart          # Fragment payload slicing
│   ├── presentation/
│   │   ├── state/
│   │   │   ├── chat_controller.dart         # Timeline & sending
│   │   │   ├── peer_controller.dart         # Discovered peers & signal
│   │   │   ├── channel_controller.dart      # Active channels & geohash
│   │   │   └── panic_controller.dart        # Emergency wipe handler
│   │   ├── theme/
│   │   │   └── terminal_theme.dart          # Monospace, green/amber CRT look
│   │   ├── views/
│   │   │   ├── terminal_chat_view.dart      # Main IRC chat console
│   │   │   ├── peer_radar_view.dart         # Discovered mesh nodes
│   │   │   ├── geohash_channels_view.dart   # Location channel selector
│   │   │   ├── identity_qr_view.dart        # Fingerprint & QR verification
│   │   │   └── widgets/
│   │   │       ├── command_input_bar.dart   # Terminal input with tab-completion
│   │   │       ├── message_bubble.dart      # IRC style formatted row
│   │   │       └── signal_badge.dart        # BLE RSSI / hop count indicator
│   └── main.dart
└── test/
    ├── domain/
    │   ├── binary_protocol_test.dart        # Binary packet serialization tests
    │   ├── noise_protocol_test.dart         # Handshake & cipher vector tests
    │   ├── fragmentation_test.dart          # Large file chunking & reassembly
    │   └── mesh_simulation_test.dart        # 10-node virtual mesh relay test!
    └── fixtures/
```

---

## 5. Detailed Component Specifications

### 5.1 Native BLE Link Layer Interface (`LinkLayerPort`)

The port contract between pure Dart and native platform radios:

```dart
abstract class LinkLayerPort {
  /// Stream of asynchronous events from the physical radio
  Stream<LinkEvent> get events;

  /// Start simultaneous GATT advertising & scanning
  Future<void> startRadio({required String serviceUuid});

  /// Stop radio operations
  Future<void> stopRadio();

  /// Send raw bytes to a specific physical peer link
  Future<void> sendBytes({
    required String peerAddress,
    required Uint8List bytes,
  });

  /// Broadcast raw bytes to all connected direct links
  Future<void> broadcastBytes({
    required Uint8List bytes,
    String? excludePeerAddress, // Split-horizon support
  });

  /// Active connection count
  int get activeLinkCount;
}

sealed class LinkEvent {
  const LinkEvent();
}

class PeerDiscoveredEvent extends LinkEvent {
  final String peerAddress;
  final int rssi;
  final Uint8List? advertisementData;
  PeerDiscoveredEvent(this.peerAddress, this.rssi, this.advertisementData);
}

class LinkConnectedEvent extends LinkEvent {
  final String peerAddress;
  final int negotiatedMtu;
  LinkConnectedEvent(this.peerAddress, this.negotiatedMtu);
}

class LinkDisconnectedEvent extends LinkEvent {
  final String peerAddress;
  LinkDisconnectedEvent(this.peerAddress);
}

class BytesReceivedEvent extends LinkEvent {
  final String peerAddress;
  final Uint8List bytes;
  BytesReceivedEvent(this.peerAddress, this.bytes);
}
```

### 5.2 Cryptography & Noise XX State Machine

* **Handshake Pattern:** `Noise_XX_25519_ChaChaPoly_SHA256`
* **Pattern Structure:**
  ```
  -> e
  <- e, ee, s, es
  -> s, se
  ```
* **Dart Implementation:** Using `cryptography` package:
  - Key Exchange: `X25519()`
  - AEAD Cipher: `ChaCha20.poly1305Aead()`
  - Hash & HKDF: `Sha256()`
  - Signatures: `Ed25519()`
* **CipherState Transition:** Once message 3 is exchanged, two symmetric `CipherState` instances are spawned (initiator $\to$ responder and responder $\to$ initiator), with incrementing 64-bit nonces.
* **Message Padding:** To prevent traffic-analysis size leakage, cleartext inside `noiseEncrypted` packets is padded via PKCS#7 to the nearest bucket size: $\{256, 512, 1024, 2048\}$ bytes.

### 5.3 Mesh Engine & Controlled Flooding

* **Seen Cache (LRU):**
  - Key: `SHA256(senderID + timestamp + type + payload_prefix)`.
  - Max size: 1,000 entries; TTL: 300 seconds.
  - Action on hit: Drop silently. If a relay timer is queued for this packet, cancel it immediately.
* **Relay Scheduler:**
  - Jitter: $T_{\text{delay}} = \text{random}(10\text{ ms}, 220\text{ ms})$.
  - Ingress link exclusion: Never send to `excludePeerAddress`.
  - Fanout: If degree $\ge 6$, select $K = \lceil \log_2(\text{degree}) \rceil$ neighbors using packet hash as random seed. Otherwise, full fanout.
  - Decrement TTL: `packet.ttl = packet.ttl - 1`. If `packet.ttl <= 0`, drop packet.

### 5.4 Fragmentation & Reassembly Engine

* BLE characteristic MTU after ATT overhead is typically $512 - 3 = 509$ bytes. BitChat standard fragment payload size is $\approx 469$ bytes.
* Packet larger than MTU is split:
  - Header: Fragment ID (8 bytes), Fragment Index (2 bytes, big-endian), Total Fragments (2 bytes, big-endian).
  - Body: Chunk of packet bytes.
* The receiver keeps an in-memory reassembly buffer with an active limit of 128 assemblies and a 30-second sliding timeout.

### 5.5 Ephemeral Timeline & Panic Wipe Subsystem

* **Volatile Memory:** Public and private chat messages are stored in an in-memory ring buffer (e.g. max 500 messages per channel). No SQLite / Hive database is used for message history!
* **Panic Wipe Execution:**
  1. Overwrite identity key pairs in secure storage with zeros before deleting keys.
  2. Clear all in-memory Noise sessions, symmetric keys, and caches.
  3. Purge all pending courier envelopes and outbox files from disk.
  4. Reset UI to fresh onboarding screen.
  5. Trigger: Available via `/wipe` or `/panic` IRC command, or a customizable triple-tap / shake gesture.

### 5.6 IRC-Style Command Interface

The user interface follows a clean, hacker-friendly IRC console paradigm:
* `/msg <nick|peerID> <text>`: Start an encrypted direct message session.
* `/who`: List all online mesh and geohash peers with signal strengths.
* `/join <#channel>`: Switch channel (e.g. `#mesh` or `#9q8yy`).
* `/slap <nick>`: Fun IRC homage (`* Alice slaps Bob around a bit with a large trout *`).
* `/ping <peerID>`: Send a directed mesh ping and measure round-trip latency.
* `/clear`: Clear the active terminal buffer.
* `/wipe` or `/panic`: Instant, unconfirmed emergency data wipe.
* `/help`: Display available commands and syntax.

---

## 6. Implementation Roadmap

### Phase 1: Core Dart Foundation & Binary Wire Codec
* [x] Reverse-engineer protocol specs & extract binary constants.
* [ ] Implement `BinaryReader` and `BinaryWriter` (network byte order, big-endian).
* [ ] Implement `BitchatPacket` data model with v1/v2 header support.
* [ ] Implement TLV encoder/decoder for `AnnouncementPacket`.
* [ ] Implement `FragmentCodec` and `CompressionUtil` (zlib).
* [ ] Unit test packet encoding/decoding against test vectors.

### Phase 2: Cryptographic Engine & Identity Subsystem
* [ ] Implement Ed25519 identity generation, verification, and packet signing.
* [ ] Implement Curve25519 (X25519) key agreement.
* [ ] Implement Noise Protocol XX handshake engine (`Noise_XX_25519_ChaChaPoly_SHA256`).
* [ ] Implement symmetric ChaCha20-Poly1305 encryption/decryption with PKCS#7 padding.
* [ ] Unit test cryptographic handshakes and message exchange.

### Phase 3: Mesh Engine & Headless Simulation
* [ ] Implement `MeshEngine` with deduplication LRU cache and jitter scheduler.
* [ ] Implement `FragmentationEngine` with timeout reassembly buffer.
* [ ] Implement `SimulatedLinkLayer` (in-memory virtual radio).
* [ ] Construct a multi-node simulation test (e.g. Node A $\to$ Node B $\to$ Node C) verifying multi-hop packet routing and loop suppression.

### Phase 4: Native BLE Dual-Role Radio Layer
* [ ] **iOS:** Implement `BLECentralController` & `BLEPeripheralController` in Swift.
* [ ] **iOS:** Configure background BLE execution modes and state restoration.
* [ ] **Android:** Implement `BleAdvertiserManager`, `BleGattServerManager`, `BleScannerManager`, and `BleGattClientManager` in Kotlin.
* [ ] **Bridge:** Implement Flutter MethodChannel & EventChannel bindings for `LinkLayerPort`.
* [ ] Physical device smoke test: Verify two mobile phones establish a BLE link and exchange raw packets.

### Phase 5: Nostr Dual-Transport & Location Channels
* [ ] Implement `NostrRelayAdapter` over WebSockets (`web_socket_channel`).
* [ ] Implement Geohash location calculator (`geolocator` -> Geohash string).
* [ ] Implement `MessageRouter` to arbitrate between BLE Mesh and Nostr fallback.
* [ ] Implement BitChat encrypted envelope packing for Nostr events.

### Phase 6: Flutter Presentation Layer (Terminal/IRC UI)
* [ ] Implement Riverpod / BLoC state management (`TimelineState`, `PeerState`, `ChannelState`).
* [ ] Implement retro Terminal/IRC UI theme (monospace typography, high-contrast matrix green or amber palette).
* [ ] Implement terminal input bar with `/` command and `@peer` tab-completion.
* [ ] Implement Peer Radar screen with RSSI bars and verification badges.
* [ ] Implement Geohash location channel browser.

### Phase 7: Store-and-Forward Couriers, Panic Wipe & Field Polish
* [ ] Implement spray-and-wait courier storage and delivery engine.
* [ ] Implement out-of-band QR code identity verification flow.
* [ ] Implement Emergency Panic Wipe (zeroization + memory flush + app reset).
* [ ] End-to-end field testing in real-world offline environments.

---

## 7. Key Engineering Risks & Mitigations

| Risk | Impact | Architectural Mitigation |
|---|---|---|
| **iOS Background BLE Limits** | iOS throttles background scanning and terminates non-compliant peripherals. | Use CoreBluetooth State Restoration (`CBCentralManagerOptionRestoreIdentifierKey`); limit scanning frequency in background; leverage Nostr push notifications when backgrounded. |
| **Android BLE Stack Fragmentation** | Many Android chipsets have subtle GATT server bugs, connection limit quirks, and MTU negotiation issues. | Strict connection limits (cap at 6 concurrent links); conservative initial MTU (23 bytes default, negotiate up to 512); dedicated Kotlin radio coordinator managing serial GATT operations. |
| **Battery Drain from Active Scanning** | Continuous BLE radio usage rapidly depletes battery. | Adaptive duty cycling: scan actively for 4s during peer discovery, back off to 15–30s interval once connected; RSSI filtering to reject weak, distant noise. |
| **Memory Exhaustion from Large Files** | Flooding large media packets can crash memory-constrained devices. | Cap fragment assembly to 128 concurrent items and 1 MB max size; reject oversized incoming files at protocol level; use streaming file chunking. |

---

## 8. Summary

By decoupling the physical radio through a clean **Link Layer Port** and building the **BitChat Mesh Engine in pure, testable Dart**, this architecture guarantees 100% protocol fidelity with the upstream iOS/macOS BitChat implementation while giving Flutter unmatched testability, cross-platform maintainability, and top-tier cryptographic privacy.
