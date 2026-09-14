import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grid/core/constants/ble_constants.dart';
import 'package:grid/domain/enums/transport_medium.dart';
import 'package:grid/domain/ports/power_policy_port.dart';
import 'package:grid/domain/ports/transport_port.dart';
import 'package:grid/infrastructure/adapters/native_ble_link_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeBleLinkAdapter Platform Channel Bridge', () {
    late NativeBleLinkAdapter adapter;
    late List<MethodCall> methodCalls;

    void emitBleEvent(dynamic event) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        BleConstants.eventChannelName,
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        (ByteData? reply) {},
      );
    }

    setUp(() {
      methodCalls = [];

      // Mock control method channel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BleConstants.controlMethodChannelName),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'start') return true;
          if (call.method == 'stop') return true;
          if (call.method == 'sendBroadcast') return true;
          if (call.method == 'sendDirected') return true;
          if (call.method == 'setPowerMode') return true;
          return null;
        },
      );

      // Mock event channel listen / cancel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BleConstants.eventChannelName),
        (MethodCall call) async {
          return null; // listen or cancel
        },
      );

      adapter = NativeBleLinkAdapter();
    });

    tearDown(() async {
      await adapter.stop();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BleConstants.controlMethodChannelName),
        null,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BleConstants.eventChannelName),
        null,
      );
    });

    test('initializes and starts BLE radio in active power mode', () async {
      expect(adapter.isAvailable, isFalse);
      expect(adapter.medium, TransportMedium.bleMesh);

      await adapter.start(mode: BlePowerMode.active);

      expect(adapter.isAvailable, isTrue);
      expect(adapter.currentMode, BlePowerMode.active);

      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'start');
      expect(methodCalls.first.arguments, {'mode': 'active'});
    });

    test('sends broadcast packet via native channel', () async {
      await adapter.start();

      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      await adapter.sendBroadcast(payload);

      final broadcastCall =
          methodCalls.firstWhere((call) => call.method == 'sendBroadcast');
      expect(broadcastCall.arguments['data'], orderedEquals(payload));
    });

    test('sends directed packet to specific peer ID', () async {
      await adapter.start();

      final payload = Uint8List.fromList([10, 20, 30]);
      await adapter.sendDirected('peer_device_123', payload);

      final directedCall =
          methodCalls.firstWhere((call) => call.method == 'sendDirected');
      expect(directedCall.arguments['peerId'], 'peer_device_123');
      expect(directedCall.arguments['data'], orderedEquals(payload));
    });

    test('throws StateError when attempting transmission before starting adapter', () async {
      final payload = Uint8List.fromList([1, 2, 3]);

      expect(
        () async => await adapter.sendBroadcast(payload),
        throwsA(isA<StateError>()),
      );

      expect(
        () async => await adapter.sendDirected('peer_xyz', payload),
        throwsA(isA<StateError>()),
      );
    });

    test('updates duty cycle power modes', () async {
      await adapter.start(mode: BlePowerMode.active);

      await adapter.setPowerMode(BlePowerMode.balanced);
      expect(adapter.currentMode, BlePowerMode.balanced);

      await adapter.setPowerMode(BlePowerMode.background);
      expect(adapter.currentMode, BlePowerMode.background);

      final powerCalls =
          methodCalls.where((call) => call.method == 'setPowerMode').toList();
      expect(powerCalls.length, 2);
      expect(powerCalls[0].arguments['mode'], 'balanced');
      expect(powerCalls[1].arguments['mode'], 'background');
    });

    test('receives inbound packets from native EventChannel', () async {
      await adapter.start();

      final receivedEvents = <TransportPacketEvent>[];
      final subscription = adapter.incomingPackets.listen(receivedEvents.add);

      // Emit simulated native packetReceived event
      final testData = Uint8List.fromList([42, 43, 44]);
      emitBleEvent({
        'type': 'packetReceived',
        'data': testData,
        'peerId': 'ios_peripheral_99',
        'rssi': -62,
      });

      await pumpEventQueue();

      expect(receivedEvents.length, 1);
      final event = receivedEvents.first;
      expect(event.packetBytes, orderedEquals(testData));
      expect(event.sourcePeerId, 'ios_peripheral_99');
      expect(event.medium, TransportMedium.bleMesh);
      expect(event.rssi, -62);

      await subscription.cancel();
    });

    test('tracks peer connections and disconnections from native events', () async {
      await adapter.start();
      expect(adapter.connectedPeerIds, isEmpty);

      // Connect peer 1
      emitBleEvent({
        'type': 'peerConnected',
        'peerId': 'peer_alpha',
      });
      await pumpEventQueue();
      expect(adapter.connectedPeerIds, contains('peer_alpha'));

      // Connect peer 2
      emitBleEvent({
        'type': 'peerConnected',
        'peerId': 'peer_beta',
      });
      await pumpEventQueue();
      expect(adapter.connectedPeerIds.length, 2);
      expect(adapter.connectedPeerIds, containsAll(['peer_alpha', 'peer_beta']));

      // Disconnect peer 1
      emitBleEvent({
        'type': 'peerDisconnected',
        'peerId': 'peer_alpha',
      });
      await pumpEventQueue();
      expect(adapter.connectedPeerIds.length, 1);
      expect(adapter.connectedPeerIds, contains('peer_beta'));
    });

    test('stops radio and cleans up connected peers', () async {
      await adapter.start();

      emitBleEvent({
        'type': 'peerConnected',
        'peerId': 'peer_alpha',
      });
      await pumpEventQueue();
      expect(adapter.connectedPeerIds, contains('peer_alpha'));

      await adapter.stop();
      expect(adapter.isAvailable, isFalse);
      expect(adapter.connectedPeerIds, isEmpty);

      final stopCall = methodCalls.firstWhere((call) => call.method == 'stop');
      expect(stopCall, isNotNull);
    });
  });
}
