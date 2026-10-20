import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Authenticated APIs derive the player from the JWT, never from a supplied ID.
class FriendInviteService {
  FriendInviteService({SupabaseClient? client, MethodChannel? channel})
    : _client = client ?? Supabase.instance.client,
      _channel =
          channel ?? const MethodChannel('com.okeyix.game/comparison_share');
  final SupabaseClient _client;
  final MethodChannel _channel;

  Future<Map<String, dynamic>> dashboard() async => Map<String, dynamic>.from(
    await _client.rpc('okeyix_invite_dashboard') as Map,
  );
  Future<List<Map<String, dynamic>>> friends({
    Map<String, dynamic>? before,
  }) async {
    final result = await _client.rpc(
      'okeyix_invited_friends',
      params: {
        'p_before_at': before?['accepted_at'],
        'p_before_id': before?['id'],
      },
    );
    return (result as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<String> redeem(String code) async {
    final result = await _client.rpc(
      'okeyix_redeem_invite',
      params: {'p_code': code.trim().toUpperCase()},
    );
    return (result as Map)['status'] as String;
  }

  Future<void> shareWhatsApp(String message, Rect origin) =>
      _channel.invokeMethod<void>('shareInviteWhatsApp', {
        'text': message,
        'x': origin.left,
        'y': origin.top,
        'width': origin.width,
        'height': origin.height,
      });
}
