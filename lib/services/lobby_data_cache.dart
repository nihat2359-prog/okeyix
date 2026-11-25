import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Presentation cache only. Server checks still decide bans and game access.
class LobbyDataCache {
  static SharedPreferences? _prefs;
  static Future<void>? _initializing;
  static final Map<String, Future<List<dynamic>>> _profileReads = {};
  static Future<List<Map<String, dynamic>>>? _leagueRead;

  static Future<void> initialize() => _initializing ??= () async {
    _prefs = await SharedPreferences.getInstance();
  }();

  static Map<String, dynamic>? profile(String userId) {
    try {
      final raw = _prefs?.getString('lobby.profile.v1.$userId');
      if (raw == null) return null;
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (data['row'] is! Map || data['profile'] is! Map) return null;
      if ((data['row'] as Map)['id'] != userId) return null;
      final p = data['profile'] as Map;
      if (p['coins'] is! num || p['rating'] is! num) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> get leagues {
    try {
      final raw = _prefs?.getString('lobby.leagues.v1');
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveProfile(
    String uid,
    Map<String, dynamic> row,
    Map<String, dynamic> profile,
  ) async {
    try {
      await initialize();
      await _prefs!.setString(
        'lobby.profile.v1.$uid',
        jsonEncode({'row': row, 'profile': profile}),
      );
    } catch (_) {
      /* A storage failure must not discard a fresh server result. */
    }
  }

  static Future<List<dynamic>> refreshProfile(
    SupabaseClient client,
    String uid,
  ) {
    return _profileReads.putIfAbsent(uid, () async {
      try {
        final results = await Future.wait<dynamic>([
          client
              .from('users')
              .select(
                'id,username,avatar_url,wins,losses,is_banned,ban_reason,ban_until',
              )
              .eq('id', uid)
              .limit(1),
          client
              .from('profiles')
              .select('coins,rating,allow_game_invites')
              .eq('id', uid)
              .limit(1),
        ]);
        final users = results[0] as List;
        final profiles = results[1] as List;
        final row = users.isEmpty
            ? null
            : Map<String, dynamic>.from(users.first);
        if (row != null && profiles.isNotEmpty) {
          await saveProfile(
            uid,
            row,
            Map<String, dynamic>.from(profiles.first),
          );
        }
        return [row, profiles];
      } finally {
        _profileReads.remove(uid);
      }
    });
  }

  static Future<List<Map<String, dynamic>>> refreshLeagues(
    SupabaseClient client,
  ) {
    return _leagueRead ??= () async {
      try {
        final rows = await client
            .from('leagues')
            .select()
            .order('display_order', ascending: true);
        final result = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        try {
          await initialize();
          await _prefs!.setString('lobby.leagues.v1', jsonEncode(result));
        } catch (_) {
          /* Keep fresh leagues if local storage is unavailable. */
        }
        return result;
      } finally {
        _leagueRead = null;
      }
    }();
  }

  /// Timeout releases navigation, without cancelling the background refresh.
  static Future<void> prepare(SupabaseClient client, String uid) async {
    await Future.wait<void>([
          initialize(),
          refreshProfile(
            client,
            uid,
          ).then<void>((_) {}, onError: (Object _) {}),
          refreshLeagues(client).then<void>((_) {}, onError: (Object _) {}),
        ])
        .then<void>((_) {})
        .timeout(const Duration(milliseconds: 1200), onTimeout: () {});
  }
}
