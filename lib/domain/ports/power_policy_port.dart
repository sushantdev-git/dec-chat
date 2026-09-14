/// Adaptive BLE power duty-cycle profiles for battery optimization.
enum BlePowerMode {
  /// Active Mode (App in active foreground):
  /// 100% continuous scanning and continuous advertising.
  active,

  /// Balanced Mode (App idle in foreground):
  /// 15 seconds active scan, 15 seconds idle sleep.
  balanced,

  /// Background Mode (App in background):
  /// 5 seconds active scan, 55 seconds idle sleep.
  background,
}

/// Abstract port for controlling the radio's adaptive duty-cycle and power consumption.
abstract class PowerPolicyPort {
  /// Currently active power mode.
  BlePowerMode get currentMode;

  /// Transitions the BLE radio subsystem into the designated power profile.
  Future<void> setPowerMode(BlePowerMode mode);
}
