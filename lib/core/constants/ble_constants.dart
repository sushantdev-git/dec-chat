/// Bluetooth Low Energy (BLE) protocol constants matching the BitChat specification.
class BleConstants {
  /// BitChat 128-bit Service UUID (standard BitChat mesh radio service).
  static const String serviceUuid = '0000FDC7-0000-1000-8000-00805F9B34FB';

  /// Short 16-bit Service UUID representation (0xFDC7).
  static const String shortServiceUuid = 'FDC7';

  /// BitChat Packet Transfer Characteristic UUID (Read, WriteWithoutResponse, Notify).
  static const String packetCharacteristicUuid = '00002A06-0000-1000-8000-00805F9B34FB';

  /// Target Maximum Transmission Unit (MTU) negotiated over BLE links.
  static const int targetMtu = 512;

  /// Default ATT MTU before negotiation.
  static const int defaultAttMtu = 23;

  /// Effective payload MTU accounting for 3-byte ATT header overhead.
  static const int effectiveMaxPayload = targetMtu - 3; // 509 bytes

  // Platform Channel Names
  static const String controlMethodChannelName = 'com.bitchat.mesh/ble_control';
  static const String eventChannelName = 'com.bitchat.mesh/ble_events';
}
