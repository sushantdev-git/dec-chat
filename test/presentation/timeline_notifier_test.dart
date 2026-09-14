import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/domain/entities/bitchat_packet.dart';
import 'package:grid/domain/enums/message_type.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/ports/transport_port.dart';
import 'package:grid/presentation/state/channels_notifier.dart';
import 'package:grid/presentation/state/identity_state.dart';
import 'package:grid/presentation/state/peers_notifier.dart';
import 'package:grid/presentation/state/timeline_notifier.dart';

void main() {
  group('TimelineNotifier Ephemeral Chat & Commands', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('sends public message and appends to channel timeline', () async {
      final notifier = container.read(timelineProvider.notifier);

      await notifier.sendUserMessage(channelOrPeerId: '#mesh', text: 'Hello Decentralized Mesh!');

      final messages = container.read(timelineProvider).getMessages('#mesh');
      expect(messages.length, equals(1));
      expect(messages.first.content, equals('Hello Decentralized Mesh!'));
      expect(messages.first.isOutgoing, isTrue);
      expect(messages.first.isEncrypted, isFalse);
    });

    test('sends directed message with E2EE flag set to true', () async {
      final notifier = container.read(timelineProvider.notifier);
      const peerId = 'target_peer_123';

      await notifier.sendUserMessage(channelOrPeerId: peerId, text: 'Secret message');

      final messages = container.read(timelineProvider).getMessages(peerId);
      expect(messages.length, equals(1));
      expect(messages.first.content, equals('Secret message'));
      expect(messages.first.isOutgoing, isTrue);
      expect(messages.first.isEncrypted, isTrue); // Peer chats are encrypted
    });

    test('executes /slap command', () async {
      final notifier = container.read(timelineProvider.notifier);

      await notifier.sendUserMessage(channelOrPeerId: '#mesh', text: '/slap Bob');

      final messages = container.read(timelineProvider).getMessages('#mesh');
      expect(messages.length, equals(1));
      expect(messages.first.content, contains('slaps Bob with a large trout'));
    });

    test('executes /join command and joins channel in channelsProvider', () async {
      final notifier = container.read(timelineProvider.notifier);

      await notifier.sendUserMessage(channelOrPeerId: '#mesh', text: '/join #9q8yy');

      final channelsState = container.read(channelsProvider);
      expect(channelsState.joinedChannels, contains('#9q8yy'));

      final channelMessages = container.read(timelineProvider).getMessages('#9q8yy');
      expect(channelMessages.length, equals(1));
      expect(channelMessages.first.content, contains('Joined channel #9q8yy'));
    });

    test('executes /clear command to wipe active channel messages', () async {
      final notifier = container.read(timelineProvider.notifier);

      await notifier.sendUserMessage(channelOrPeerId: '#mesh', text: 'Msg 1');
      await notifier.sendUserMessage(channelOrPeerId: '#mesh', text: 'Msg 2');
      expect(container.read(timelineProvider).getMessages('#mesh').length, equals(2));

      await notifier.sendUserMessage(channelOrPeerId: '#mesh', text: '/clear');
      final msgs = container.read(timelineProvider).getMessages('#mesh');
      expect(msgs.length, equals(1)); // Only the system confirmation message remains
      expect(msgs.first.content, contains('timeline cleared'));
    });

    test('executes /panic command to purge all timelines', () async {
      final notifier = container.read(timelineProvider.notifier);

      await notifier.sendUserMessage(channelOrPeerId: '#mesh', text: 'Msg in mesh');
      await notifier.sendUserMessage(channelOrPeerId: '#general', text: 'Msg in general');

      await notifier.sendUserMessage(channelOrPeerId: '#mesh', text: '/panic');

      expect(container.read(timelineProvider).getMessages('#general').isEmpty, isTrue);
      final meshMsgs = container.read(timelineProvider).getMessages('#mesh');
      expect(meshMsgs.length, equals(1));
      expect(meshMsgs.first.content, contains('EMERGENCY PANIC WIPE EXECUTED'));
    });

    test('processes inbound packet and adds incoming message to timeline', () {
      final notifier = container.read(timelineProvider.notifier);

      final senderBytes = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44]);
      const senderHex = 'aabbccdd11223344';

      // Register peer in peer directory
      container.read(peersProvider.notifier).updatePresence(
            peerId: senderHex,
            nickname: 'Satoshi',
          );

      final packet = BitchatPacket(
        type: MessageType.message,
        ttl: 5,
        timestamp: 1600000000000,
        senderId: senderBytes,
        recipientId: null,
        payload: Uint8List.fromList(utf8.encode('Hello from Satoshi!')),
      );

      notifier.handleInboundPacket(
        packet,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: senderHex,
          medium: TransportMedium.bleMesh,
        ),
      );

      final messages = container.read(timelineProvider).getMessages('#mesh');
      expect(messages.length, equals(1));
      expect(messages.first.content, equals('Hello from Satoshi!'));
      expect(messages.first.senderNickname, equals('Satoshi'));
      expect(messages.first.isOutgoing, isFalse);
    });

    test('drops inbound packet originating from local peer ID (echo suppression)', () {
      final notifier = container.read(timelineProvider.notifier);
      final localPeerIdHex = container.read(identityProvider).peerIdHex;

      final localBytes = Uint8List(8);
      for (int i = 0; i < 8; i++) {
        localBytes[i] = int.parse(localPeerIdHex.substring(i * 2, i * 2 + 2), radix: 16);
      }

      final echoPacket = BitchatPacket(
        type: MessageType.message,
        ttl: 5,
        timestamp: 1600000000000,
        senderId: localBytes,
        recipientId: null,
        payload: Uint8List.fromList(utf8.encode('Echo echo')),
      );

      notifier.handleInboundPacket(
        echoPacket,
        TransportPacketEvent(
          packetBytes: Uint8List(0),
          sourcePeerId: localPeerIdHex,
          medium: TransportMedium.bleMesh,
        ),
      );

      final messages = container.read(timelineProvider).getMessages('#mesh');
      expect(messages.isEmpty, isTrue); // Suppressed!
    });
  });
}
