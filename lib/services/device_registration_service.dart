import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:okeyix/services/device_identity_service.dart';
import 'package:okeyix/services/push_notification_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceRegistrationService {
  DeviceRegistrationService._();

  static Future<void> registerCurrentDevice({
    String? pushTokenOverride,
    bool lookupPushToken = true,
  }) async {
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;
    if (session == null || user == null) {
      debugPrint('REGISTER_DEVICE SKIP: no session');
      return;
    }

    final deviceId = await DeviceIdentityService.getStableInstallId();
    final packageInfo = await PackageInfo.fromPlatform();
    final pushToken = pushTokenOverride ??
        (lookupPushToken
            ? await PushNotificationService.instance.getToken()
            : null);
    debugPrint(
      'REGISTER_DEVICE START: user=${user.id} token=${pushToken == null ? "YOK" : "VAR"}',
    );

    String platform = "web";
    String deviceModel = "";
    String osVersion = "";

    if (kIsWeb) {
      platform = "web";
      deviceModel = "browser";
      osVersion = "web";
    } else {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        platform = "android";
        deviceModel = android.model;
        osVersion = android.version.release;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        platform = "ios";
        deviceModel = ios.utsname.machine;
        osVersion = ios.systemVersion;
      }
    }

    final res = await supabase.functions.invoke(
      'register_device',
      body: {
        "user_id": user.id,
        "device_id": deviceId,
        "platform": platform,
        "device_model": deviceModel,
        "os_version": osVersion,
        "app_version": packageInfo.version,
        "push_token": pushToken,
      },
    );
    debugPrint('REGISTER_DEVICE DONE: ${res.data}');
  }
}
