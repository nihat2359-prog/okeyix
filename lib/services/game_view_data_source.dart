import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ViewRow = Map<String, dynamic>;
typedef ViewRows = List<ViewRow>;

/// Public presentation data only. Never owns hands, deck, moves or money writes.
/// One instance belongs to one game screen and is shared with its avatar overlay.
class GameViewDataSource {
  final String tableId;
  final String? Function() currentUser;
  final Future<ViewRow?> Function() fetchTable;
  final Future<ViewRows> Function() fetchPlayers;
  final Future<ViewRows> Function(List<String>) fetchUsers, fetchProfiles;
  final Future<ViewRows> Function(String) fetchLeague;
  final Future<ViewRow> Function()? fetchSessionScore;
  final DateTime Function() now;
  late final _ReadSlot<ViewRow?> _table;
  late final _ReadSlot<ViewRows> _players;
  late final _ReadSlot<ViewRow> _sessionScore;
  final Map<String, _ReadSlot<ViewRows>> _users = {},
      _profiles = {},
      _leagues = {};
  String? _user;
  String? _memberKey;
  bool _disposed = false;
  String? _lastTableEvent, _lastPlayersEvent;
  StreamSubscription<AuthState>? _authSubscription;

  GameViewDataSource({
    required this.tableId,
    required this.currentUser,
    required this.fetchTable,
    required this.fetchPlayers,
    required this.fetchUsers,
    required this.fetchProfiles,
    required this.fetchLeague,
    this.fetchSessionScore,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    _user = currentUser();
    _sessionScore = _ReadSlot(
      fetchSessionScore ??
          () async => <String, dynamic>{'wins': 0, 'losses': 0},
      this.now,
      const Duration(milliseconds: 200),
    );
    _table = _ReadSlot(fetchTable, this.now, const Duration(milliseconds: 200));
    _players = _ReadSlot(
      fetchPlayers,
      this.now,
      const Duration(milliseconds: 200),
    );
  }

  // Only columns already consumed by these two UI layers; no select('*').
  static const tableColumns =
      'status,max_players,ready_since,last_finish_at,last_winner_user_id,chat_enabled,spectators_enabled,last_final_slots,last_finish_tile,last_win_amount,pot_amount,league_id,entry_coin,current_turn,turn_seconds,turn_started_at';

  factory GameViewDataSource.supabase(SupabaseClient client, String tableId) {
    ViewRows rows(dynamic data) =>
        (data as List).map((e) => ViewRow.from(e as Map)).toList();
    final source = GameViewDataSource(
      tableId: tableId,
      currentUser: () => client.auth.currentUser?.id,
      fetchSessionScore: () async => ViewRow.from(
        await client.rpc(
              'okeyix_my_table_score',
              params: {'p_table_id': tableId},
            )
            as Map,
      ),
      fetchTable: () async {
        try {
          return await client
              .from('tables')
              .select(tableColumns)
              .eq('id', tableId)
              .maybeSingle();
        } on PostgrestException catch (e) {
          if (e.code != '42703' || !e.message.contains('turn_seconds')) rethrow;
          return await client
              .from('tables')
              .select(tableColumns.replaceAll(',turn_seconds', ''))
              .eq('id', tableId)
              .maybeSingle();
        }
      },
      fetchPlayers: () async {
        try {
          return rows(
            await client
                .from('table_players')
                .select('seat_index,user_id,is_double_mode')
                .eq('table_id', tableId)
                .order('seat_index'),
          );
        } on PostgrestException catch (e) {
          if (e.code != '42703' || !e.message.contains('is_double_mode')) {
            rethrow;
          }
          return rows(
            await client
                .from('table_players')
                .select('seat_index,user_id')
                .eq('table_id', tableId)
                .order('seat_index'),
          );
        }
      },
      fetchUsers: (ids) async => rows(
        await client
            .from('users')
            .select('id,username,email,avatar_url')
            .inFilter('id', ids),
      ),
      fetchProfiles: (ids) async => rows(
        await client
            .from('profiles')
            .select('id,username,coins')
            .inFilter('id', ids),
      ),
      fetchLeague: (id) async => rows(
        await client
            .from('leagues')
            .select('turn_seconds')
            .eq('id', id)
            .limit(1),
      ),
    );
    source._authSubscription = client.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user.id;
      if (!source._disposed && source._user != user) {
        source.invalidateAll();
        source._user = user;
      }
    });
    return source;
  }

  Future<T> _guard<T>(Future<T> Function() read) async {
    if (_disposed) throw StateError('Game view disposed');
    final user = currentUser();
    if (user != _user) {
      invalidateAll();
      _user = user;
    }
    final result = await read();
    if (_disposed || user != currentUser()) {
      throw StateError('Game view session changed');
    }
    return result;
  }

  Future<ViewRow?> table() => _guard(() => _table.read());
  Future<ViewRow> sessionScore() => _guard(() => _sessionScore.read());
  Future<ViewRows> players() => _guard(() async {
    final result = await _players.read();
    final key = _key(
      result.map((e) => e['user_id']?.toString()).whereType<String>().toList(),
    );
    if (_memberKey != key) {
      _clear(_users);
      _clear(_profiles);
      _memberKey = key;
    }
    return result;
  });
  Future<ViewRows> users(List<String> ids) => _guard(
    () => ids.isEmpty
        ? Future.value(<ViewRow>[])
        : _users
              .putIfAbsent(
                _key(ids),
                () => _ReadSlot(
                  () => fetchUsers(List.of(ids)),
                  now,
                  const Duration(seconds: 60),
                ),
              )
              .read(),
  );
  // Coins remain short-lived, matching the existing periodic refresh behavior.
  Future<ViewRows> profiles(List<String> ids) => _guard(
    () => ids.isEmpty
        ? Future.value(<ViewRow>[])
        : _profiles
              .putIfAbsent(
                _key(ids),
                () => _ReadSlot(
                  () => fetchProfiles(List.of(ids)),
                  now,
                  const Duration(milliseconds: 200),
                ),
              )
              .read(),
  );
  Future<ViewRows> league(String id) => _guard(
    () => _leagues
        .putIfAbsent(
          id,
          () =>
              _ReadSlot(() => fetchLeague(id), now, const Duration(minutes: 5)),
        )
        .read(),
  );
  static String _key(List<String> ids) =>
      (ids.toSet().toList()..sort()).join('|');

  bool matchesMembers(List<String> ids) =>
      !_disposed && _user == currentUser() && _memberKey == _key(ids);

  // Payloads may be partial and may contain private columns. Invalidate and
  // re-read the explicit public projection instead of distributing the payload.
  void tableChanged([String? eventToken]) {
    if (eventToken != null && eventToken == _lastTableEvent) return;
    _lastTableEvent = eventToken;
    _table.invalidate();
  }

  void playersChanged([String? eventToken]) {
    if (eventToken != null && eventToken == _lastPlayersEvent) return;
    _lastPlayersEvent = eventToken;
    _players.invalidate();
  }

  void invalidateAll() {
    _sessionScore.invalidate();
    _table.invalidate();
    _players.invalidate();
    _clear(_users);
    _clear(_profiles);
    _clear(_leagues);
    _memberKey = null;
    _lastTableEvent = null;
    _lastPlayersEvent = null;
  }

  void _clear(Map<String, _ReadSlot<ViewRows>> entries) {
    for (final entry in entries.values) {
      entry.dispose();
    }
    entries.clear();
  }

  void dispose() {
    _disposed = true;
    _sessionScore.dispose();
    _authSubscription?.cancel();
    _table.dispose();
    _players.dispose();
    _clear(_users);
    _clear(_profiles);
    _clear(_leagues);
  }
}

