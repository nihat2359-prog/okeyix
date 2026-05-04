import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  DeviceIdentityService._();

  static const _secureStorage = FlutterSecureStorage();
  static const _stableInstallIdKey = 'stable_install_id_v2';
  static const _webInstallIdKey = 'web_stable_install_id_v2';

  static Future<String> getStableInstallId() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_webInstallIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final created = 'web_${const Uuid().v4()}';
      await prefs.setString(_webInstallIdKey, created);
      return created;
    }

    final existing = await _secureStorage.read(key: _stableInstallIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final prefix = Platform.isAndroid
        ? 'and'
        : Platform.isIOS
            ? 'ios'
            : 'dev';
    final created = '$prefix-${const Uuid().v4()}';
    await _secureStorage.write(key: _stableInstallIdKey, value: created);
    return created;
  }
}

