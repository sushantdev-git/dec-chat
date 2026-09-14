# BitChat Mobile: Architecture Blueprint & Technical Specification (Flutter)

**Document Version:** 1.1.0 (Extensibility & Modular Hardening)  
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

---

## 2. Zero-Overhaul Extensibility Architecture

A primary architectural failure mode in peer-to-peer networking is creating tight coupling between the mesh radio, packet routing, and application features (which led upstream BitChat v2 to stall in an 8,000-line god-object).

To ensure that **any future protocol extension (e.g. voice streaming, group messaging, bulletin boards, Cashu ecash payments, or alternate transports like LoRa and LAN Wi-Fi Direct) can be dropped in without refactoring core routing or presentation**, this architecture enforces 7 modularity principles:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       FLUTTER PRESENTATION (Signal UI)                      │
│   Unified Conversation View  ·  Peer Directory  ·  Safety Numbers & Badges  │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                    APPLICATION & STATE LAYER (Riverpod)                     │
│     AsyncNotifiers  ·  State Providers  ·  PanicWipeCoordinator             │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                     DOMAIN CORE: MODULAR PLUGIN ENGINE                      │
│                                                                             │
│   ┌──────────────────────────────────────────────────────────────────────┐  │
│   │                 ProtocolFeatureRegistry (Open-Closed)                │  │
│   │  [PublicChatModule] [NoiseModule] [CourierModule] [FileTransfer]     │  │
│   │  [VoiceModule]      [GroupModule] [BoardModule]   [FutureModules...] │  │
│   └──────────────────────────────────▲───────────────────────────────────┘  │
│                                      │ Dispatches Inbound Payload           │
│   ┌──────────────────────────────────┴───────────────────────────────────┐  │
│   │                   MeshEngine (Pure Infrastructure)                   │  │
│   │  - Tolerant Decoder (Relays Unknown Packet Types Safely)             │  │
│   │  - Controlled Flooding (TTL Clamping 7->5, Deduplication LRU 1000)   │  │
│   │  - Randomized Jitter Scheduler (10-220ms) · Fanout Subsetting        │  │
│   │  - Split-Horizon Link Rule · Outbox State Machine                    │  │
│   └──────────────────────────────────▲───────────────────────────────────┘  │
│                                      │                                      │
│   ┌──────────────────────────────────┴───────────────────────────────────┐  │
│   │            MultiTransportRouter (Prioritized Arbitration)            │  │
│   │    BLE Mesh (Offline) ──▶ Local LAN (Wi-Fi) ──▶ Nostr Relay (Web)    │  │
│   └──────────────────────────────────▲───────────────────────────────────┘  │
└──────────────────────────────────────┼──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────────────┐
│                            PORTS & ADAPTERS LAYER                           │
│  TransportPort   CryptoPort   ConversationRepoPort   PowerPolicyPort        │
└─────────┬──────────────┬───────────────┬─────────────────────┬──────────────┘
          │              │               │                     │
          ▼              ▼               ▼                     ▼
   [Native BLE]     [Dart Crypto]  [Volatile RAM /        [Adaptive Duty]
   [Nostr WS]       (X25519/Ed)    Encrypted Cache]       (100% vs 25% sleep)
   [Future: LoRa]
```

### 2.1 The Protocol Feature Registry (Open-Closed Principle)
The `MeshEngine` is **pure networking infrastructure**. It knows how to encode headers, decrement TTL, deduplicate packets, and relay bytes over links. It has **zero knowledge** of private chat, files, or audio.

Whenever a packet is addressed to our local peer (or is a public broadcast), `MeshEngine` passes it to `ProtocolFeatureRegistry`:

```dart
abstract class ProtocolFeatureModule {
  String get moduleId;
  Set<MessageType> get handledMessageTypes;
  Future<void> initialize();
  Future<void> handleInbound(BitchatPacket packet, InboundContext context);
  Future<void> dispose();
}
```

*Adding a new feature later (e.g. push-to-talk voice, bulletin board, or Cashu ecash tokens) requires creating a single class implementing `ProtocolFeatureModule` and registering it at startup. **Zero edits to the mesh engine or routing logic.***

### 2.2 Tolerant Reader & Unknown Packet Relaying
If a nearby peer is running BitChat v2.5 with a new packet type (`0x30`), older nodes must **not crash, drop, or invalidate** the packet:
- `MessageType.unknown(int rawValue)` safely captures unallocated types.
- Relays inspect only the outer 14/16-byte binary header.
- The packet is deduplicated, TTL-decremented, jittered, and relayed across the mesh to its destination.
- TLV parsers ignore unknown tags gracefully without parse exceptions.

### 2.3 Pluggable Multi-Transport Pipeline
Instead of hardcoding binary `isBle` vs `isNostr` flags, the routing layer interacts with a unified `TransportPort`:

```dart
enum TransportMedium { bleMesh, localLan, nostrRelay, lora, custom }

