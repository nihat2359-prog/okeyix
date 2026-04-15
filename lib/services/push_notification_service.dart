import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // Ignore init failures in background isolate.
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (e) {
      debugPrint('PUSH INIT ERROR (Firebase.initializeApp): $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('PUSH PERMISSION: ${settings.authorizationStatus}');

    final token = await messaging.getToken();
    await _saveTokenToSupabase(token);

    messaging.onTokenRefresh.listen((newToken) async {
      await _saveTokenToSupabase(newToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('PUSH FOREGROUND MESSAGE: ${message.messageId}');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('PUSH OPENED APP: ${message.messageId}');
    });

    _initialized = true;
  }

  Future<void> _saveTokenToSupabase(String? token) async {
    if (token == null || token.isEmpty) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('users').upsert({
        'id': user.id,
        'email': user.email,
        'push_token': token,
        'push_platform': defaultTargetPlatform.name,
        'push_token_updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('PUSH TOKEN SAVED');
    } catch (e) {
      debugPrint('PUSH TOKEN SAVE ERROR: $e');
    }
  }
}
