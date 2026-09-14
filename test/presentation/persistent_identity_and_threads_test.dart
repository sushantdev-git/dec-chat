import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/application/bitchat_coordinator.dart';
import 'package:grid/domain/entities/bitchat_packet.dart';
import 'package:grid/domain/enums/message_type.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/ports/transport_port.dart';
import 'package:grid/infrastructure/services/local_storage_service.dart';
import 'package:grid/presentation/models/chat_message.dart';
import 'package:grid/presentation/state/identity_state.dart';
import 'package:grid/presentation/state/panic_controller.dart';
import 'package:grid/presentation/state/peers_notifier.dart';
import 'package:grid/presentation/state/timeline_notifier.dart';

void main() {
  group('Persistent Identity & Thread Unification Across App Restarts', () {
    late Directory tempDir;
    late LocalStorageService storageService;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('bitchat_sim_');
      storageService = LocalStorageService(customDir: tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('IdentityNotifier retains identical peerId and keys across restarts', () async {
      // Session 1: App starts for the first time
      final notifierSession1 = IdentityNotifier(null, storageService);
      await notifierSession1.initialize(nickname: 'AlicePhone');

      final session1State = notifierSession1.state;
      expect(session1State.isInitialized, isTrue);
      expect(session1State.nickname, 'AlicePhone');
      final firstPeerId = session1State.peerIdHex;
      final firstFingerprint = session1State.keyPair!.fingerprint;
      expect(firstPeerId.length, 16);

      // Session 2: App is closed and restarted
      final notifierSession2 = IdentityNotifier(null, storageService);
      await notifierSession2.initialize();

      final session2State = notifierSession2.state;
      expect(session2State.isInitialized, isTrue);
      expect(session2State.nickname, 'AlicePhone');
      // peerIdHex and cryptographic keys MUST match 100%
      expect(session2State.peerIdHex, firstPeerId);
      expect(session2State.keyPair!.fingerprint, firstFingerprint);
      expect(session2State.keyPair!.peerId, orderedEquals(session1State.keyPair!.peerId));
    });

    test('TimelineNotifier restores conversation history and unifies threads for the same peer', () async {
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storageService),
          bitchatCoordinatorProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final identityNotifier = container.read(identityProvider.notifier);
      await identityNotifier.initialize(nickname: 'DeviceA');
      final identity = container.read(identityProvider);

      final timelineNotifier = container.read(timelineProvider.notifier);
      await timelineNotifier.initialize();

      const peerBId = 'b0b0b0b0b0b0b0b0';

      // 1. Device A sends a direct message to Device B
      await timelineNotifier.sendUserMessage(
        channelOrPeerId: peerBId,
        text: 'Hello Device B!',
      );

      // Verify message is in peer B's thread
      final threadMessages1 = container.read(timelineProvider).getMessages(peerBId);
      expect(threadMessages1.length, 1);
      expect(threadMessages1.first.content, 'Hello Device B!');

      // 2. Device B sends a reply
      final inboundPacket = BitchatPacket(
        type: MessageType.message,
        senderId: Uint8List.fromList([0xb0, 0xb0, 0xb0, 0xb0, 0xb0, 0xb0, 0xb0, 0xb0]),
        recipientId: identity.keyPair!.peerId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: Uint8List.fromList('Hey Device A, got your message!'.codeUnits),
      );

      timelineNotifier.handleInboundPacket(
        inboundPacket,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: peerBId,
          medium: TransportMedium.bleMesh,
        ),
      );

      final threadMessages2 = container.read(timelineProvider).getMessages(peerBId);
      expect(threadMessages2.length, 2);
      expect(threadMessages2.last.content, 'Hey Device A, got your message!');

      // 3. Simulate App Restart: create a fresh ProviderContainer reading from the same storage
      final restartedContainer = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storageService),
          bitchatCoordinatorProvider.overrideWithValue(null),
        ],
      );
      addTearDown(restartedContainer.dispose);

      final restartedTimelineNotifier = restartedContainer.read(timelineProvider.notifier);
      await restartedTimelineNotifier.initialize();

      // Verify that all messages in peer B's thread are restored
      final restoredMessages = restartedContainer.read(timelineProvider).getMessages(peerBId);
      expect(restoredMessages.length, 2);
      expect(restoredMessages[0].content, 'Hello Device B!');
      expect(restoredMessages[1].content, 'Hey Device A, got your message!');

      // 4. Device B restarts and sends another message (using same peerId)
      final followUpPacket = BitchatPacket(
        type: MessageType.message,
        senderId: Uint8List.fromList([0xb0, 0xb0, 0xb0, 0xb0, 0xb0, 0xb0, 0xb0, 0xb0]),
        recipientId: identity.keyPair!.peerId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: Uint8List.fromList('Still here in the same thread!'.codeUnits),
      );

      restartedTimelineNotifier.handleInboundPacket(
        followUpPacket,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: peerBId,
          medium: TransportMedium.bleMesh,
        ),
      );

      // Check that NO new thread was opened, and message appended to the SAME thread
      final unifiedMessages = restartedContainer.read(timelineProvider).getMessages(peerBId);
      expect(unifiedMessages.length, 3);
      expect(unifiedMessages[2].content, 'Still here in the same thread!');

      // Verify channel count has not duplicated
      final allThreads = restartedContainer.read(timelineProvider).messagesByChannel.keys.toList();
      expect(allThreads.contains(peerBId), isTrue);
      expect(allThreads.length, 1);
    });

    test('PeersNotifier deduplicates by peerId and noisePublicKey across restarts', () async {
      final peersNotifier = PeersNotifier(null, storageService);
      await peersNotifier.initialize();

      const peerId = 'c0c0c0c0c0c0c0c0';
      const noisePub = '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff';

      // 1. Initial discovery
      peersNotifier.updatePresence(
        peerId: peerId,
        nickname: 'Charlie',
        noisePublicKey: noisePub,
        rssi: -70,
      );

      expect(peersNotifier.state.allPeers.length, 1);
      expect(peersNotifier.state.getPeer(peerId)?.nickname, 'Charlie');

      // 2. Subsequent announcement arrives with updated RSSI and nickname
      peersNotifier.updatePresence(
        peerId: peerId,
        nickname: 'Charlie (Updated)',
        noisePublicKey: noisePub,
        rssi: -55,
      );

      // Must update existing peer, NOT create a second peer
      expect(peersNotifier.state.allPeers.length, 1);
      expect(peersNotifier.state.getPeer(peerId)?.nickname, 'Charlie (Updated)');
      expect(peersNotifier.state.getPeer(peerId)?.rssi, -55);

      // 3. Simulate app restart
      final restartedPeersNotifier = PeersNotifier(null, storageService);
      await restartedPeersNotifier.initialize();

      expect(restartedPeersNotifier.state.allPeers.length, 1);
      expect(restartedPeersNotifier.state.getPeer(peerId)?.nickname, 'Charlie (Updated)');
    });

    test('Panic wipe zeroizes in-memory state and purges persistent disk files', () async {
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storageService),
          bitchatCoordinatorProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      // Setup state in all notifiers
      final identityNotifier = container.read(identityProvider.notifier);
      await identityNotifier.initialize(nickname: 'SecretUser');
      final originalPeerId = container.read(identityProvider).peerIdHex;

      final timelineNotifier = container.read(timelineProvider.notifier);
      timelineNotifier.addMessage(ChatMessage(
        id: 'msg_sec',
        senderId: originalPeerId,
        senderNickname: 'SecretUser',
        content: 'Top secret data',
        timestamp: DateTime.now(),
        isOutgoing: true,
        channelOrPeerId: '#mesh',
      ));

      final peersNotifier = container.read(peersProvider.notifier);
      peersNotifier.updatePresence(
        peerId: 'd0d0d0d0d0d0d0d0',
        nickname: 'Dave',
      );

      expect(await storageService.loadIdentity(), isNotNull);
      expect(await storageService.loadTimeline(), isNotNull);
      expect(await storageService.loadPeers(), isNotNull);

      // Execute panic wipe
      final panicController = container.read(panicControllerProvider);
      await panicController.executePanicWipe();

      // In-memory timelines and peers cleared
      expect(container.read(timelineProvider).getMessages('#mesh'), isEmpty);
      expect(container.read(peersProvider).allPeers, isEmpty);

      // Identity was replaced with a new random ephemeral key
      final newIdentity = container.read(identityProvider);
      expect(newIdentity.peerIdHex, isNot(equals(originalPeerId)));

      // Disk storage was wiped completely
      expect(await storageService.loadIdentity(), isNull);
      expect(await storageService.loadTimeline(), isNull);
      expect(await storageService.loadPeers(), isNull);
    });
  });
}
