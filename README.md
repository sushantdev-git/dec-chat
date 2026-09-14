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
  - [x] **Phase 3: Mesh Routing Engine & Multi-Node Simulation** *(Completed)*
    - `SeenPacketCache`: High-performance 1,000-entry LRU cache with 5-minute TTL and immediate duplicate suppression.
    - `ProtocolFeatureRegistry` & `ProtocolFeatureModule`: Dynamic decoupled feature registration preserving the Open-Closed Principle (zero feature knowledge in core mesh).
    - `MeshEngine`: BitChat controlled flooding with adaptive TTL clamping ($7 \to 5$ when peer density $\ge 6$), randomized relay jitter ($10\text{--}220\text{ ms}$), split-horizon filtering, and degree-based fanout subsetting.
    - `TransportPort` & `TransportMedium`: Transport abstraction supporting BLE, Nostr, Wi-Fi LAN, and simulated virtual radio links.
    - `SimulatedMeshNetwork` & `SimulatedLinkAdapter`: Headless multi-node virtual radio environment with configurable propagation latency, packet loss, and topology builders (line, full mesh, ring).
    - **Verification:** 38/38 unit tests passing across all suites including 10-node linear chain and circular ring deduplication simulations; 0 analyzer issues.
  - [ ] **Phase 4: Native BLE Dual-Role Radio Bridge** (Swift iOS CoreBluetooth + Kotlin Android BLE Advertiser/GattServer)
  - [ ] **Phase 5: Nostr Dual-Transport & Location Channels** (WebSocket relays, Geohash chat rooms)
  - [ ] **Phase 6: Riverpod Application State & Signal UI** (Conversation threads, peer directory, message bubbles, IRC slash commands)
  - [ ] **Phase 7: Store-and-Forward Couriers, Panic Wipe & Field Polish** (Spray-and-wait outbox, instant zeroization, QR safety verification)
  
---

## 📦 Repository & Local Environment

- **Git Remote:** `https://github.com/sushantdev-git/dec-chat.git`
- **Default Branch:** `main`
- **Active Feature Branch:** `feat/mesh-routing-engine`
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
