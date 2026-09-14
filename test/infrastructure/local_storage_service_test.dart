import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/infrastructure/services/local_storage_service.dart';
import 'package:grid/presentation/models/chat_message.dart';
import 'package:grid/presentation/models/peer_model.dart';

void main() {
  group('LocalStorageService (File-backed)', () {
    late Directory tempDir;
    late LocalStorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dec_chat_test_');
      storage = LocalStorageService(customDir: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves, loads, and deletes identity JSON', () async {
      expect(await storage.loadIdentity(), isNull);

      final identityData = {
        'version': 1,
        'nickname': 'Alice',
        'noisePrivateKey': List.generate(32, (i) => i),
        'signingPrivateKey': List.generate(32, (i) => 31 - i),
      };

      await storage.saveIdentity(identityData);

      final loaded = await storage.loadIdentity();
      expect(loaded, isNotNull);
      expect(loaded!['nickname'], 'Alice');
      expect(loaded['noisePrivateKey'], orderedEquals(List.generate(32, (i) => i)));

      await storage.deleteIdentity();
      expect(await storage.loadIdentity(), isNull);
    });

    test('saves, loads, and deletes conversation timelines', () async {
      expect(await storage.loadTimeline(), isNull);

      final msg1 = ChatMessage(
        id: 'msg_1',
        senderId: 'peer_1',
        senderNickname: 'Alice',
        content: 'Hello Mesh',
        timestamp: DateTime.now(),
        isOutgoing: false,
        channelOrPeerId: '#mesh',
      );

      final msg2 = ChatMessage(
        id: 'msg_2',
        senderId: 'peer_2',
        senderNickname: 'Bob',
        content: 'Hey Alice',
        timestamp: DateTime.now(),
        isOutgoing: true,
        channelOrPeerId: 'peer_1',
      );

      final timeline = {
        '#mesh': [msg1],
        'peer_1': [msg2],
      };

      await storage.saveTimeline(timeline);

      final loaded = await storage.loadTimeline();
      expect(loaded, isNotNull);
      expect(loaded!.containsKey('#mesh'), isTrue);
      expect(loaded['#mesh']!.length, 1);
      expect(loaded['#mesh']!.first.content, 'Hello Mesh');

      expect(loaded.containsKey('peer_1'), isTrue);
      expect(loaded['peer_1']!.length, 1);
      expect(loaded['peer_1']!.first.content, 'Hey Alice');

      await storage.deleteTimeline();
      expect(await storage.loadTimeline(), isNull);
    });

    test('saves, loads, and deletes peer models', () async {
      expect(await storage.loadPeers(), isNull);

      final peer1 = PeerModel(
        peerId: 'a1b2c3d4e5f60718',
        nickname: 'Alice',
        noisePublicKey: 'aabbccdd',
        signingPublicKey: 'eeff0011',
        rssi: -65,
        hops: 0,
        lastSeen: DateTime.now(),
        isDirectNeighbor: true,
        isVerified: true,
        medium: TransportMedium.bleMesh,
        safetyNumber: '12345 67890',
      );

      await storage.savePeers([peer1]);

      final loaded = await storage.loadPeers();
      expect(loaded, isNotNull);
      expect(loaded!.length, 1);
      expect(loaded.first.peerId, 'a1b2c3d4e5f60718');
      expect(loaded.first.nickname, 'Alice');
      expect(loaded.first.isVerified, isTrue);
      expect(loaded.first.medium, TransportMedium.bleMesh);

      await storage.deletePeers();
      expect(await storage.loadPeers(), isNull);
    });

    test('wipeAll scrubs and removes all persistent files', () async {
      await storage.saveIdentity({'nickname': 'ToWipe'});
      await storage.saveTimeline({'#mesh': []});
      await storage.savePeers([]);

      expect(await storage.loadIdentity(), isNotNull);
      expect(await storage.loadTimeline(), isNotNull);
      expect(await storage.loadPeers(), isNotNull);

      await storage.wipeAll();

      expect(await storage.loadIdentity(), isNull);
      expect(await storage.loadTimeline(), isNull);
      expect(await storage.loadPeers(), isNull);

      // Verify files do not exist on disk
      final identityFile = File('${tempDir.path}/identity.json');
      final conversationsFile = File('${tempDir.path}/conversations.json');
      final peersFile = File('${tempDir.path}/peers.json');

      expect(await identityFile.exists(), isFalse);
      expect(await conversationsFile.exists(), isFalse);
      expect(await peersFile.exists(), isFalse);
    });
  });

  group('LocalStorageService (In-Memory Fallback)', () {
    test('operates transparently when in-memory only', () async {
      final storage = LocalStorageService(inMemoryOnly: true);

      await storage.saveIdentity({'test': 'val'});
      expect(await storage.loadIdentity(), {'test': 'val'});

      await storage.wipeAll();
      expect(await storage.loadIdentity(), isNull);
    });
  });
}
