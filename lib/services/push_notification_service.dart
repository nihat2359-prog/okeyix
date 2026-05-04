import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

typedef PushTokenCallback = FutureOr<void> Function(String token);
typedef PushDataCallback = FutureOr<void> Function(Map<String, dynamic> data);
typedef PushDebugCallback = FutureOr<void> Function(String message);

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
  Future<void>? _firebaseInitFuture;

  Future<void> _ensureFirebaseReady() {
    if (Firebase.apps.isNotEmpty) {
      return Future.value();
    }
    _firebaseInitFuture ??= Firebase.initializeApp();
    return _firebaseInitFuture!;
  }

  Future<void> init({
    PushTokenCallback? onToken,
    PushDataCallback? onNotificationTapData,
    PushDebugCallback? onDebug,
  }) async {
    if (_initialized) return;
    if (kIsWeb) {
      await onDebug?.call('PUSH: Web ortaminda FCM init atlandi');
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      await onDebug?.call('PUSH: Desteklenmeyen platform');
      return;
    }

    try {
      _onNotificationTapData = onNotificationTapData;

      if (Firebase.apps.isEmpty) {
        await _ensureFirebaseReady();
        await onDebug?.call('PUSH: Firebase.initializeApp tamam');
      } else {
        await onDebug?.call('PUSH: Firebase zaten initialize');
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      final before = await messaging.getNotificationSettings();
      await onDebug?.call(
        'PUSH: Izin (once): ${before.authorizationStatus.name}',
      );

      final permission = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await onDebug?.call(
        'PUSH: Izin (sonra): ${permission.authorizationStatus.name}',
      );

      if (Platform.isIOS) {
        final apns = await messaging.getAPNSToken();
        await onDebug?.call(
          'PUSH: APNS token ${apns == null ? "YOK" : "VAR"}',
        );
      }

      final token = await messaging.getToken();
      await onDebug?.call('PUSH: FCM token ${token == null ? "YOK" : "VAR"}');
      if (token != null && token.isNotEmpty && onToken != null) {
        await onToken(token);
        await onDebug?.call('PUSH: Token server kaydi tetiklendi');
      }

      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        if (newToken.isNotEmpty && onToken != null) {
          await onToken(newToken);
          await onDebug?.call('PUSH: Token yenilendi ve kaydedildi');
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
      await onDebug?.call('PUSH: Init tamam');
    } catch (e) {
      debugPrint('PUSH INIT ERROR: $e');
      await onDebug?.call('PUSH INIT ERROR: $e');
    }
  }

  Future<String?> getToken() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      await _ensureFirebaseReady();
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
