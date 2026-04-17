import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player_model.dart';
import 'avatar_card.dart';
import 'avatar_preset.dart';

class GameAvatarOverlay extends StatefulWidget {
  final String tableId;
  final double topInset;

  const GameAvatarOverlay({
    super.key,
    required this.tableId,
    this.topInset = 0,
  });

  @override
  State<GameAvatarOverlay> createState() => _GameAvatarOverlayState();
}

class _GameAvatarOverlayState extends State<GameAvatarOverlay> {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _localCoinFloor = 50000;

  List<_SeatPlayer> players = [];
  RealtimeChannel? _tablePlayersChannel;
  RealtimeChannel? _tableChannel;
  Timer? _pollTimer;

  String? _myUserId;
  int? _mySeatIndex;
  int _tableSize = 2;
  String _tableStatus = 'waiting';
  String? _leagueId;
  int _entryCoin = 100;
  int _currentTurnSeat = 0;
  int _turnSeconds = 15;
  int _lastSeenTurnSeat = -1;
  DateTime? _turnStartedAt;
  Timer? _tickerTimer;
  bool _hasLoadedPlayersOnce = false;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
    _subscribeTablePlayers();
    _subscribeTable();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadPlayers(),
    );
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tablePlayersChannel?.unsubscribe();
    _tableChannel?.unsubscribe();
    _pollTimer?.cancel();
    _tickerTimer?.cancel();
    _tablePlayersChannel = null;
    _tableChannel = null;
    _pollTimer = null;
    _tickerTimer = null;
    super.dispose();
  }

  void _subscribeTablePlayers() {
    _tablePlayersChannel?.unsubscribe();
    _tablePlayersChannel = _supabase
        .channel('avatar_overlay_${widget.tableId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'table_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: widget.tableId,
          ),
          callback: (_) async => _loadPlayers(),
        )
        .subscribe();
  }

  void _subscribeTable() {
    _tableChannel?.unsubscribe();
    _tableChannel = _supabase
        .channel('avatar_overlay_table_${widget.tableId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tables',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.tableId,
          ),
          callback: (payload) async {
            final nextTurnRaw = payload.newRecord['current_turn'];
            final nextTurn = int.tryParse('$nextTurnRaw');
            final nextTurnStartedAt = _parseServerTime(
              payload.newRecord['turn_started_at'],
            );
            if (nextTurn != null && nextTurn != _lastSeenTurnSeat) {
              _lastSeenTurnSeat = nextTurn;
              _currentTurnSeat = nextTurn;
              _turnStartedAt = nextTurnStartedAt ?? DateTime.now();
              if (mounted) setState(() {});
            }
            await _loadPlayers();
          },
        )
        .subscribe();
  }

  Future<void> _loadPlayers() async {
    try {
      _myUserId = _supabase.auth.currentUser?.id;

      Map<String, dynamic> table;
      try {
        final row = await _supabase
            .from('tables')
            .select(
              'max_players, league_id, entry_coin, status, current_turn, turn_seconds, turn_started_at',
            )
            .eq('id', widget.tableId)
            .maybeSingle();
        if (row == null) return;
        table = Map<String, dynamic>.from(row);
      } catch (_) {
        final row = await _supabase
            .from('tables')
            .select(
              'max_players, league_id, entry_coin, status, current_turn, turn_started_at',
            )
            .eq('id', widget.tableId)
            .maybeSingle();
        if (row == null) return;
        table = Map<String, dynamic>.from(row);
      }

      _tableSize = (table['max_players'] as int?) ?? 2;
      _tableStatus = table['status']?.toString() ?? 'waiting';
      final turn = (table['current_turn'] as int?) ?? 0;
      final serverTurnStartedAt = _parseServerTime(table['turn_started_at']);
      if (turn != _lastSeenTurnSeat) {
        _lastSeenTurnSeat = turn;
        _turnStartedAt = serverTurnStartedAt ?? DateTime.now();
      }
      if (serverTurnStartedAt != null) {
        final currentStart = _turnStartedAt;
        if (currentStart == null ||
            (serverTurnStartedAt.difference(currentStart).inMilliseconds)
                    .abs() >
                3000) {
          _turnStartedAt = serverTurnStartedAt;
        }
      }
      _currentTurnSeat = turn;
      _turnStartedAt ??= serverTurnStartedAt ?? DateTime.now();
      _leagueId = table['league_id']?.toString();
      _entryCoin = (table['entry_coin'] as int?) ?? 100;
      final tableTurnSeconds = table['turn_seconds'] as int?;
      if (_leagueId != null) {
        try {
          final league = await _supabase
              .from('leagues')
              .select('turn_seconds')
              .eq('id', _leagueId!)
              .limit(1);
          if ((league as List).isNotEmpty) {
            _turnSeconds =
                (league.first['turn_seconds'] as int?) ?? _turnSeconds;
          }
        } catch (_) {}
      }
      if (tableTurnSeconds != null && tableTurnSeconds > 0) {
        _turnSeconds = tableTurnSeconds;
      }
      _turnSeconds = _normalizeTurnSeconds(_turnSeconds);

      dynamic rows;
      try {
        rows = await _supabase
            .from('table_players')
            .select('seat_index, user_id, is_double_mode')
            .eq('table_id', widget.tableId)
            .order('seat_index', ascending: true);
      } catch (_) {
        rows = await _supabase
            .from('table_players')
            .select('seat_index, user_id')
            .eq('table_id', widget.tableId)
            .order('seat_index', ascending: true);
      }

      final playerRows = (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      final userIds = playerRows
          .map((row) => row['user_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final profiles = await _loadProfilesByUserId(userIds);
      final users = await _loadUsersByUserId(userIds);
      final walletByUserId = await _loadWalletBalancesByUserId(userIds);
      await _hydrateCurrentUserFallback(users);

      final mapped = playerRows
          .map(
            (row) => _seatPlayerFromRow(row, profiles, users, walletByUserId),
          )
          .whereType<_SeatPlayer>()
          .toList();

      final mySeat = mapped
          .where((p) => p.player.id == _myUserId)
          .map((p) => p.seatIndex)
          .cast<int?>()
          .firstWhere((v) => v != null, orElse: () => null);

      if (!mounted) return;
      final previousIds = players.map((p) => p.player.id).toSet();
      final joinedPlayers = _hasLoadedPlayersOnce
          ? mapped.where((p) => !previousIds.contains(p.player.id)).toList()
          : const <_SeatPlayer>[];

      setState(() {
        players = mapped;
        _mySeatIndex = mySeat;
        _hasLoadedPlayersOnce = true;
      });

      _showJoinedPlayersSnack(joinedPlayers);
    } catch (e) {
      debugPrint('OVERLAY ERROR: $e');
    }
  }

  void _showJoinedPlayersSnack(List<_SeatPlayer> joinedPlayers) {
    if (!mounted || joinedPlayers.isEmpty) return;

    final names = joinedPlayers
        .map((p) => p.player.name.trim())
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) return;

    final message = names.length == 1
        ? '${names.first} masaya katıldı'
        : '${names.length} oyuncu masaya katıldı: ${names.join(', ')}';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  Future<Map<String, Map<String, dynamic>>> _loadProfilesByUserId(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    try {
      final rows = await _supabase
          .from('profiles')
          .select('id, username, coins')
          .inFilter('id', userIds);

      return (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => row['id'] != null)
          .fold<Map<String, Map<String, dynamic>>>({}, (acc, row) {
            acc[row['id'].toString()] = row;
            return acc;
          });
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadUsersByUserId(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};

    try {
      final rows = await _supabase
          .from('users')
          .select('id, username, email, avatar_url')
          .inFilter('id', userIds);

      return (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => row['id'] != null)
          .fold<Map<String, Map<String, dynamic>>>({}, (acc, row) {
            acc[row['id'].toString()] = row;
            return acc;
          });
    } catch (e) {
      debugPrint('USERS LOAD ERROR: $e');
      return {};
    }
  }

  Future<void> _hydrateCurrentUserFallback(
    Map<String, Map<String, dynamic>> usersByUserId,
  ) async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;
    if (usersByUserId.containsKey(currentUser.id)) return;

    final email = currentUser.email?.trim();
    if (email == null || email.isEmpty) return;

    try {
      final row = await _supabase
          .from('users')
          .select('id, username, email, avatar_url')
          .eq('email', email)
          .maybeSingle();

      if (row is Map<String, dynamic>) {
        usersByUserId[currentUser.id] = row;
      }
    } catch (e) {
      debugPrint('USERS EMAIL FALLBACK ERROR: $e');
    }
  }

  _SeatPlayer? _seatPlayerFromRow(
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> profileByUserId,
    Map<String, Map<String, dynamic>> usersByUserId,
    Map<String, int> walletByUserId,
  ) {
    final seatIndex = row['seat_index'] as int?;
    final userId = row['user_id']?.toString();
    if (seatIndex == null || userId == null || userId.isEmpty) {
      return null;
    }

    final profile = profileByUserId[userId];
    final user = usersByUserId[userId];

    final username = user?['username']?.toString().trim().isNotEmpty == true
        ? user!['username'].toString().trim()
        : (profile?['username']?.toString().trim().isNotEmpty == true
              ? profile!['username'].toString().trim()
              : 'Oyuncu ${seatIndex + 1}');

    final profileCoinsRaw = profile?['coins'];
    final profileCoins = profileCoinsRaw is int
        ? profileCoinsRaw
        : int.tryParse('$profileCoinsRaw') ?? 0;
    final walletCoins = walletByUserId[userId] ?? 0;
    int coins = profileCoins > walletCoins ? profileCoins : walletCoins;
    if (coins <= 0) {
      final opponentFloor = _entryCoin > 0 ? _entryCoin : 100;
      coins = userId == _myUserId ? _localCoinFloor : opponentFloor;
    }
    final profileRatingRaw = profile?['rating'];
    final profileRating = profileRatingRaw is int
        ? profileRatingRaw
        : int.tryParse('$profileRatingRaw') ?? 0;
    final rating = profileRating > 0 ? profileRating : 1200;

    final avatarRaw = (user?['avatar_url'] ?? profile?['avatar_url'])
        ?.toString();
    final isDoubleMode = row['is_double_mode'] == true;

    return _SeatPlayer(
      seatIndex: seatIndex,
      player: PlayerModel(
        id: userId,
        name: username,
        avatarPath: _resolveAvatarPath(avatarRaw, seatIndex),
        coins: coins,
        rating: rating,
        isDoubleMode: isDoubleMode,
        isActive: _tableStatus == 'playing' && seatIndex == _currentTurnSeat,
        remainingTime:
            (_tableStatus == 'playing' && seatIndex == _currentTurnSeat)
            ? _normalizedRemainingForRing()
            : 15.0,
      ),
    );
  }

  Future<Map<String, int>> _loadWalletBalancesByUserId(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return {};
    try {
      final rows = await _supabase
          .from('wallet_transactions')
          .select('user_id, amount')
          .inFilter('user_id', userIds);

      final balances = <String, int>{};
      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final userId = row['user_id']?.toString();
        if (userId == null || userId.isEmpty) continue;
        final amountRaw = row['amount'];
        final amount = amountRaw is int
            ? amountRaw
            : int.tryParse('$amountRaw') ?? 0;
        balances[userId] = (balances[userId] ?? 0) + amount;
      }
      return balances;
    } catch (_) {
      return {};
    }
  }

  double _remainingTurnSeconds() {
    if (_turnStartedAt == null) return _turnSeconds.toDouble();
    final elapsed =
        DateTime.now().difference(_turnStartedAt!).inMilliseconds / 1000.0;
    final remain = _turnSeconds - elapsed;
    if (remain < 0) return 0;
    return remain;
  }

  double _normalizedRemainingForRing() {
    if (_turnSeconds <= 0) return 0;
    final remain = _remainingTurnSeconds();
    return (remain / _turnSeconds) * 15.0;
  }

  int _normalizeTurnSeconds(int value) {
    if (value <= 0) return 15;
    if (value < 5) return 5;
    if (value > 60) return 60;
    return value;
  }

  DateTime? _parseServerTime(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return null;
    return parsed.toLocal();
  }

  String _resolveAvatarPath(String? avatarUrl, int seatIndex) {
    final normalized = avatarUrl?.trim();
    if (normalized != null && normalized.isNotEmpty) return normalized;
    return defaultAvatarPresetForSeat(seatIndex);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bySeat = <int, _SeatPlayer>{for (final p in players) p.seatIndex: p};
    final useDuelLayout = players.length <= 2;

    final items = <Widget>[];
    if (useDuelLayout) {
      final me = players
          .where((p) => p.player.id == _myUserId)
          .cast<_SeatPlayer?>()
          .firstWhere((p) => p != null, orElse: () => null);
      final opponent = players
          .where((p) => p.player.id != _myUserId)
          .cast<_SeatPlayer?>()
          .firstWhere((p) => p != null, orElse: () => null);

      if (me != null) {
        items.add(
          _buildPositionedSeat(
            size: size,
            relativeSeat: 0,
            child: AvatarCard(
              player: me.player,
              position: AvatarPosition.bottom,
            ),
          ),
        );
      }

      items.add(
        _buildPositionedSeat(
          size: size,
          relativeSeat: 1,
          child: opponent != null
              ? AvatarCard(
                  player: opponent.player,
                  position: AvatarPosition.top,
                )
              : (_tableStatus == 'playing'
                    ? const SizedBox.shrink()
                    : _InviteSeatCard(
                        vertical: false,
                        onInvite: () => _showInviteDialogForSeat(1),
                      )),
        ),
      );

      return Stack(children: items);
    }

    for (int absoluteSeat = 0; absoluteSeat < _tableSize; absoluteSeat++) {
      final relativeSeat = _relativeSeat(absoluteSeat);
      final occupied = bySeat[absoluteSeat];

      items.add(
        _buildPositionedSeat(
          size: size,
          relativeSeat: relativeSeat,
          child: occupied != null
              ? AvatarCard(
                  player: occupied.player,
                  position: _avatarPositionFor(relativeSeat),
                )
              : (_tableStatus == 'playing'
                    ? const SizedBox.shrink()
                    : _InviteSeatCard(
                        vertical: _isSideSeat(relativeSeat),
                        onInvite: () => _showInviteDialogForSeat(absoluteSeat),
                      )),
        ),
      );
    }

    return Stack(children: items);
  }

  int _relativeSeat(int absoluteSeat) {
    final base = _mySeatIndex ?? 0;
    return (absoluteSeat - base + _tableSize) % _tableSize;
  }

  AvatarPosition _avatarPositionFor(int relativeSeat) {
    if (relativeSeat == 0) return AvatarPosition.bottom;
    if (relativeSeat == 2 || (_tableSize == 2 && relativeSeat == 1)) {
      return AvatarPosition.top;
    }
    return relativeSeat == 1 ? AvatarPosition.left : AvatarPosition.right;
  }

  bool _isSideSeat(int relativeSeat) {
    if (_tableSize == 2) return false;
    return relativeSeat == 1 || relativeSeat == 3;
  }

  Widget _buildPositionedSeat({
    required Size size,
    required int relativeSeat,
    required Widget child,
  }) {
    switch (relativeSeat) {
      case 0:
        return Positioned(
          left: 0,
          right: 0,
          bottom: 185,
          child: Center(child: child),
        );
      case 1:
        if (_tableSize == 2) {
          return Positioned(
            left: 0,
            right: 0,
            top: 26 + widget.topInset,
            child: Center(child: child),
          );
        }
        return Positioned(left: 20, top: size.height * 0.32, child: child);
      case 2:
        return Positioned(
          left: 0,
          right: 0,
          top: 52 + widget.topInset,
          child: Center(child: child),
        );
      case 3:
        return Positioned(right: 20, top: size.height * 0.32, child: child);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _showInviteDialogForSeat(int seatIndex) async {
    final candidates = await _loadEligiblePlayers();

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(.75),
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF0F1B17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFB9932F), width: 1.4),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: MediaQuery.of(context).size.height * 0.78,
            ),
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Oyuncu Davet Et",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE7C66A),
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        "Bu lig iÃ§in uygun ve aktif oyuncu bulunamadÄ±.",
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        itemCount: candidates.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white10),
                        itemBuilder: (_, i) {
                          final p = candidates[i];
                          final name = p['username']?.toString() ?? "Oyuncu";
                          final rating = p['rating']?.toString() ?? "-";
                          final coins = p['coins']?.toString() ?? "0";
                          final userId = p['id']?.toString();
                          final avatarUrl = p['avatar_url'];

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: const Color(0xFF1F3D32),
                                  backgroundImage: avatarUrl != null &&
                                          avatarUrl.toString().isNotEmpty
                                      ? NetworkImage(avatarUrl.toString())
                                      : null,
                                  child: avatarUrl == null ||
                                          avatarUrl.toString().isEmpty
                                      ? Text(
                                          name.substring(0, 1).toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Rating $rating â€¢ $coins coin",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white60,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFB9932F),
                                    foregroundColor: Colors.black,
                                    visualDensity: VisualDensity.compact,
                                    minimumSize: const Size(72, 34),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: userId == null
                                      ? null
                                      : () async {
                                          await _sendInvite(userId: userId, isBot: p['is_bot'] == true);
                                          if (!mounted) return;
                                          Navigator.pop(context);
                                        },
                                  child: const Text("Davet"),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadEligiblePlayers() async {
    final myUserId = _myUserId;
    final leagueId = _leagueId;
    if (myUserId == null || leagueId == null) return [];
    try {
      final tablePlayers = await _supabase
          .from('table_players')
          .select('user_id')
          .eq('table_id', widget.tableId);
      final excludedIds = (tablePlayers as List)
          .map((r) => (r as Map)['user_id']?.toString())
          .whereType<String>()
          .toSet();
      excludedIds.add(myUserId);

      final pendingInvites = await _supabase
          .from('table_invites')
          .select('to_user')
          .eq('table_id', widget.tableId)
          .eq('status', 'pending');
      for (final raw in (pendingInvites as List)) {
        final uid = (raw as Map)['to_user']?.toString();
        if (uid != null && uid.isNotEmpty) excludedIds.add(uid);
      }

      int minRating = 0;
      try {
        final league = await _supabase
            .from('leagues')
            .select('min_rating')
            .eq('id', leagueId)
            .maybeSingle();
        minRating = (league?['min_rating'] as int?) ?? 0;
      } catch (_) {}

      final activeTables = await _supabase
          .from('tables')
          .select('id')
          .inFilter('status', ['waiting', 'playing']);
      final activeTableIds = (activeTables as List)
          .map((r) => (r as Map)['id']?.toString())
          .whereType<String>()
          .toList();
      if (activeTableIds.isEmpty) return [];

      final activePlayers = await _supabase
          .from('table_players')
          .select('user_id')
          .inFilter('table_id', activeTableIds);
      final activeUserIds = (activePlayers as List)
          .map((r) => (r as Map)['user_id']?.toString())
          .whereType<String>()
          .toSet();
      if (activeUserIds.isEmpty) return [];

      final profileRows = await _supabase
          .from('profiles')
          .select('id, username, rating, coins, avatar')
          .inFilter('id', activeUserIds.toList())
          .gte('rating', minRating)
          .gte('coins', _entryCoin)
          .limit(80);

      final userRows = await _supabase
          .from('users')
          .select('id, avatar_url')
          .inFilter('id', activeUserIds.toList());
      final avatarById = <String, String?>{};
      for (final raw in (userRows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id == null) continue;
        avatarById[id] = row['avatar_url']?.toString();
      }

      final regular = (profileRows as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .where((p) {
            final id = p['id']?.toString();
            return id != null && !excludedIds.contains(id);
          })
          .map((p) {
            final id = p['id']?.toString();
            if (id != null) {
              p['avatar_url'] = avatarById[id] ?? p['avatar']?.toString();
            }
            return p;
          })
          .toList();

      regular.sort((a, b) {
        final ar = (a['rating'] as int?) ?? 0;
        final br = (b['rating'] as int?) ?? 0;
        return br.compareTo(ar);
      });

      final bots = <Map<String, dynamic>>[];
      try {
        final botRows = await _supabase
            .from('users')
            .select('id, username, avatar_url, is_bot')
            .eq('is_bot', true)
            .limit(30);
        final botIds = (botRows as List)
            .map((r) => (r as Map)['id']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();
        final botRatingById = <String, int>{};
        if (botIds.isNotEmpty) {
          final botProfiles = await _supabase
              .from('profiles')
              .select('id,rating')
              .inFilter('id', botIds);
          for (final raw in (botProfiles as List)) {
            final row = Map<String, dynamic>.from(raw as Map);
            final id = row['id']?.toString();
            if (id == null || id.isEmpty) continue;
            botRatingById[id] = (row['rating'] as int?) ?? 1200;
          }
        }
        for (final raw in (botRows as List)) {
          final row = Map<String, dynamic>.from(raw as Map);
          final id = row['id']?.toString();
          if (id == null || id.isEmpty || excludedIds.contains(id)) continue;
          final rating = botRatingById[id] ?? 1200;
          if (rating < minRating) continue;
          bots.add({
            'id': id,
            'username': row['username'] ?? 'Standart Bot',
            'rating': rating,
            'coins': 999999,
            'avatar_url': row['avatar_url']?.toString(),
            'is_bot': true,
          });
          if (bots.length >= 5) break;
        }
      } catch (_) {}

      return [...bots, ...regular];
    } catch (e) {
      debugPrint('ELIGIBLE PLAYERS ERROR: $e');
      return [];
    }
  }
  Future<void> _sendInvite({required String userId, bool isBot = false}) async {
    final myUserId = _myUserId;
    if (myUserId == null) return;
    try {
      if (isBot) {
        final seatRows = await _supabase
            .from('table_players')
            .select('seat_index')
            .eq('table_id', widget.tableId);
        final used = (seatRows as List)
            .map((r) => (r as Map)['seat_index'] as int?)
            .whereType<int>()
            .toSet();
        int? freeSeat;
        for (int i = 0; i < _tableSize; i++) {
          if (!used.contains(i)) {
            freeSeat = i;
            break;
          }
        }
        if (freeSeat == null) {
          throw Exception('Masa dolu');
        }
        await _supabase.from('table_players').insert({
          'table_id': widget.tableId,
          'user_id': userId,
          'seat_index': freeSeat,
          'hand': <dynamic>[],
        });
        if (!mounted) return;
        await _loadPlayers();
        return;
      }
      await _supabase.from('table_invites').insert({
        'table_id': widget.tableId,
        'from_user': myUserId,
        'to_user': userId,
        'status': 'pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Davet gÃ¶nderildi')));
    } catch (e) {
      if (!mounted) return;
      final err = e.toString();
      final message =
          (isBot &&
              (err.contains('foreign key') ||
                  err.contains('violates') ||
                  err.contains('auth.users')))
          ? 'Bot hesabı auth.users içinde bulunmadığı için masaya eklenemedi.'
          : 'Davet gönderilemedi: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _SeatPlayer {
  final int seatIndex;
  final PlayerModel player;

  _SeatPlayer({required this.seatIndex, required this.player});
}

class _InviteSeatCard extends StatelessWidget {
  final bool vertical;
  final VoidCallback onInvite;

  const _InviteSeatCard({required this.vertical, required this.onInvite});

  @override
  Widget build(BuildContext context) {
    final content = [
      const CircleAvatar(
        radius: 26,
        backgroundColor: Color(0xFF1F2937),
        child: Icon(Icons.person_add_alt_1, color: Color(0xFFD4AF37)),
      ),
      vertical ? const SizedBox(height: 10) : const SizedBox(width: 10),
      ElevatedButton(
        onPressed: onInvite,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD4AF37),
          foregroundColor: Colors.black,
        ),
        child: const Text('DAVET'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xCC141A20), Color(0xAA0F141A)],
        ),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: vertical
          ? Column(mainAxisSize: MainAxisSize.min, children: content)
          : Row(mainAxisSize: MainAxisSize.min, children: content),
    );
  }
}
