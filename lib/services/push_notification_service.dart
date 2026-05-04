import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:okeyix/firebase_options.dart';

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
      await messaging.setAutoInitEnabled(true);
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

      String? apnsForDiag;
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
        apnsForDiag = apns;
        await onDebug?.call(
          'PUSH: APNS token ${apns == null ? "YOK (bekleniyor)" : "VAR"}',
        );
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
      await onDebug?.call('PUSH: FCM token ${token == null ? "YOK" : "VAR"}');
      if (token != null && token.isNotEmpty && onToken != null) {
        await onToken(token);
        _tokenDelivered = true;
        await onDebug?.call('PUSH: Token server kaydi tetiklendi');
      }
      await onDebug?.call(
        'PUSH_DIAG auth=${permission.authorizationStatus.name} '
        'apns=${(apnsForDiag != null && apnsForDiag.isNotEmpty) ? "VAR" : "YOK"} '
        'fcm=${(token != null && token.isNotEmpty) ? "VAR" : "YOK"}',
      );

      if (Platform.isIOS && !_tokenDelivered) {
        _startIosTokenRetry(onToken, onDebug);
      }

      _tokenRefreshSub = messaging.onTokenRefresh.listen((newToken) async {
        if (newToken.isNotEmpty && onToken != null) {
          await onToken(newToken);
          _tokenDelivered = true;
          _iosTokenRetryTimer?.cancel();
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
    PushDebugCallback? onDebug,
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
          await onDebug?.call('PUSH_DIAG auth=authorized apns=VAR fcm=VAR retry=OK');
          await onDebug?.call('PUSH: iOS retry ile token alindi');
          timer.cancel();
          return;
        }
      } catch (_) {}

      if (attempts % 6 == 0) {
        await onDebug?.call('PUSH: iOS token bekleniyor (retry $attempts)');
      }
      if (attempts >= 36) {
        await onDebug?.call('PUSH_DIAG auth=authorized apns=YOK fcm=YOK retry=TIMEOUT');
        await onDebug?.call('PUSH: iOS token retry zaman asimi');
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
