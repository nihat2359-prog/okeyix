import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedbackSettingsService {
  static const String _soundKey = 'settings.sound_enabled';
  static const String _vibrationKey = 'settings.vibration_enabled';

  static bool _loaded = false;
  static bool _soundEnabled = true;
  static bool _vibrationEnabled = true;

  static bool get soundEnabled => _soundEnabled;
  static bool get vibrationEnabled => _vibrationEnabled;

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool(_soundKey) ?? true;
    _vibrationEnabled = prefs.getBool(_vibrationKey) ?? true;
    _loaded = true;
  }

  static Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, value);
    _loaded = true;
  }

  static Future<void> setVibrationEnabled(bool value) async {
    _vibrationEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationKey, value);
    _loaded = true;
  }

  static Future<void> triggerHaptic() async {
    if (!_vibrationEnabled) return;
    await HapticFeedback.selectionClick();
  }
}

