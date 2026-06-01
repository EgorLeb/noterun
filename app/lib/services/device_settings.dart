import 'package:shared_preferences/shared_preferences.dart';

/// Local device-only settings — not synced to server.
class DeviceSettings {
  static const _pitchDeltaKey = 'device_pitch_delta';

  /// Pitch shift in semitones: -6.0..+6.0. Default 0.0.
  static Future<double> getPitchDelta() async {
    final prefs = await SharedPreferences.getInstance();
    // Legacy: value may have been stored as int — handle both types.
    final raw = prefs.get(_pitchDeltaKey);
    if (raw == null) return 0.0;
    if (raw is double) return raw;
    if (raw is int) return raw.toDouble();
    return 0.0;
  }

  static Future<void> setPitchDelta(double delta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_pitchDeltaKey, delta.clamp(-6.0, 6.0));
  }
}
