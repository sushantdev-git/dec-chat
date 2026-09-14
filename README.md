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

- [ ] **Phase 1: Pure Dart Wire Protocol & Codecs** (BinaryReader, BinaryWriter, BitchatPacket, TLV AnnouncementCodec, FragmentCodec)
- [ ] **Phase 2: Cryptographic Engine & Identity** (Ed25519 signing, Curve25519 key agreement, Noise_XX handshake, ChaCha20-Poly1305)
- [ ] **Phase 3: Mesh Engine & Headless Multi-Node Simulation** (Deduplication LRU, jitter scheduler, TTL clamping, SimulatedLinkLayer 10-node test)
- [ ] **Phase 4: Native BLE Dual-Role Radio Bridge** (Swift iOS CoreBluetooth + Kotlin Android BLE Advertiser/GattServer)
- [ ] **Phase 5: Nostr Dual-Transport & Location Channels** (WebSocket relays, Geohash chat rooms)
- [ ] **Phase 6: Riverpod Application State & Signal UI** (Conversation threads, peer directory, message bubbles, IRC slash commands)
- [ ] **Phase 7: Store-and-Forward Couriers, Panic Wipe & Field Polish** (Spray-and-wait outbox, instant zeroization, QR safety verification)

---

## 📦 Repository & Local Environment

- **Git Remote:** `https://github.com/sushantdev-git/dec-chat.git`
- **Default Branch:** `main`
- **Author:** Sushant Mishra (`sushantkumar6700@gmail.com`)

### Prerequisites & Setup
To run and develop DecChat locally:
1. **Flutter SDK:** Ensure Flutter (≥ 3.22.0) and Dart (≥ 3.4.0) are installed:
   ```bash
   # Via Homebrew (macOS)
   brew install --cask flutter
   
   # Or download directly from:
   # https://docs.flutter.dev/get-started/install/macos
   ```
2. Verify installation:
   ```bash
   flutter doctor
   ```
3. Run automated tests (headless):
   ```bash
   dart test
   ```

---

## 📄 License

This project is dedicated to the public domain under the [Unlicense](http://unlicense.org/).
