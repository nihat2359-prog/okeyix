import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _heartbeatTimer;
  String? _activeUserId;
  bool _started = false;
  bool _isOnline = false;

  Future<void> startForCurrentUser() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;

    _activeUserId = uid;
    _started = true;
    await _setPresence(isOnline: true, userId: uid);
    _startHeartbeat();
  }

  Future<void> stopForCurrentUser() async {
    final uid = _activeUserId ?? _supabase.auth.currentUser?.id;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _started = false;
    if (uid != null && uid.isNotEmpty) {
      await _setPresence(isOnline: false, userId: uid);
    }
    _activeUserId = null;
  }

  Future<void> onAppResumed() async {
    if (!_started) {
      await startForCurrentUser();
      return;
    }
    final uid = _activeUserId ?? _supabase.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    await _setPresence(isOnline: true, userId: uid);
    _startHeartbeat();
  }

  Future<void> onAppBackgrounded() async {
    final uid = _activeUserId ?? _supabase.auth.currentUser?.id;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (uid == null || uid.isEmpty) return;
    await _setPresence(isOnline: false, userId: uid);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      final uid = _activeUserId ?? _supabase.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return;
      if (!_isOnline) return;
      await _touchLastSeen(userId: uid);
    });
  }

  Future<void> _setPresence({
    required bool isOnline,
    required String userId,
  }) async {
    _isOnline = isOnline;
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'is_online': isOnline,
      'last_seen_at': now,
    };

    try {
      await _supabase.from('profiles').update(payload).eq('id', userId);
    } catch (_) {}
  }

  Future<void> _touchLastSeen({required String userId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await _supabase
          .from('profiles')
          .update({'last_seen_at': now}).eq('id', userId);
    } catch (_) {}
  }
}
