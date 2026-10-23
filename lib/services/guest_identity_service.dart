import 'package:flutter/foundation.dart';
import 'device_identity_service.dart';

/// A private developer key is supplied by the local launch configuration.
/// Only web debug can use this key. Native and release/profile builds always
/// use the normal installation identity, even if launch arguments include it.
String? developmentGuestIdentity({required bool debugBuild, required String localKey,
  bool requireConfigured = false, bool browserBuild = true}) {
  if (!browserBuild) return null;
  final key = localKey.trim();
  if (debugBuild && requireConfigured && key.isEmpty) {
    throw StateError('DEV_GUEST_KEY_REQUIRED');
  }
  return debugBuild && key.isNotEmpty ? 'okeyix-dev-guest:$key' : null;
}

class GuestIdentityService {
  static const _localKey = String.fromEnvironment('OKEYIX_DEV_GUEST_KEY');
  static bool get missingDebugWebKey => kDebugMode && kIsWeb && _localKey.trim().isEmpty;
  static Future<String> getInstallId() async =>
      developmentGuestIdentity(debugBuild: kDebugMode, localKey: _localKey,
        requireConfigured: kIsWeb, browserBuild: kIsWeb) ??
      await DeviceIdentityService.getStableInstallId();
}
