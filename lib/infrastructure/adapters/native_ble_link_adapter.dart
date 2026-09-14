import 'dart:async';
import 'package:flutter/services.dart';

import '../../core/constants/ble_constants.dart';
import '../../domain/enums/transport_medium.dart';
import '../../domain/ports/power_policy_port.dart';
import '../../domain/ports/transport_port.dart';

/// Concrete [TransportPort] adapter bridging Dart mesh routing with native dual-role BLE.
///
/// Communicates with iOS CoreBluetooth and Android BluetoothLeAdvertiser/GattServer
/// via Flutter platform channels.
class NativeBleLinkAdapter implements TransportPort, PowerPolicyPort {
  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  final StreamController<TransportPacketEvent> _packetStreamController =
      StreamController<TransportPacketEvent>.broadcast();

  final Set<String> _connectedPeerIds = <String>{};
  StreamSubscription? _nativeEventSubscription;
  bool _isAvailable = false;
  BlePowerMode _powerMode = BlePowerMode.active;

  NativeBleLinkAdapter({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel(BleConstants.controlMethodChannelName),
        _eventChannel =
            eventChannel ?? const EventChannel(BleConstants.eventChannelName);

  @override
  TransportMedium get medium => TransportMedium.bleMesh;

  @override
  Stream<TransportPacketEvent> get incomingPackets =>
      _packetStreamController.stream;

  @override
  List<String> get connectedPeerIds => List.unmodifiable(_connectedPeerIds);

  @override
  bool get isAvailable => _isAvailable;

  @override
  BlePowerMode get currentMode => _powerMode;

  @override
  Future<void> start({BlePowerMode mode = BlePowerMode.active}) async {
    if (_isAvailable) return;

    _powerMode = mode;
    _subscribeToNativeEvents();

    try {
      final success = await _methodChannel.invokeMethod<bool>(
        'start',
        {'mode': mode.name},
      );
      _isAvailable = success ?? true;
    } on MissingPluginException {
      _isAvailable = false;
    } on PlatformException catch (e) {
      _isAvailable = false;
      throw StateError('Failed to initialize native BLE link: ${e.message}');
    } catch (_) {
      _isAvailable = false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod('stop');
    } catch (_) {
      // Best-effort stop
    } finally {
      await _nativeEventSubscription?.cancel();
      _nativeEventSubscription = null;
      _connectedPeerIds.clear();
      _isAvailable = false;
    }
  }

  @override
  Future<void> sendBroadcast(Uint8List packetBytes) async {
    if (!_isAvailable) {
      throw StateError('Cannot send broadcast: BLE link is not active');
    }

    try {
      await _methodChannel.invokeMethod('sendBroadcast', {
        'data': packetBytes,
      });
    } on PlatformException catch (e) {
      throw StateError('Native BLE broadcast failed: ${e.message}');
    }
  }

  @override
  Future<void> sendDirected(String targetPeerId, Uint8List packetBytes) async {
    if (!_isAvailable) {
      throw StateError('Cannot send directed packet: BLE link is not active');
    }

    try {
      await _methodChannel.invokeMethod('sendDirected', {
        'peerId': targetPeerId,
        'data': packetBytes,
      });
    } on PlatformException catch (e) {
      throw StateError(
        'Native BLE directed transmission to $targetPeerId failed: ${e.message}',
      );
    }
  }

  @override
  Future<void> setPowerMode(BlePowerMode mode) async {
    _powerMode = mode;
    if (_isAvailable) {
      try {
        await _methodChannel.invokeMethod('setPowerMode', {
          'mode': mode.name,
        });
      } on PlatformException catch (e) {
        throw StateError('Failed to update BLE power mode: ${e.message}');
      }
    }
  }

  void _subscribeToNativeEvents() {
    _nativeEventSubscription?.cancel();
    _nativeEventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (error) {
        // Handle native platform channel errors
      },
    );
  }

  void _handleNativeEvent(dynamic event) {
    if (event is! Map) return;

    final type = event['type'] as String?;
    switch (type) {
      case 'packetReceived':
        final rawData = event['data'];
        final peerId = event['peerId'] as String? ?? 'unknown';
        final rssi = event['rssi'] as int?;

        final Uint8List packetBytes;
        if (rawData is Uint8List) {
          packetBytes = rawData;
        } else if (rawData is List) {
          packetBytes = Uint8List.fromList(List<int>.from(rawData));
        } else {
          return;
        }

        _packetStreamController.add(
          TransportPacketEvent(
            packetBytes: packetBytes,
            sourcePeerId: peerId,
            medium: TransportMedium.bleMesh,
            rssi: rssi,
          ),
        );
        break;

      case 'peerConnected':
        final peerId = event['peerId'] as String?;
        if (peerId != null && peerId.isNotEmpty) {
          _connectedPeerIds.add(peerId);
        }
        break;

      case 'peerDisconnected':
        final peerId = event['peerId'] as String?;
        if (peerId != null) {
          _connectedPeerIds.remove(peerId);
        }
        break;

      case 'adapterStateChanged':
        final state = event['state'] as String?;
        _isAvailable = state == 'poweredOn';
        break;
    }
  }

  /// Disposes resources, subscriptions, and stream controllers.
  void dispose() {
    stop();
    _packetStreamController.close();
  }
}
