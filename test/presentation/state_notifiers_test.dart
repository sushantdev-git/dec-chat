import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid/application/bitchat_coordinator.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/presentation/state/channels_notifier.dart';
import 'package:grid/presentation/state/identity_state.dart';
import 'package:grid/presentation/state/panic_controller.dart';
import 'package:grid/presentation/state/peers_notifier.dart';

void main() {
  group('PeersNotifier Peer Directory State', () {
    late PeersNotifier notifier;

    setUp(() {
      notifier = PeersNotifier();
    });

    test('updates presence and calculates direct vs multi-hop correctly', () {
      notifier.updatePresence(
        peerId: 'peer12345678',
        nickname: 'Alice',
        rssi: -65,
        hops: 0, // Direct neighbor
        medium: TransportMedium.bleMesh,
      );

      final peer = notifier.state.getPeer('peer12345678');
      expect(peer, isNotNull);
      expect(peer!.nickname, equals('Alice'));
      expect(peer.isDirectNeighbor, isTrue);
      expect(peer.hops, equals(0));
      expect(peer.signalQuality, equals('Good'));
      expect(peer.isVerified, isFalse);

      // Multi-hop peer update
      notifier.updatePresence(
        peerId: 'peer87654321',
        nickname: 'Bob',
        rssi: null,
        hops: 2,
        medium: TransportMedium.nostr,
      );

      final bob = notifier.state.getPeer('peer87654321');
      expect(bob, isNotNull);
      expect(bob!.isDirectNeighbor, isFalse);
      expect(bob.hops, equals(2));
      expect(bob.signalQuality, equals('Internet / Relay'));
      expect(bob.medium, equals(TransportMedium.nostr));

      expect(notifier.state.allPeers.length, equals(2));
      expect(notifier.state.directPeers.length, equals(1));
    });

    test('toggles cryptographic safety number verification', () {
      notifier.updatePresence(
        peerId: 'peer_verified_test',
        nickname: 'Carol',
      );

      expect(notifier.state.getPeer('peer_verified_test')!.isVerified, isFalse);
      expect(notifier.state.verifiedPeers.isEmpty, isTrue);

      notifier.toggleVerification('peer_verified_test');
      expect(notifier.state.getPeer('peer_verified_test')!.isVerified, isTrue);
      expect(notifier.state.verifiedPeers.length, equals(1));

      // Toggle back to unverified
      notifier.toggleVerification('peer_verified_test');
      expect(notifier.state.getPeer('peer_verified_test')!.isVerified, isFalse);
    });

    test('clears all peers on panic wipe', () {
      notifier.updatePresence(peerId: 'p1', nickname: 'Node 1');
      notifier.updatePresence(peerId: 'p2', nickname: 'Node 2');
      expect(notifier.state.allPeers.length, equals(2));

      notifier.clear();
      expect(notifier.state.allPeers.isEmpty, isTrue);
      expect(notifier.state.peers.isEmpty, isTrue);
    });
  });

  group('ChannelsNotifier Channel Management', () {
    late ChannelsNotifier notifier;

    setUp(() {
      notifier = ChannelsNotifier();
    });

    test('initializes with default #mesh and #general channels', () {
      expect(notifier.state.joinedChannels, contains('#mesh'));
      expect(notifier.state.joinedChannels, contains('#general'));
      expect(notifier.state.activeChannel, equals('#mesh'));
    });

    test('joins channel, normalizes # prefix, and sets as active', () {
      notifier.joinChannel('9q8yy'); // Without '#'
      expect(notifier.state.joinedChannels, contains('#9q8yy'));
      expect(notifier.state.activeChannel, equals('#9q8yy'));

      notifier.joinChannel('#crypto');
      expect(notifier.state.joinedChannels, contains('#crypto'));
      expect(notifier.state.activeChannel, equals('#crypto'));
    });

    test('preserves #mesh invariant (cannot leave #mesh)', () {
      final leftMesh = notifier.leaveChannel('#mesh');
      expect(leftMesh, isFalse);
      expect(notifier.state.joinedChannels, contains('#mesh'));

      // Can leave other channels
      notifier.joinChannel('#temp');
      expect(notifier.state.joinedChannels, contains('#temp'));
      final leftTemp = notifier.leaveChannel('#temp');
      expect(leftTemp, isTrue);
      expect(notifier.state.joinedChannels.contains('#temp'), isFalse);
      expect(notifier.state.activeChannel, equals('#mesh'));
    });

    test('switches active channel view', () {
      notifier.setActiveChannel('#general');
      expect(notifier.state.activeChannel, equals('#general'));
    });

    test('resets channels to default on panic wipe', () {
      notifier.joinChannel('#temp1');
      notifier.joinChannel('#temp2');
      notifier.clear();

      expect(notifier.state.joinedChannels, equals({'#mesh', '#general'}));
      expect(notifier.state.activeChannel, equals('#mesh'));
    });
  });

  group('PanicController Lifecycle & Recovery', () {
    test('executePanicWipe clears state and re-arms coordinator with startScan', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initialize identity
      await container.read(identityProvider.notifier).initialize();
      final initialPeerId = container.read(identityProvider).peerIdHex;

      // Add a peer
      container.read(peersProvider.notifier).updatePresence(peerId: 'peer_abc', nickname: 'PeerABC');
      expect(container.read(peersProvider).allPeers.length, equals(1));

      // Execute wipe
      await container.read(panicControllerProvider).executePanicWipe();

      // Peers cleared
      expect(container.read(peersProvider).allPeers.isEmpty, isTrue);

      // Identity changed to fresh ephemeral key
      final newPeerId = container.read(identityProvider).peerIdHex;
      expect(newPeerId, isNot(equals(initialPeerId)));

      // New coordinator is running and started
      final coordinator = container.read(bitchatCoordinatorProvider);
      expect(coordinator, isNotNull);
      expect(coordinator!.isStarted, isTrue);
    });
  });
}