abstract class TransportPort {
  TransportMedium get medium;
  Stream<TransportEvent> get events;
  Future<void> sendPacket(BitchatPacket packet, {String? targetPeerAddress});
  bool get isAvailable;
  int get priorityOrder; // 0 = Direct BLE, 1 = Local LAN, 2 = Nostr Internet
}
```
If we choose to add local Wi-Fi Direct, Multicast LAN UDP, or LoRa radio support in the future, we simply create a new adapter implementing `TransportPort` and register it in the router.

### 2.4 Configurable Storage & Ephemerality Strategy
- **Default Policy:** `VolatileMemoryConversationRepository` — Zero disk footprint. All message history lives in RAM ring buffers and vanishes on app kill or panic wipe.
- **Optional Policy:** `EncryptedDiskConversationRepository` — AES-GCM encrypted local store (key in Secure Enclave), allowing users who prefer message retention across restarts to opt-in, while maintaining instant cryptographic zeroization on panic.

### 2.5 Adaptive Power & Duty-Cycle Policies
BLE scanning causes rapid battery depletion if run at 100% duty cycle. The system includes an explicit `PowerPolicyCoordinator`:
- **Active Mode (App in foreground):** 100% scan, continuous advertising.
- **Balanced Mode (App idle in foreground):** Scan 15s, idle 15s.
- **Background Mode (App in background):** CoreBluetooth state restoration / Android background scan interval (scan 5s, idle 55s).

---

## 3. BitChat Protocol Wire Specifications (Under the Hood)

### 3.1 Wire Format & Binary Protocol

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

### 3.2 Identity & Cryptographic Primitives

Each client generates two primary asymmetric key pairs:
1. **Curve25519 Key Pair:** Used for Noise Protocol Diffie-Hellman key exchange.
2. **Ed25519 Key Pair:** Used for signing public announcements, packets, and identity binding.

* **Peer ID:** The first 8 bytes of `SHA-256(Curve25519_Static_Public_Key)`. This 8-byte identifier is used in all mesh packet headers.
* **Signing Envelope:** Signatures are computed over the packet representation with `TTL = 0`, stripping the mutable TTL byte so relays can decrement TTL in transit without breaking the cryptographic signature.

### 3.3 Mesh Routing & Controlled Flooding Algorithm

To prevent broadcast storms while ensuring delivery across lossy radio links:
1. **TTL Clamping:** Packets originate with `TTL = 7`. Relays adaptively clamp TTL:
   - High density ($\ge 6$ active links): Cap broadcast TTL at $5$.
   - Low density ($\le 2$ active links): Relay at incoming TTL $- 1$.
2. **Deduplication LRU Seen-Set:** A cache of 1,000 recent packet identifiers with a 5-minute expiry. An incoming duplicate instantly cancels any pending relay.
3. **Randomized Relay Jitter:** Nodes delay relaying by a pseudo-random interval between $10\text{ ms}$ and $220\text{ ms}$ (wider window in dense topologies). This prevents simultaneous packet collisions over the 2.4 GHz ISM band and lets duplicate suppression take effect.
4. **Degree-Based Fanout Subsetting:** Broadcast traffic is forwarded to a deterministic, pseudo-random subset ($\approx \log_2(\text{degree})$) of connected peers, seeded by the packet ID.
5. **Split-Horizon Rule:** A packet is never relayed back out through the link on which it arrived.
6. **Directed Routing:** Packets with a target `recipientID` follow recorded source routes (derived from 1-hop neighbor lists in recent `announce` packets). If no route exists, they fall back to flooding with full fanout.

---

## 4. Flutter System Architecture & Directory Structure

```
dec_chat/
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
│   │   └── routes.dart                 # Signal-style navigation
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
│   │   │   ├── conversation.dart       # Polymorphic conversation (1:1, Channel, Mesh)
│   │   │   ├── message.dart            # Chat message entity
│   │   │   ├── peer.dart               # Peer identity & state
│   │   │   └── courier_envelope.dart   # Store-and-forward sealed payload
│   │   ├── enums/
│   │   │   ├── message_type.dart       # Extensible wire types + unknown fallback
│   │   │   ├── noise_payload_type.dart # Inner private types
│   │   │   └── transport_medium.dart   # BLE, Nostr, LAN, LoRa
│   │   ├── ports/
│   │   │   ├── transport_port.dart     # Unified transport abstraction
│   │   │   ├── crypto_port.dart        # Noise & signature interface
│   │   │   ├── conversation_repo_port.dart # Storage interface (RAM or Encrypted Disk)
│   │   │   └── power_policy_port.dart  # Adaptive duty-cycle interface
│   │   └── services/
│   │       ├── feature_registry.dart   # Pluggable feature modules
│   │       ├── mesh_engine.dart        # Controlled flooding, dedup, jitter
│   │       ├── fragmentation_engine.dart# Slicing & reassembly
│   │       ├── noise_session_manager.dart# Noise XX handshake & cipher states
│   │       ├── message_router.dart     # Multi-transport arbitration
│   │       ├── courier_service.dart    # Spray-and-wait outbox
│   │       └── irc_command_parser.dart # Slash command parser
│   ├── infrastructure/
│   │   ├── adapters/
│   │   │   ├── native_ble_link_adapter.dart # Platform channel bridge
│   │   │   ├── simulated_link_adapter.dart  # In-memory virtual mesh test radio
│   │   │   ├── nostr_relay_adapter.dart     # WebSocket Nostr client
│   │   │   ├── cryptography_adapter.dart    # X25519, Ed25519, ChaChaPoly
│   │   │   ├── volatile_conversation_repo.dart # Ephemeral RAM repository
│   │   │   └── geolocator_adapter.dart      # GPS to Geohash converter
│   │   ├── codecs/
│   │   │   ├── binary_protocol_codec.dart   # BitchatPacket <-> Uint8List
│   │   │   ├── announcement_codec.dart      # TLV Announcement encode/decode
│   │   │   └── fragment_codec.dart          # Fragment payload slicing
│   │   └── modules/
│   │       ├── public_chat_module.dart      # Handles MessageType.message
│   │       ├── noise_chat_module.dart       # Handles MessageType.noiseEncrypted
│   │       ├── courier_module.dart          # Handles MessageType.courierEnvelope
│   │       └── diagnostics_module.dart      # Handles MessageType.ping/pong
│   ├── presentation/
│   │   ├── state/
│   │   │   ├── conversation_providers.dart  # Riverpod conversation streams
│   │   │   ├── peer_providers.dart          # Discovered peer list & radar
│   │   │   └── panic_controller.dart        # Emergency wipe coordinator
│   │   ├── theme/
│   │   │   └── signal_theme.dart            # Clean, high-contrast Signal aesthetic
│   │   └── views/
│   │       ├── conversation_list_view.dart  # Signal-style thread list
│   │       ├── chat_screen.dart             # Message bubbles, lock badges, input
│   │       ├── peer_directory_screen.dart   # Nearby mesh peers, RSSI, safety numbers
│   │       ├── qr_verification_sheet.dart   # In-person safety number scanning
│   │       └── widgets/
│   │           ├── message_bubble.dart      # Encrypted bubble with delivery checks
│   │           ├── transport_badge.dart     # BLE Mesh vs Nostr indicator
│   │           └── slash_command_popup.dart # Command suggestions for /msg, /ping
│   └── main.dart
└── test/
    ├── domain/
    │   ├── binary_protocol_test.dart        # Packet serialization & unknown type tests
    │   ├── noise_protocol_test.dart         # Handshake & cipher vector tests
    │   ├── fragmentation_test.dart          # Large file chunking & reassembly
    │   └── mesh_simulation_test.dart        # 10-node virtual mesh relay test!
    └── fixtures/