/// Serializes refreshes. Events arriving during a request force reconciliation
/// before publishing. A continuous event burst yields to the next polling tick.
class _ReadSlot<T> {
  final Future<T> Function() fetch;
  final DateTime Function() now;
  final Duration ttl;
  Future<T>? _pending;
  T? _value;
  DateTime? _at;
  int _version = 0;
  bool _disposed = false;
  _ReadSlot(this.fetch, this.now, this.ttl);
  void invalidate() {
    _version++;
    _at = null;
    _value = null;
  }

  void dispose() {
    _disposed = true;
    invalidate();
    _value = null;
  }

  Future<T> read() {
    if (_disposed) return Future.error(StateError('Read disposed'));
    if (_pending != null) return _pending!;
    if (_at != null && now().difference(_at!) < ttl) {
      return Future.value(_value as T);
    }
    return _pending = _refresh().whenComplete(() => _pending = null);
  }

  Future<T> _refresh() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final version = _version;
      final result = await fetch();
      if (_disposed) throw StateError('Read disposed');
      if (version != _version) continue;
      _value = result;
      _at = now();
      return result;
    }
    throw StateError('Read superseded; reconcile on next tick');
  }
}

/// Coalesces a burst of UI refresh requests, with one trailing reconciliation.
/// Polling remains the eventual fallback if events continue throughout both runs.
class CoalescedViewRefresh {
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;
  Future<void> run(Future<void> Function() action) {
    if (_disposed) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _drain(action).whenComplete(() => _running = null);
  }

  Future<void> _drain(Future<void> Function() action) async {
    for (var i = 0; i < 2 && !_disposed; i++) {
      _again = false;
      await action();
      if (!_again) return;
    }
  }

  void dispose() {
    _disposed = true;
    _again = false;
  }
}
