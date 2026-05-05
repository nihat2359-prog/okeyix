import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:okeyix/firebase_options.dart';

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
  Future<void>? _firebaseInitFuture;
  Timer? _iosTokenRetryTimer;
  bool _tokenDelivered = false;

  Future<void> _ensureFirebaseReady() {
    if (Firebase.apps.isNotEmpty) {
      return Future.value();
    }
    _firebaseInitFuture ??= Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return _firebaseInitFuture!;
  }

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
        await _ensureFirebaseReady();
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      await messaging.getNotificationSettings();

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (Platform.isIOS) {
        String? apns;
        for (int i = 0; i < 6; i++) {
          try {
            apns = await messaging.getAPNSToken();
          } catch (_) {
            apns = null;
          }
          if (apns != null && apns.isNotEmpty) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      String? token;
      for (int i = 0; i < 8; i++) {
        try {
          token = await messaging.getToken();
        } catch (_) {
          token = null;
        }
        if (token != null && token.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (token != null && token.isNotEmpty && onToken != null) {
        await onToken(token);
        _tokenDelivered = true;
      }

      if (Platform.isIOS && !_tokenDelivered) {
        _startIosTokenRetry(onToken);
      }

      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        if (newToken.isNotEmpty && onToken != null) {
          await onToken(newToken);
          _tokenDelivered = true;
          _iosTokenRetryTimer?.cancel();
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
      await _ensureFirebaseReady();
      final messaging = FirebaseMessaging.instance;
      if (Platform.isIOS) {
        for (int i = 0; i < 8; i++) {
          try {
            final apns = await messaging.getAPNSToken();
            if (apns != null && apns.isNotEmpty) break;
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      return messaging.getToken();
    } catch (_) {
      return null;
    }
  }

  void _startIosTokenRetry(
    PushTokenCallback? onToken,
  ) {
    _iosTokenRetryTimer?.cancel();
    int attempts = 0;
    _iosTokenRetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      attempts++;
      try {
        final messaging = FirebaseMessaging.instance;
        final apns = await messaging.getAPNSToken();
        final token = await messaging.getToken();
        if (apns != null &&
            apns.isNotEmpty &&
            token != null &&
            token.isNotEmpty &&
            onToken != null) {
          await onToken(token);
          _tokenDelivered = true;
          timer.cancel();
          return;
        }
      } catch (_) {}

      if (attempts >= 36) {
        debugPrint('PUSH: iOS token retry timeout after $attempts attempts');
        timer.cancel();
      }
    });
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _onMessageOpenedSub?.cancel();
    await _onMessageSub?.cancel();
    _iosTokenRetryTimer?.cancel();
    _tokenRefreshSub = null;
    _onMessageOpenedSub = null;
    _onMessageSub = null;
    _iosTokenRetryTimer = null;
    _initialized = false;
    _tokenDelivered = false;
  }
}