```

---

## 5. Signal UI Design Pattern Specification

The UI adopts **Signal's world-class privacy-first interaction design**, while exposing BitChat's decentralized capabilities:

1. **Conversation List (Home):**
   - Clean list of active threads: Direct Chats, Location Channels (`#9q8yy`), and Global `#mesh`.
   - Visual transport badges: Blue Bluetooth icon for direct BLE mesh, purple Globe icon for Nostr fallback.
   - Safety Status: A verified checkmark next to peers who have completed in-person QR verification.
2. **Chat Screen:**
   - Message bubbles with delivery and read receipt status.
   - Top app bar displays peer safety status ("Lock icon: End-to-End Encrypted").
   - Disappearing messages timer icon if ephemerality mode is active.
   - Input composer supports normal text, plus autocompleting BitChat slash commands (`/msg`, `/who`, `/slap`, `/ping`, `/clear`, `/panic`).
3. **Peer Safety Numbers & QR Verification:**
   - Tapping on a peer displays their 60-digit cryptographic Safety Number (derived from Ed25519 & Noise public keys) and a QR code.
   - Scanning a peer's QR code in person marks them as "Cryptographically Verified".
4. **Emergency Panic Wipe:**
   - Discreet trigger (e.g. triple-tap on app header or `/panic` command) instantly executes zeroization without prompts.

