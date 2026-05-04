import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/services/profile_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player_model.dart';
import 'avatar_card.dart';
import 'avatar_preset.dart';

class GameAvatarOverlay extends StatefulWidget {
  final String tableId;
  final double topInset;
  final OkeyGame game;
  final Map<String, String> playerChatByUserId;
  const GameAvatarOverlay({
    super.key,
    required this.tableId,
    this.topInset = 0,
    required this.game,
    this.playerChatByUserId = const {},
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
  final List<_FlyAwayFx> _flyAwayFx = <_FlyAwayFx>[];

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
      final previousPlayers = List<_SeatPlayer>.from(players);
      final previousIds = players.map((p) => p.player.id).toSet();
      final joinedPlayers = _hasLoadedPlayersOnce
          ? mapped.where((p) => !previousIds.contains(p.player.id)).toList()
          : const <_SeatPlayer>[];
      final removedPlayers = _hasLoadedPlayersOnce
          ? previousPlayers
              .where((p) => !mapped.any((m) => m.player.id == p.player.id))
              .toList(growable: false)
          : const <_SeatPlayer>[];

      setState(() {
        players = mapped;
        _mySeatIndex = mySeat;
        _hasLoadedPlayersOnce = true;
      });

      _showJoinedPlayersSnack(joinedPlayers);
      _showRemovedPlayersFx(removedPlayers, mySeat);
    } catch (e) {
      debugPrint('OVERLAY ERROR: $e');
    }
  }

