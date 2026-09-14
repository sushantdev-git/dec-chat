# DecChat: Decentralized Peer-to-Peer Mesh & Nostr Messenger

> A censorship-resistant, zero-infrastructure, end-to-end encrypted mobile chat application built with **Flutter**, powered by the **BitChat** mesh protocol and **Nostr** internet fallback.

[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](http://unlicense.org/)
[![Protocol: BitChat v2.0](https://img.shields.io/badge/protocol-BitChat%20v2.0-orange)](https://github.com/permissionlesstech/bitchat)
[![Architecture: Clean%20%2F%20Hexagonal](https://img.shields.io/badge/architecture-Hexagonal%20Ports%20%26%20Adapters-green)](BITCHAT_FLUTTER_ARCHITECTURE.md)
[![State: Riverpod](https://img.shields.io/badge/state-Riverpod-blue)](https://riverpod.dev)
[![UI: Signal%20Design%20Pattern](https://img.shields.io/badge/UI-Signal%20Design%20Pattern-brightgreen)](https://signal.org)

---

## 🌟 Vision & Key Capabilities

- **Zero Accounts & Zero Phone Numbers:** Cryptographic key pairs serve as the sole user identity. No servers, registration, or metadata silos.
- **Dual Transport Architecture:**
  - **Offline BLE Mesh Network:** Direct peer-to-peer and multi-hop mesh communication over Bluetooth Low Energy when disconnected from the internet.
  - **Nostr Relay Fallback:** Bridges separated meshes and reaches remote mutual favorites across the global internet via Nostr WebSocket relays.
- **Signal UI Design Pattern:** Clean, intuitive, modern messaging interface inspired by Signal (conversation threads, encrypted chat bubbles, peer safety numbers, QR verification), coupled with BitChat power commands (`/msg`, `/who`, `/slap`, `/ping`, `/join`, `/clear`, `/panic`).
- **End-to-End Encryption with Forward Secrecy:** Private chats are secured using the **Noise Protocol Framework (`Noise_XX_25519_ChaChaPoly_SHA256`)**.
- **Controlled Flooding Mesh Routing:** Multi-hop message delivery capped by degree-based TTL clamping ($7 \to 5$), 1000-entry LRU deduplication, randomized relay jitter ($10\text{--}220\text{ ms}$), split-horizon filtering, and degree-adaptive fanout.
- **Volatile Ephemeral Storage & Instant Panic Wipe:** Messages live in volatile memory only. An emergency wipe instantly zeroizes private keys and wipes caches without confirmation.

---

## 🏛 Architecture Overview

Detailed architectural design and protocol reverse-engineering are documented in:
👉 **[BITCHAT_FLUTTER_ARCHITECTURE.md](BITCHAT_FLUTTER_ARCHITECTURE.md)**

### Zero-Overhaul Extensibility & Plugin Architecture
To prevent the architectural stalling seen in monolithic mesh clients, DecChat employs an **Open-Closed Plugin Pattern**:
- **Pure Infrastructure Mesh Engine:** The core `MeshEngine` handles only low-level networking (flooding, deduplication LRU, TTL clamping, randomized jitter, and link relaying). It has **zero knowledge** of specific message types or features.
- **Protocol Feature Registry:** High-level features (Public Chat, Noise E2EE, Couriers, Files, Voice, Groups, Bulletin Boards) are self-contained `ProtocolFeatureModule` plugins that register dynamically. New features are added without modifying the core mesh engine.
- **Tolerant Wire Codec:** Unknown future packet types (`MessageType.unknown`) are forwarded across the mesh safely without crashing or dropping packets.
- **Pluggable Multi-Transport Pipeline:** Abstract `TransportPort` allows seamlessly adding new transports (e.g. Local LAN Wi-Fi Direct, LoRa radios, WebRTC) alongside BLE Mesh and Nostr.
- **Configurable Ephemerality:** Clean repository port supporting both default volatile in-memory storage (zero disk trace) and optional encrypted local persistence.

```
┌────────────────────────────────────────────────────────┐
│               FLUTTER PRESENTATION (Signal UI)         │
│     Chat Screen, Peer Directory, QR Verification       │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│                 APPLICATION LAYER (Riverpod)           │
│        TimelineState, PeerState, ChannelState          │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│          DOMAIN CORE: MODULAR PLUGIN ENGINE            │
│  ┌──────────────────────────────────────────────────┐  │
│  │ ProtocolFeatureRegistry (Chat, Noise, Couriers)  │  │
│  └────────────────────────▲─────────────────────────┘  │
│                           │ Dispatches Inbound Payload │
│  ┌────────────────────────┴─────────────────────────┐  │
│  │ MeshEngine (Flooding, Dedup, Jitter, TTL Clamp)  │  │
│  └────────────────────────▲─────────────────────────┘  │
│                           │                            │
│  ┌────────────────────────┴─────────────────────────┐  │
│  │ MultiTransportRouter (BLE Mesh -> LAN -> Nostr)  │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│                 PORTS & ADAPTERS LAYER                 │
│  TransportPort   CryptoPort   StoragePort   PowerPort  │
└────────────┬───────────────────────┬───────────────────┘
             │                       │
     ┌───────┴───────┐       ┌───────┴───────┐
     ▼               ▼       ▼               ▼
[Native BLE]  [Simulated] [Dart Crypto] [Nostr WS]
(iOS/Android)  (Headless)  (X25519/Ed)   (Relays)
```

---

## 🛠 Engineering Methodology: Build-and-Test Incrementalism

We adhere strictly to an **incremental, verifiable engineering pattern**:
1. **Piece-by-Piece Construction:** We build one self-contained, high-cohesion module at a time.
2. **Immediate Verification:** Every module is accompanied by comprehensive automated tests (unit, property, or simulation).
3. **Commit & Push:** Once verified, changes are committed and pushed incrementally to the upstream repository.

### Delivery Phases

  - [x] **Phase 1: Pure Dart Wire Protocol & Codecs** *(Completed & Merged)*
    - `BinaryReader` & `BinaryWriter`: Big-endian integer and byte slice read/write with bounds checking.
    - `MessageType`: Wire packet enumeration matching BitChat v2.0 with forward-compatible `unknown(rawValue)` fallback.
    - `MessagePadding`: PKCS#7 message padding toward `{256, 512, 1024, 2048}`-byte buckets.
    - `BitchatPacket`: Immutable packet model (v1 14-byte & v2 16-byte headers, flag bitmasks, `copyForSigning()` invariant).
    - `BinaryProtocolCodec`: Full wire serialization/deserialization engine with automatic zlib payload compression.
    - `AnnouncementCodec`: TLV presence encoder/decoder with resilient unknown tag skipping.
    - `FragmentCodec`: Large packet MTU slicing into 469-byte fragments and reassembly.
    - **Verification:** 15/15 unit tests passing, 0 analyzer issues.
  - [x] **Phase 2: Cryptographic Engine & Identity Subsystem** *(Completed & Merged)*
    - `IdentityKeyPair`: Dual Curve25519 (X25519) + Ed25519 keys, persistent 8-byte peer ID (`SHA-256(noisePublicKey)[0..8]`), and symmetric Signal-style 60-digit safety numbers.
    - `CryptoPort` & `CryptographyAdapter`: Abstract port & concrete adapter using `package:cryptography` for unforgeable canonical packet signing (`TTL=0`) and tamper-evident verification.
    - `NoiseCipherState`: ChaCha20-Poly1305 AEAD with BitChat 12-byte nonce layout, extracted 4-byte big-endian wire nonces, and 1024-bit sliding-window replay protection.
    - `NoiseSymmetricState`: Complete Noise Protocol framework SymmetricState abstraction (HKDF-SHA256, `mixHash`, `mixKey`, `mixKeyAndHash`, `encryptAndHash`, `decryptAndHash`, `split`).
    - `NoiseHandshakeState`: 3-step `Noise_XX_25519_ChaChaPoly_SHA256` mutual authentication state machine (`-> e`, `<- e, ee, s, es`, `-> s, se`) with forward secrecy and static key encryption.
    - `NoiseSessionManager` & `NoiseSession`: State management for peer E2EE sessions, in-flight handshake timeout management, automatic PKCS#7 message padding, and instant panic session wipe.
    - `NoisePayloadType`: Forward-compatible enumeration for inner decrypted 0x11 payloads (`privateMessage`, `readReceipt`, `groupInvite`, `verifyChallenge`, etc.).
    - **Verification:** 28/28 unit tests passing across protocol and crypto suites, 0 analyzer issues.
  - [x] **Phase 3: Mesh Routing Engine & Multi-Node Simulation** *(Completed & Merged)*
    - `SeenPacketCache`: High-performance 1,000-entry LRU cache with 5-minute TTL and immediate duplicate suppression.
    - `ProtocolFeatureRegistry` & `ProtocolFeatureModule`: Dynamic decoupled feature registration preserving the Open-Closed Principle (zero feature knowledge in core mesh).
    - `MeshEngine`: BitChat controlled flooding with adaptive TTL clamping ($7 \to 5$ when peer density $\ge 6$), randomized relay jitter ($10\text{--}220\text{ ms}$), split-horizon filtering, and degree-based fanout subsetting.
    - `TransportPort` & `TransportMedium`: Transport abstraction supporting BLE, Nostr, Wi-Fi LAN, and simulated virtual radio links.
    - `SimulatedMeshNetwork` & `SimulatedLinkAdapter`: Headless multi-node virtual radio environment with configurable propagation latency, packet loss, and topology builders (line, full mesh, ring).
    - **Verification:** 38/38 unit tests passing across all suites including 10-node linear chain and circular ring deduplication simulations; 0 analyzer issues.
  - [x] **Phase 4: Native BLE Dual-Role Radio Bridge** *(Completed & Merged)*
    - `BleConstants`: BitChat Service UUID (`0xFDC7`), Characteristic UUID (`0x2A06`), target MTU 512, platform channel identifiers.
    - `PowerPolicyPort` & `BlePowerMode`: Adaptive duty cycle modes: `active` (100% continuous), `balanced` (15s on / 15s off), and `background` (5s on / 55s off).
    - `NativeBleLinkAdapter`: Concrete `TransportPort` bridging Dart mesh routing with native dual-role radio controllers via Flutter MethodChannel and EventChannel.
    - **iOS CoreBluetooth Dual-Role (`ios/Runner/BLE/`):**
      - `BLEPeripheralController`: `CBPeripheralManager` & GATT Server advertising BitChat service and hosting packet characteristic.
      - `BLECentralController`: `CBCentralManager` & Scanner discovering BitChat peers, subscribing to notifications, and transmitting packets.
      - `BLERadioCoordinator`: Dual-role coordinator managing both Central and Peripheral links with adaptive duty-cycling.
      - `BlePlatformChannel`: Platform channel message and event stream handlers.
      - Background modes: `bluetooth-central`, `bluetooth-peripheral`.
    - **Android BLE Dual-Role (`android/app/src/main/kotlin/com/bitchat/mesh/dec_chat/ble/`):**
      - `BleAdvertiserManager`: `BluetoothLeAdvertiser` with low-latency settings.
      - `BleGattServerManager`: `BluetoothGattServer` handling incoming writes and client subscriptions.
      - `BleScannerManager`: `BluetoothLeScanner` with service UUID scan filters.
      - `BleGattClientManager`: Client connections, MTU 512 negotiation, notifications, and packet transmission.
      - `BleRadioCoordinator`: Dual-role coordinator and duty-cycle scheduling.
      - `BlePlatformChannel`: MethodChannel and EventChannel bridge.
      - Permissions: `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`.
    - **Verification:** 46/46 unit tests passing across all suites including platform channel bridge test suite; 0 analyzer issues.
  - [x] **Phase 5: Nostr Dual-Transport & Location Channels** *(Completed)*
    - `Geohash`: Pure Dart Morton Z-order curve spatial indexing encoder, decoder, 8-neighbor adjacency calculator, and location channel validation (`#9q8yy`).
    - `NostrKind`: Protocol event enumeration covering NIP-01, NIP-04, NIP-28, and custom ephemeral BitChat mesh (20000) & geohash (20001) carriers.
    - `NostrEvent`: NIP-01 data model, canonical serialization `[0, pubkey, created_at, kind, tags, content]`, SHA-256 event ID verification, and transparent BitChat packet wrapping/unwrapping.
    - `NostrRelayAdapter`: Concrete `TransportPort` managing multi-relay WebSocket connections, automatic reconnection with backoff, NIP-01 subscription framing (`REQ`, `CLOSE`), echo suppression, and geohash channel subscriptions.
    - `LocationChannelService`: Spatial channel manager resolving GPS coordinates to geohash channels and computing 9-cell boundary neighborhood coverage.
    - `MessageRouter`: Dual-transport coordinator implementing `TransportPort`, providing policy switching (`adaptive`, `bleOnly`, `nostrOnly`, `dual`), cross-medium deduplication via `SeenPacketCache`, and proximity-directed BLE-to-Nostr fallback.
    - **Verification:** 78/78 unit tests passing across all suites; 0 analyzer issues.
  - [x] **Phase 6: Riverpod Application State & Signal UI** *(Completed)*
    - `ChatMessage` & `PeerModel`: Immutable presentation models with transport badges, delivery checkmarks, and symmetric 60-digit safety numbers.
    - `ChatCommand`: Command parser supporting BitChat power commands (`/msg`, `/who`, `/slap`, `/ping`, `/join`, `/clear`, `/panic`).
    - **Riverpod Application State:**
      - `IdentityNotifier`: Manages local key pairs, nickname, and peer ID.
      - `PeersNotifier`: Tracks active/discovered peers, RSSI signal indicators, hop count, and safety verification status.
      - `ChannelsNotifier`: Manages joined channels (`#mesh`, `#general`, `#9q8yy`).
      - `TimelineNotifier`: Ephemeral in-memory timeline buffer with packet dispatching and feature module routing.
      - `PanicController`: Instant zeroization and session wipe.
    - **Signal UI Design Pattern (`lib/presentation/`):**
      - `SignalTheme`: Clean dark aesthetic (`#121212` background, `#2C6BED` Signal Blue accent).
      - `TransportBadge`: Dynamic indicator for BLE Mesh (Blue Bluetooth radio) vs Nostr (Purple Globe).
      - `MessageBubble`: Chat bubble with bubble tail, encryption lock badge, and delivery receipts.
      - `SlashCommandPopup`: Autocompleting command overlay.
      - `SafetyNumberCard`: Symmetric 60-digit safety number comparison layout (12 blocks of 5 digits) with QR verification.
      - `ConversationListScreen`, `ChatScreen`, `PeerDirectoryScreen`, `SafetyVerificationDialog`.
    - **Verification:** 109/109 unit and widget tests passing across all suites; 0 analyzer issues.
  - [x] **Phase 7: Store-and-Forward Couriers, Panic Wipe & Field Polish** *(Completed)*
    - `CourierEnvelope`: Compact binary wire serialization for sealed DTN envelopes, hop budgeting, and expiration checking.
    - `CourierService`: Store-and-forward Delay-Tolerant Networking (DTN) outbox with spray-and-wait routing, data-muling across partitioned networks, direct encounter delivery, and capacity eviction.
    - `CourierModule`: Protocol feature module integrating `MessageType.courierEnvelope` (`0x04`) into `ProtocolFeatureRegistry` and `MeshEngine`.
    - `PanicZeroizationService`: In-place memory scrubbing (`scrubBytes`), courier outbox wipe, Noise session cipher state destruction, deduplication cache clearing, and radio shutdown.
    - `BitchatCoordinator`: Master application coordinator tying together identity, Noise encryption, controlled mesh flooding, courier DTN, and panic zeroization.
    - `PanicController` Integration: Complete tie-in of the presentation layer's `/panic` command to the low-level zeroization pipeline.
    - `End-to-End Integration Suite`: Verification of direct 1-hop delivery, multi-node mobile data muling across network partitions, and panic zeroization.
    - **Verification:** 123/123 unit and integration tests passing across all suites; 0 analyzer issues.
  - [x] **Phase 8: Native macOS Desktop BLE, Live Peer Discovery & Dual-Transport Hardening** *(Completed)*
    - **Live Presence Discovery & Protocol Wiring:**
      - `AnnouncementModule`: Protocol module capturing `MessageType.announce` packets and registering peers with nicknames, cryptographic public keys, and Signal-style safety numbers into `peersProvider`.
      - `ChatMessageModule`: Protocol module routing `MessageType.message` packets into `timelineProvider` for real-time conversation updates.
      - Periodic Announcement Timer: Added a 4-second recurring announcement routine in `BitchatCoordinator` to actively advertise node presence across BLE and Nostr transports.
      - Eager Coordinator Activation: Bound `bitchatCoordinatorProvider` directly into `ConversationListScreen` on app launch.
    - **Native macOS CoreBluetooth Integration (`macos/Runner/MainFlutterWindow.swift`):**
      - Implemented native `BLEPeripheralController` (advertising + GATT server) and `BLECentralController` (scanning + GATT client) in Swift for native macOS desktop builds.
      - Fixed radio initialization lifecycle bug where scanning/advertising guards returned early before Bluetooth reached `.poweredOn` state; added `shouldBeAdvertising` and `shouldBeScanning` state management to automatically trigger radio operation upon initialization.
      - Updated macOS entitlements (`DebugProfile.entitlements` and `Release.entitlements`) with `com.apple.security.device.bluetooth` and `com.apple.security.network.client`.
    - **Android BLE Scanner & Internet Permissions:**
      - Added `INTERNET` and `ACCESS_NETWORK_STATE` to `AndroidManifest.xml` for seamless WebSocket connectivity.
      - Enhanced `BleScannerManager.kt` with dual filter matching (`SERVICE_UUID` and `filterByName("DecChat")`) with software fallback in `onScanResult` for maximum cross-platform compatibility with Apple CoreBluetooth advertisements.
    - **Nostr Relay Resilience & Unique Public Keys:**
      - Replaced dead relays with confirmed active Nostr WebSocket relays (`wss://relay.primal.net`, `wss://offchain.pub`, `wss://nos.lol`).
      - Derived unique 64-character lowercase hex public keys from node Ed25519 signing keys so peer packets are never dropped as self-echoes.
      - Updated `MessageRouter` with non-blocking error guards (`.catchError((_) {})`) ensuring BLE and Nostr operate redundantly.
    - **Field Verification:**
      - Verified bidirectional peer discovery and live end-to-end encrypted chat between a native **macOS desktop app** on Apple Silicon Mac mini and a **Samsung Galaxy S23** running the Android release APK.
    - **Verification:** 130/130 unit and integration tests passing across all suites (`test/application/peer_discovery_and_modules_test.dart`); 0 analyzer issues.
  - [x] **Phase 9: Persistent Cryptographic Identity, Thread Unification & Zero-Trace Local Storage** *(Completed)*
    - **Deterministic Identity Recovery (`IdentityKeyPair`):**
      - Implemented serialization and deserialization (`toJson` and `fromJson`) for `IdentityKeyPair` via 32-byte private key seed extraction (`extractPrivateKeyBytes` and `newKeyPairFromSeed`).
      - Guarantees 100% deterministic restoration of dual X25519 and Ed25519 key pairs, retaining identical 8-byte `peerId`, fingerprints, and Signal-style safety numbers across app restarts.
    - **Zero-Trace Local Storage Subsystem (`LocalStorageService`):**
      - Created decoupled persistent storage engine managing `identity.json`, `peers.json`, and `conversations.json` in sandboxed storage using `path_provider`.
      - Write-through memory cache ensures instant UI read latencies and non-blocking asynchronous disk flushing.
      - Integrated panic scrub: `wipeAll()` physically overwrites file disk buffers with zero bytes before unlinking inodes, strictly maintaining BitChat's zero-trace emergency wipe guarantee.
      - Transparent in-memory fallback for headless CI and test environments.
    - **State Management & Conversation Thread Unification:**
      - `IdentityNotifier`: Restores persistent identity on startup, keeping the local node's `peerId` constant.
      - `PeersNotifier`: Loads discovered contacts on boot; deduplicates incoming announcements by both `peerId` and `noisePublicKey` to prevent duplicate peer entries.
      - `TimelineNotifier`: Restores conversation histories on boot; normalizes channel/peer keys (stripping `@` prefixes and lowercase) so that messages across app restarts are routed seamlessly into the same unified conversation thread for the same physical peer.
      - `PanicController`: Orchestrates disk zeroization alongside in-memory timeline purging, radio shutdown, and ephemeral key regeneration.
    - **Field Verification:**
      - Tested on Samsung Galaxy S23: verified persistent peer ID (`c0e64ded`) across complete process terminations (`am force-stop`), retained conversation history under Direct Messages, and unified subsequent messages consecutively in the exact same thread.
    - **Verification:** 140/140 unit and integration tests passing across all suites (`test/infrastructure/local_storage_service_test.dart`, `test/presentation/persistent_identity_and_threads_test.dart`, `test/domain/crypto_engine_test.dart`); 0 analyzer issues.
  
---

## 📦 Repository & Local Environment

- **Git Remote:** `https://github.com/sushantdev-git/dec-chat.git`
- **Default Branch:** `main`
- **Active Feature Branch:** `feat/persistent-identity-thread-unification`
- **Author:** Sushant Mishra (`sushantkumar6700@gmail.com`)

### Environment & Toolchain
- **Flutter SDK:** `3.47.4 • channel stable` (Installed at `~/development/flutter`)
- **Dart SDK:** `3.13.3 • macos_arm64`
- **Run Tests:**
  ```bash
  flutter test
  ```
- **Analyze Code:**
  ```bash
  flutter analyze
  ```

---

## 📄 License

This project is dedicated to the public domain under the [Unlicense](http://unlicense.org/).