---

## 6. Incremental Build-and-Test Delivery Checklist

- [ ] **Phase 1: Pure Dart Wire Protocol & Codecs**
  - [ ] BinaryReader & BinaryWriter (network byte order, big-endian)
  - [ ] MessageType with `unknown` fallback for future forward compatibility
  - [ ] BitchatPacket with v1/v2 header, flags, and `toBinaryDataForSigning()`
  - [ ] TLV AnnouncementCodec with resilient parser for unknown tags
  - [ ] FragmentCodec (slicing & reassembly headers)
  - [ ] Automated round-trip unit test suite
- [ ] **Phase 2: Cryptographic Engine & Noise XX**
  - [ ] Ed25519 signature generation and verification
  - [ ] Curve25519 (X25519) key agreement
  - [ ] Noise XX handshake state machine (`Noise_XX_25519_ChaChaPoly_SHA256`)
  - [ ] ChaCha20-Poly1305 AEAD cipher with PKCS#7 bucket padding (256, 512, 1024, 2048)
  - [ ] Automated cryptographic test vectors & session handshake tests
- [ ] **Phase 3: Mesh Engine & 10-Node Headless Simulation**
  - [ ] ProtocolFeatureRegistry and feature module interfaces
  - [ ] MeshEngine (deduplication LRU 1000, TTL clamping 7->5, jitter scheduler, split horizon)
  - [ ] Fragmentation reassembly buffer with 30s sliding timeout
  - [ ] SimulatedLinkLayer (in-memory virtual radio)
  - [ ] 10-node headless virtual mesh test (multi-hop propagation, loop suppression, packet drops)
- [ ] **Phase 4: Native BLE Dual-Role Radio Layer**
  - [ ] iOS Swift: Central Controller & Peripheral Controller (GATT Server + Advertiser)
  - [ ] iOS: Background BLE state restoration configuration
  - [ ] Android Kotlin: Advertiser, Scanner, GattServer, and GattClient
  - [ ] Flutter MethodChannel / EventChannel bridge implementation
  - [ ] Physical device smoke test
- [ ] **Phase 5: Nostr Dual-Transport & Location Channels**
  - [ ] WebSocket Nostr relay adapter
  - [ ] Geohash location calculator
  - [ ] Multi-transport arbitration router (Mesh BLE -> Nostr internet fallback)
- [ ] **Phase 6: Riverpod State & Signal UI**
  - [ ] Conversation, Peer, and Panic Riverpod AsyncNotifiers
  - [ ] Signal-style theme and conversation thread list
  - [ ] Chat screen with message bubbles, transport badges, and slash commands
  - [ ] Peer directory and in-person QR safety number verification
- [ ] **Phase 7: Store-and-Forward Couriers, Panic Wipe & Field Polish**
  - [ ] Spray-and-wait courier storage and delivery
  - [ ] Panic Wipe zeroization pipeline
  - [ ] Final real-world field verification
