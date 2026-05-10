import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class DebugEventService {
  DebugEventService._();

  static final Map<String, DateTime> _lastByKey = <String, DateTime>{};

  static void log({
    required String tag,
    String? tableId,
    String? userId,
    Map<String, dynamic>? data,
  }) {
    unawaited(
      _insert(tag: tag, tableId: tableId, userId: userId, data: data),
    );
  }

  static void logThrottled({
    required String key,
    required String tag,
    String? tableId,
    String? userId,
    Map<String, dynamic>? data,
    Duration minInterval = const Duration(seconds: 3),
  }) {
    final now = DateTime.now();
    final last = _lastByKey[key];
    if (last != null && now.difference(last) < minInterval) {
      return;
    }
    _lastByKey[key] = now;
    log(tag: tag, tableId: tableId, userId: userId, data: data);
  }

  static Future<void> _insert({
    required String tag,
    String? tableId,
    String? userId,
    Map<String, dynamic>? data,
  }) async {
    try {
      final client = Supabase.instance.client;
      final currentUserId = userId ?? client.auth.currentUser?.id;
      await client.from('debug_events').insert({
        'tag': tag,
        'table_id': tableId,
        'user_id': currentUserId,
        'payload': data ?? const <String, dynamic>{},
        'client_ts': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Best effort telemetry: never crash gameplay.
    }
  }
}