  void _showRemovedPlayersFx(List<_SeatPlayer> removedPlayers, int? mySeat) {
    if (!mounted || removedPlayers.isEmpty) return;
    final baseSeat = mySeat ?? _mySeatIndex ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      for (int i = 0; i < removedPlayers.length; i++) {
        final p = removedPlayers[i];
        final relative = (p.seatIndex - baseSeat + _tableSize) % _tableSize;
        _flyAwayFx.add(
          _FlyAwayFx(
            key: '${p.player.id}_$nowMs\_$i',
            relativeSeat: relative,
            name: p.player.name,
            avatarPath: p.player.avatarPath,
          ),
        );
      }
    });
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Widget _inviteAvatar(String? avatarRef, String name) {
    final raw = avatarRef?.trim();
    final resolved = (raw != null && raw.isNotEmpty)
        ? avatarPresetByRef(raw).imageUrl
        : '';
    final fallbackChar = name.isNotEmpty ? name[0].toUpperCase() : '?';

    if (resolved.startsWith('assets/')) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFF1F3D32),
        backgroundImage: AssetImage(resolved),
      );
    }
    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: const Color(0xFF1F3D32),
        backgroundImage: NetworkImage(resolved),
        onBackgroundImageError: (_, __) {},
        child: Text(
          fallbackChar,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFF1F3D32),
      child: Text(
        fallbackChar,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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

      final isMe = me != null;

      if (me != null) {
        items.add(
          _buildPositionedSeat(
            size: size,
            relativeSeat: 0,
            child: _buildSeatWithChatBubble(
              player: me.player,
              position: AvatarPosition.bottom,
              progress: widget.game.getTurnProgress(),
              onTap: () {
                ProfileService.showUserCard({'id': me.player.id});
              },
            ),
          ),
        );
      }

      items.add(
        _buildPositionedSeat(
          size: size,
          relativeSeat: 1,
          child: opponent != null
              ? _buildSeatWithChatBubble(
                  player: opponent.player,
                  position: AvatarPosition.top,
                  progress: (opponent.player.remainingTime / 15).clamp(
                    0.0,
                    1.0,
                  ),
                  onTap: () {
                    ProfileService.showUserCard({'id': opponent.player.id});
                  },
                )
              : (_tableStatus == 'playing'
                    ? const SizedBox.shrink()
                    : _InviteSeatCard(
                        vertical: false,
                        onInvite: () => _showInviteDialogForSeat(1),
                      )),
        ),
      );

      return Stack(
        children: [
          ...items,
          ..._flyAwayFx
              .map((fx) => _buildFlyAwayFx(size: size, fx: fx))
              .toList(growable: false),
        ],
      );
    }

    for (int absoluteSeat = 0; absoluteSeat < _tableSize; absoluteSeat++) {
      final relativeSeat = _relativeSeat(absoluteSeat);
      final occupied = bySeat[absoluteSeat];

      items.add(
        _buildPositionedSeat(
          size: size,
          relativeSeat: relativeSeat,
          child: occupied != null
              ? _buildSeatWithChatBubble(
                  player: occupied.player,
                  position: _avatarPositionFor(relativeSeat),
                  progress: (occupied.player.remainingTime / 15).clamp(
                    0.0,
                    1.0,
                  ),
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

    return Stack(
      children: [
        ...items,
        ..._flyAwayFx
            .map((fx) => _buildFlyAwayFx(size: size, fx: fx))
            .toList(growable: false),
      ],
    );
  }

  Widget _buildSeatWithChatBubble({
    required PlayerModel player,
    required AvatarPosition position,
    required double progress,
    VoidCallback? onTap,
  }) {
    final text = widget.playerChatByUserId[player.id];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AvatarCard(
          player: player,
          position: position,
          progress: progress,
          onTap: onTap,
        ),
        if (text != null && text.trim().isNotEmpty)
          Positioned(
            top: -30,
            left: 4,
            right: 4,
            child: IgnorePointer(
              child: _buildChatBubble(text.trim()),
            ),
          ),
      ],
    );
  }

  Widget _buildChatBubble(String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF2D596), Color(0xFFE7BE6A)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xCC7A5A1F), width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1D2A25),
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.1,
            ),
          ),
        ),
        CustomPaint(
          size: const Size(14, 7),
          painter: _ChatBubbleTailPainter(),
        ),
      ],
    );
  }

  Widget _buildFlyAwayFx({required Size size, required _FlyAwayFx fx}) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(fx.key),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      onEnd: () {
        if (!mounted) return;
        setState(() {
          _flyAwayFx.removeWhere((e) => e.key == fx.key);
        });
      },
      builder: (context, t, child) {
        final anchor = _seatAnchor(size, fx.relativeSeat);
        final dx = 220.0 * t;
        final dy = -260.0 * t;
        final opacity = (1 - t).clamp(0.0, 1.0);
        final scale = (1 - 0.7 * t).clamp(0.2, 1.0);
        final angle = 0.45 * t;

        return Positioned(
          left: anchor.dx + dx - 48,
          top: anchor.dy + dy - 48,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: angle,
                child: Transform.scale(
                  scale: scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _inviteAvatar(fx.avatarPath, fx.name),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC2A1313),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0x66FFB085),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'Masa disi!',
                          style: TextStyle(
                            color: Color(0xFFFFE0D2),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Offset _seatAnchor(Size size, int relativeSeat) {
    switch (relativeSeat) {
      case 0:
        return Offset(size.width * 0.5, size.height * 0.72);
      case 1:
        if (_tableSize == 2) return Offset(size.width * 0.5, size.height * 0.17);
        return Offset(size.width * 0.2, size.height * 0.45);
      case 2:
        return Offset(size.width * 0.5, size.height * 0.17);
      case 3:
        return Offset(size.width * 0.8, size.height * 0.45);
      default:
        return Offset(size.width * 0.5, size.height * 0.5);
    }
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
        final scale = min(size.width / 1600, size.height / 900);

        final gameHeight = 900 * scale;
        final offsetY = (size.height - gameHeight) / 2;

        final rackY = 720.0;
        final rackHeight = 400.0;
        final rackTop = rackY - rackHeight / 2;

        final avatarWorldY = rackTop - 170;

        final avatarScreenY = avatarWorldY * scale + offsetY;

        return Positioned(
          left: 0,
          right: 0,
          top: avatarScreenY,
          child: Center(child: child),
        );
      case 1:
        if (_tableSize == 2) {
          return Positioned(
            left: 0,
            right: 0,
            top: widget.topInset,
            child: Center(child: child),
          );
        }
        return Positioned(left: 20, top: size.height, child: child);
      case 2:
        return Positioned(
          left: 0,
          right: 0,
          top: widget.topInset,
          child: Center(child: child),
        );
      case 3:
        return Positioned(right: 20, top: size.height * 0.42, child: child);
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _showInviteDialogForSeat(int seatIndex) async {
    final candidates = await _loadEligiblePlayers();
    final _controller = ScrollController();

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(.75),
      builder: (context) {
        final online = candidates
            .where((p) => p['is_online'] == true)
            .toList(growable: false);
        final offline = candidates
            .where((p) => p['is_online'] != true)
            .toList(growable: false);

        Widget buildCandidateList(List<Map<String, dynamic>> source) {
          if (source.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  "Bu sekmede oyuncu yok.",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }

          return Stack(
            children: [
              Scrollbar(
                controller: _controller,
                thumbVisibility: true,
                thickness: 4,
                radius: const Radius.circular(8),
                child: ListView.separated(
                  controller: _controller,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 30),
                  itemCount: source.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = source[i];

                    final name = p['username']?.toString() ?? "Oyuncu";
                    final rating = p['rating'];
                    final coins = p['coins'] ?? 0;
                    final userId = p['id']?.toString();
                    final avatarUrl = p['avatar_url'];
                    final isOnline = p['is_online'] == true;
                    final lastSeenText = _formatLastSeen(p['last_seen_at']);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF16251F).withOpacity(0.9),
                            const Color(0xFF0F1B17).withOpacity(0.9),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.05),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFB9932F).withOpacity(0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _inviteAvatar(avatarUrl?.toString(), name),
                                Positioned(
                                  right: -1,
                                  top: -1,
                                  child: _statusDot(isOnline),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.emoji_events,
                                      size: 14,
                                      color: Color(0xFFE7C66A),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      Format.rating(rating),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.monetization_on,
                                      size: 14,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      Format.coin(coins),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                if (!isOnline) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    lastSeenText,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFE7C66A),
                                  Color(0xFFB9932F),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFB9932F).withOpacity(0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: userId == null
                                    ? null
                                    : () async {
                                        await _sendInvite(
                                          userId: userId,
                                          isBot: p['is_bot'] == true,
                                        );
                                        if (!mounted) return;
                                        Navigator.pop(context);
                                      },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    "Davet",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF0F1B17).withOpacity(0.9),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return DefaultTabController(
          length: 2,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight: MediaQuery.of(context).size.height * 0.78,
              ),
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1B17).withOpacity(0.88),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFB9932F).withOpacity(0.7),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        const Icon(Icons.group, color: Color(0xFFE7C66A)),
                        const SizedBox(width: 8),
                        const Text(
                          "Oyuncu Davet Et",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE7C66A),
                            letterSpacing: .6,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (candidates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          "Bu lig için uygun oyuncu bulunamadı.",
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    else ...[
                      Container(
                        height: 46,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0x33243A33), Color(0x33111C18)],
                          ),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: const Color(0x6689B19F),
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: TabBar(
                          indicator: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEFD18A), Color(0xFFD9A84D)],
                            ),
                            borderRadius: BorderRadius.circular(10.5),
                            border: Border.all(
                              color: const Color(0xCC775A1F),
                              width: 0.9,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x8A7D5717),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          indicatorPadding: EdgeInsets.zero,
                          labelColor: const Color(0xFF1F2B24),
                          unselectedLabelColor: const Color(0xFFD7E7DE),
                          labelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.15,
                          ),
                          tabs: [
                            Tab(text: 'Oyunda (${online.length})'),
                            Tab(text: 'Oyun Dışı (${offline.length})'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: TabBarView(
                          children: [
                            buildCandidateList(online),
                            buildCandidateList(offline),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
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
      final res = await _supabase.rpc(
        'get_invitable_players',
        params: {
          'p_table_id': widget.tableId,
          'p_user_id': myUserId,
          'p_league_id': leagueId,
          'p_entry_coin': _entryCoin,
        },
      );

      final list = List<Map<String, dynamic>>.from(res ?? []);

      // ekstra güvenlik: rating'e göre sırala
      list.sort((a, b) {
        final ar = (a['rating'] as int?) ?? 0;
        final br = (b['rating'] as int?) ?? 0;
        return br.compareTo(ar);
      });

      final ids = list
          .map((e) => e['id']?.toString())
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (ids.isNotEmpty) {
        final statusRows = await _supabase
            .from('profiles')
            .select('id,is_online,last_seen_at')
            .inFilter('id', ids);
        final byId = <String, Map<String, dynamic>>{};
        for (final raw in (statusRows as List)) {
          final row = Map<String, dynamic>.from(raw as Map);
          final id = row['id']?.toString();
          if (id != null && id.isNotEmpty) {
            byId[id] = row;
          }
        }
        for (final p in list) {
          final id = p['id']?.toString();
          final status = id == null ? null : byId[id];
          p['is_online'] = (p['is_bot'] == true) || (status?['is_online'] == true);
          p['last_seen_at'] = status?['last_seen_at'];
        }
      }
      return list;
    } catch (e) {
      debugPrint('ELIGIBLE PLAYERS ERROR: $e');
      return [];
    }
  }

  Widget _statusDot(bool isOnline) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isOnline ? const Color(0xFF33D17A) : const Color(0xFFE5484D),
        border: Border.all(color: Colors.white, width: 1.4),
      ),
    );
  }

  String _formatLastSeen(dynamic raw) {
    if (raw == null) return 'Son görülme: bilinmiyor';
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return 'Son görülme: bilinmiyor';
    final diff = DateTime.now().toUtc().difference(parsed.toUtc());
    if (diff.inSeconds < 60) return 'Son görülme: az önce';
    if (diff.inMinutes < 60) return 'Son görülme: ${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return 'Son görülme: ${diff.inHours} sa önce';
    return 'Son görülme: ${diff.inDays} gün önce';
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
      try {
        await _supabase.functions.invoke(
          'send_table_invite_push',
          body: {
            'table_id': widget.tableId,
            'from_user': myUserId,
            'to_user': userId,
          },
        );
      } catch (e) {
        debugPrint('INVITE PUSH SEND ERROR: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Davet Gönderildi')));
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

class _FlyAwayFx {
  final String key;
  final int relativeSeat;
  final String name;
  final String? avatarPath;

  _FlyAwayFx({
    required this.key,
    required this.relativeSeat,
    required this.name,
    required this.avatarPath,
  });
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

class _ChatBubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    final fill = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF2D596), Color(0xFFE7BE6A)],
      ).createShader(Offset.zero & size);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xCC7A5A1F);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
