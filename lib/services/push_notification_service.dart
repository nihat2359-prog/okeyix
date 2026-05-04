import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

typedef PushTokenCallback = FutureOr<void> Function(String token);
typedef PushDataCallback = FutureOr<void> Function(Map<String, dynamic> data);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background handler must stay lightweight.
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  PushDataCallback? _onNotificationTapData;

  Future<void> init({
    PushTokenCallback? onToken,
    PushDataCallback? onNotificationTapData,
  }) async {
    if (_initialized) return;
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      _onNotificationTapData = onNotificationTapData;

      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty && onToken != null) {
        await onToken(token);
      }

      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        if (newToken.isNotEmpty && onToken != null) {
          await onToken(newToken);
        }
      });

      _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        final data = msg.data;
        if (data.isNotEmpty) {
          _onNotificationTapData?.call(data);
        }
      });

      _onMessageSub = FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('PUSH FOREGROUND MESSAGE: ${msg.data}');
      });

      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && initialMessage.data.isNotEmpty) {
        _onNotificationTapData?.call(initialMessage.data);
      }

      _initialized = true;
    } catch (e) {
      debugPrint('PUSH INIT ERROR: $e');
    }
  }

  Future<String?> getToken() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      return FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _onMessageOpenedSub?.cancel();
    await _onMessageSub?.cancel();
    _tokenRefreshSub = null;
    _onMessageOpenedSub = null;
    _onMessageSub = null;
    _initialized = false;
  }
}

