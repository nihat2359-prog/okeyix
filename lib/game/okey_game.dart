import 'dart:async' as async;
import 'dart:convert';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/components/closed_pile_component.dart';
import 'package:okeyix/game/components/discard_slot_component.dart';
import 'package:okeyix/game/components/seat_component.dart';
import 'package:okeyix/game/mappers/tile_mapper.dart';
import 'package:okeyix/game/rack/preview_component.dart';
import 'package:okeyix/game/rack/rack_config.dart';
import 'package:okeyix/game/rack/rack_slot_generator.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/game/stage.dart';
import 'package:okeyix/main.dart';
import 'package:okeyix/game/components/finish_rack.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OkeyGame extends FlameGame {
  @override
  late final World world;
  late final CameraComponent cameraComponent;

  final String tableId;
  final bool isCreator;
  final VoidCallback? onTileSfx;

  bool isTempShiftActive = false;
  int? tempShiftIndex;

  int currentTurn = 0;
  bool hasDrawnThisTurn = false;
  bool _gameStarted = false;
  bool _startRequestInFlight = false;
  bool _actionInFlight = false;
  bool _stateSyncInFlight = false;
  bool _countdownInProgress = false;
  bool _countdownTriggeredForThisFullState = false;
  int _maxPlayers = 2;
  int _countdownSecondsLeft = 0;
  int _turnSeconds = 15;
  int? _mySeatIndexAbs;
  DateTime? _turnStartedAt;
  String? _lastRenderedHandFingerprint;
  bool _sourceDrawDragActive = false;
  Vector2? _sourceDrawDragPosition;
  DiscardSlotComponent? _sourceDrawFromDiscardSlot;
  int? _pendingPreferredDrawSlot;
  String? _lastTimeoutTurnToken;
  String? _lastBotTurnToken;

  final List<Vector2> slotPositions = [];
  final Map<int, TileComponent> occupiedSlots = {};
  final Map<int, Map<String, dynamic>> _playerSeatMap = {};
  final Set<int> _botSeats = <int>{};
  final Map<String, Map<String, int>> _botKeepMemory = {};
  final Map<String, Map<String, int>> _botRecentDiscards = {};
  final List<TileModel> closedPile = [];
  Map<String, dynamic>? _league;

  TileComponent? activeDraggedTile;
  TileComponent? lastDiscardedTile;
  ClosedPileComponent? closedPileComponent;
  TileComponent? indicatorTileComponent;
  late PreviewComponent previewBox;
  late DiscardSlotComponent bottomRightDiscard;
  late DiscardSlotComponent bottomLeftDiscard;
  RealtimeChannel? _tableChannel;
  RealtimeChannel? _tablePlayersChannel;
  RealtimeChannel? _tableDiscardsChannel;
  RealtimeChannel? _movesChannel;
  async.Timer? _startWatchdogTimer;
  async.Timer? _startCountdownTimer;
  async.Timer? _turnTimer;
  async.Timer? _discardPollTimer;
  async.Timer? _tableStatePollTimer;
  TextComponent? _centerStatusText;
  final Map<int, DiscardSlotComponent> _discardSlotsByIndex = {};
  final Map<int, TileComponent> _discardTopTilesBySeat = {};
  final Set<int> _discardAnimationInFlightSeats = <int>{};
  final Set<String> _recentMoveKeys = <String>{};
  final List<String> _recentMoveKeyOrder = <String>[];
  final List<TileComponent> _deferredTileRemovals = [];
  FinishRack? _finishRack;
  OkeyGame({
    required this.tableId,
    required this.isCreator,
    this.onTileSfx,
  });

  bool get gameStarted => _gameStarted;

  void _emitTileSfx() {
    onTileSfx?.call();
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _initStage();
    await _loadInitialState();
    _subscribeRealtime();
    _subscribeTablePlayersRealtime();
    _subscribeTableDiscardsRealtime();
    _startStartWatchdog();
    _startTurnTimer();
    _startDiscardPoll();
    _startLiveTablePoll();
    _subscribeRealtimeMoves();
  }

  Future<void> reloadInitialState() async {
    await _loadInitialState();
  }

  void showFinish(List<Map<String, dynamic>> slots, String name) {
    _finishRack?.removeFromParent(); // varsa sil

    _finishRack = FinishRack(slots, name);

    world.add(_finishRack!);
  }

  void hideFinish() {
    _finishRack?.removeFromParent();
    _finishRack = null;
  }

  Vector2? getSlotPositionFromLive(int index) {
    final tile = occupiedSlots[index];
    if (tile != null) {
      return tile.position.clone(); // ğŸ”¥ GERÃ‡EK POZÄ°SYON
    }

    // fallback â†’ slotPositions varsa
    if (index < slotPositions.length) {
      return slotPositions[index].clone();
    }

    return null;
  }

  int getMyCoins() {
    if (_mySeatIndexAbs == null) return 0;

    final player = _playerSeatMap[_mySeatIndexAbs];
    if (player == null) return 0;

    final user = player['user'];
    if (user == null) return 0;

    return user['coins'] ?? 0;
  }

  @override
  @override
  void onRemove() {
    if (_tableChannel != null) {
      supabase.removeChannel(_tableChannel!);
    }

    if (_tablePlayersChannel != null) {
      supabase.removeChannel(_tablePlayersChannel!);
    }

    if (_tableDiscardsChannel != null) {
      supabase.removeChannel(_tableDiscardsChannel!);
    }

    if (_movesChannel != null) {
      supabase.removeChannel(_movesChannel!);
    }

    _startWatchdogTimer?.cancel();
    _startCountdownTimer?.cancel();
    _turnTimer?.cancel();
    _discardPollTimer?.cancel();
    _tableStatePollTimer?.cancel();

    _tableChannel = null;
    _tablePlayersChannel = null;
    _tableDiscardsChannel = null;
    _movesChannel = null;

    _startWatchdogTimer = null;
    _startCountdownTimer = null;
    _turnTimer = null;
    _discardPollTimer = null;
    _tableStatePollTimer = null;

    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_deferredTileRemovals.isEmpty) return;
    final pending = List<TileComponent>.from(_deferredTileRemovals);
    _deferredTileRemovals.clear();
    for (final tile in pending) {
      if (tile.isMounted) {
        tile.removeFromParent();
      }
    }
  }

  void scheduleTileRemoval(TileComponent tile) {
    if (_deferredTileRemovals.contains(tile)) return;
    _deferredTileRemovals.add(tile);
  }

  Future<void> _loadInitialState() async {
    final supabase = Supabase.instance.client;

    final tableRow = await supabase
        .from('tables')
        .select(
          'id, status, max_players, current_turn, deck, league_id, turn_started_at',
        )
        .eq('id', tableId)
        .maybeSingle();
    if (tableRow == null) {
      return;
    }
    final table = Map<String, dynamic>.from(tableRow);

    _maxPlayers = (table['max_players'] as int?) ?? 2;
    final nextTurn = (table['current_turn'] as int?) ?? 0;
    final serverTurnStartedAt = _parseServerTime(table['turn_started_at']);
    if (currentTurn != nextTurn) {
      _turnStartedAt = serverTurnStartedAt ?? DateTime.now();
      _lastTimeoutTurnToken = null;
    }
    currentTurn = nextTurn;
    _turnStartedAt = serverTurnStartedAt ?? _turnStartedAt ?? DateTime.now();

    try {
      final leagueId = table['league_id']?.toString();
      if (leagueId != null && leagueId.isNotEmpty) {
        final leagueRows = await supabase
            .from('leagues')
            .select('name, entry_coin, turn_seconds')
            .eq('id', leagueId)
            .limit(1);
        if ((leagueRows as List).isNotEmpty) {
          _turnSeconds =
              (leagueRows.first['turn_seconds'] as int?) ?? _turnSeconds;
          _league = Map<String, dynamic>.from(leagueRows.first);
        }
      }
      try {
        final tableTurn = await supabase
            .from('tables')
            .select('turn_seconds')
            .eq('id', tableId)
            .limit(1);
        if ((tableTurn as List).isNotEmpty) {
          final override = tableTurn.first['turn_seconds'] as int?;
          if (override != null && override > 0) {
            _turnSeconds = override;
          }
        }
      } catch (_) {}
    } catch (_) {}
    _turnSeconds = _normalizeTurnSeconds(_turnSeconds);

    final rawPlayers = await supabase
        .from('table_players')
        .select('''
      seat_index,
      user_id,
      hand,
      users (
        id,
        username,
        rating,
        avatar_url,
        is_bot,
        profiles (
          coins
        )
      )
    ''')
        .eq('table_id', tableId);

    final playersWithProfiles = (rawPlayers as List).map((p) {
      final map = Map<String, dynamic>.from(p as Map);

      final user = map['users'];

      if (user != null && user['profiles'] != null) {
        user['coins'] = user['profiles']['coins'];
      }

      map['user'] = user;
      map.remove('users');

      return map;
    }).toList();

    final uid = Supabase.instance.client.auth.currentUser?.id;

    final stillInTable = playersWithProfiles.any(
      (p) => p['user_id']?.toString() == uid,
    );

    if (!stillInTable) {
      debugPrint("PLAYER REMOVED FROM TABLE");

      _gameStarted = false;

      _showWaitingOverlay("Masadan atÄ±ldÄ±n");

      Future.delayed(const Duration(seconds: 2), () {
        overlays.add('LobbyOverlay');
      });

      return;
    }

    _playerSeatMap
      ..clear()
      ..addEntries(
        playersWithProfiles.map((p) => MapEntry((p['seat_index'] as int), p)),
      );
    _botSeats
      ..clear()
      ..addAll(
        playersWithProfiles
            .where((p) => p['user']?['is_bot'] == true)
            .map((p) => p['seat_index'] as int),
      );

    _mySeatIndexAbs = null;
    for (final p in playersWithProfiles) {
      if (p['user_id']?.toString() != uid) continue;
      final seat = p['seat_index'];
      if (seat is int) {
        _mySeatIndexAbs = seat;
        break;
      }
    }

    _renderSeats();
    _syncDeckFromTable(table['deck']);

    final status = table['status'] as String?;
    if (status != 'playing') {
      _gameStarted = false;
      _lastTimeoutTurnToken = null;
      _countdownTriggeredForThisFullState = false;
      _clearRenderedHand();
      _clearTableVisualState();
      _hideWaitingOverlay();
      await _ensureGameStartIfReady(
        knownStatus: status,
        knownPlayerCount: playersWithProfiles.length,
      );
      return;
    }

    _gameStarted = true;
    _cancelStartCountdown();
    _hideWaitingOverlay();
    await _ensureFreshTurnStartedAt(
      status: status,
      serverTurnStartedAt: serverTurnStartedAt,
    );
    _turnStartedAt ??= DateTime.now();
    await _syncDiscardTopsFromServer();
    _renderMyHand(playersWithProfiles);
  }

  Map<String, dynamic>? getLeague() {
    return _league;
  }

  int getPlayerCount() {
    return _maxPlayers;
  }

  int getTurnSeconds() {
    return _turnSeconds;
  }

  void resetGameState() {
    _playerSeatMap.clear();
    _botSeats.clear();

    _mySeatIndexAbs = null;
    _maxPlayers = 2;
    _gameStarted = false;
  }

  Future<void> _tryStartGameOnServer() async {
    print(_startRequestInFlight);
    if (_startRequestInFlight) return;
    _startRequestInFlight = true;
    final supabase = Supabase.instance.client;
    try {
      try {
        await supabase.rpc('start_game', params: {'p_table_id': tableId});
        await _loadInitialState();

        return;
      } catch (e, st) {
        debugPrint('START GAME RPC ERROR: $e');
        debugPrintStack(stackTrace: st);
        rethrow; // ğŸ”¥ BUNU EKLE
      }
    } finally {
      _startRequestInFlight = false;
    }
  }

  void _startStartWatchdog() {
    _startWatchdogTimer?.cancel();
    _startWatchdogTimer = async.Timer.periodic(const Duration(seconds: 2), (_) {
      if (_gameStarted || _stateSyncInFlight) return;
      _stateSyncInFlight = true;
      _syncWaitingOrPlayingState().whenComplete(() {
        _stateSyncInFlight = false;
      });
    });
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    _turnTimer = async.Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_gameStarted) return;
      _maybePlayBotTurn();
      if (!_isMyTurn()) return;
      final startAt = _turnStartedAt;
      if (startAt == null) {
        _turnStartedAt = DateTime.now();
        return;
      }
      final elapsed = DateTime.now().difference(startAt).inSeconds;
      if (elapsed < _turnSeconds) return;
      if (_actionInFlight) return;
      final token = '${currentTurn}_${startAt.millisecondsSinceEpoch}';
      if (_lastTimeoutTurnToken == token) return;
      _lastTimeoutTurnToken = token;
      _autoPlayTimeoutMove();
    });
  }

  void _maybePlayBotTurn() {
    if (_actionInFlight) return;

    if (!_botSeats.contains(currentTurn)) return;

    final startAt = _turnStartedAt ?? DateTime.now();

    final token = '${currentTurn}_${startAt.millisecondsSinceEpoch}';

    if (_lastBotTurnToken == token) return;

    final elapsedMs = DateTime.now().difference(startAt).inMilliseconds;

    if (elapsedMs < 1800) return;

    _lastBotTurnToken = token;

    _playBotTurn();
  }

  Future<void> _playBotTurn() async {
    final botPlayer = _playerSeatMap[currentTurn];
    final botUserId = botPlayer?['user_id']?.toString();

    if (botUserId == null) return;

    _actionInFlight = true;

    try {
      var rows = await Supabase.instance.client
          .from('table_players')
          .select('hand')
          .eq('table_id', tableId)
          .eq('user_id', botUserId)
          .limit(1);

      if ((rows as List).isEmpty) return;

      var hand = rows.first['hand'];

      if (hand is! List) return;
      final strategy = decideStrategy(hand);

      Map<String, dynamic>? drawnFromDiscardTile;
      var drewFromDiscard = false;

      /// draw
      if (hand.length == 14) {
        final fromSeat = (currentTurn - 1 + _maxPlayers) % _maxPlayers;
        final topDiscard = await _fetchDiscardTopForSeat(fromSeat);
        _decayBotRecentDiscards(botUserId);
        final currentPotential = _handPotentialScore(
          hand
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
        final takePotential = _potentialAfterTakingDiscard(
          hand,
          topDiscard,
          strategy,
        );
        final canFinishWithTop = _canFinishAfterTakingTopDiscard(hand, topDiscard);
        final shouldTakeByHeuristic =
            shouldTakeDiscard(hand, topDiscard, strategy);
        final topIsRecentOwnDiscard = topDiscard != null &&
            _botRecentDiscards[botUserId]?.containsKey(_tileMapKey(topDiscard)) ==
                true;
        final topIsFakeJoker = topDiscard != null &&
            (topDiscard['fake_joker'] == true ||
                topDiscard['is_fake_joker'] == true);
        final immediateMeldValue =
            _immediateMeldGainFromTopDiscard(hand, topDiscard);
        final wouldThrowBackTop = _wouldDiscardTakenTop(
          hand,
          topDiscard,
          strategy,
        );
        final potentialGain = takePotential - currentPotential;
        // Human-like rule:
        // take from discard when it clearly improves immediate meld quality
        // (especially completing/strengthening sets), otherwise draw closed.
        final shouldTakeTop = canFinishWithTop ||
            (!topIsRecentOwnDiscard &&
                !topIsFakeJoker &&
                ((immediateMeldValue >= 4) ||
                    (!wouldThrowBackTop &&
                        (immediateMeldValue >= 3))));

        var source = (topDiscard != null && shouldTakeTop) ? 'discard' : 'closed';

        try {
          await Supabase.instance.client.rpc(
            'game_draw',
            params: {
              'p_table_id': tableId,
              'p_user_id': botUserId,
              'p_source': source,
              'p_from_seat': source == 'discard' ? fromSeat : null,
            },
          );
          drewFromDiscard = source == 'discard';
          if (drewFromDiscard && topDiscard != null) {
            drawnFromDiscardTile = Map<String, dynamic>.from(topDiscard);
          }
        } catch (e) {
          // Fallback: if taking from discard fails for any reason, draw from closed
          // so the bot does not freeze on its turn.
          if (source == 'discard') {
            source = 'closed';
            await Supabase.instance.client.rpc(
              'game_draw',
              params: {
                'p_table_id': tableId,
                'p_user_id': botUserId,
                'p_source': source,
                'p_from_seat': null,
              },
            );
            drewFromDiscard = false;
          } else {
            rethrow;
          }
        }

        rows = await Supabase.instance.client
            .from('table_players')
            .select('hand')
            .eq('table_id', tableId)
            .eq('user_id', botUserId)
            .limit(1);

        if ((rows as List).isEmpty) return;

        hand = rows.first['hand'];
      }

      if (hand is! List || hand.length != 15) return;

      final finishDiscardTile = _pickFinishDiscardTile(hand);
      final canFinish = finishDiscardTile != null;
      final botSlots = _buildSlotsJsonFromHand(hand);

      _decayBotKeepMemory(botUserId);
      if (drewFromDiscard && drawnFromDiscardTile != null) {
        _rememberBotTile(botUserId, drawnFromDiscardTile!);
      }

      Map<String, dynamic> tile;
      if (canFinish) {
        tile = finishDiscardTile!;
      } else {
        tile = pickBestDiscardTile(
          hand,
          strategy,
          protectedKeys: _botProtectedTileKeys(botUserId),
        );
        if (_isJokerMap(tile)) {
          tile = _pickNonJokerTileOrFallback(hand, strategy);
        }
      }
      tile = _ensureLooseDiscardWhenPossible(hand, tile, strategy);

      // Final guard against race/desync: never send discard if server hand is not 15.
      final latestRows = await Supabase.instance.client
          .from('table_players')
          .select('hand')
          .eq('table_id', tableId)
          .eq('user_id', botUserId)
          .limit(1);
      if (latestRows is! List || latestRows.isEmpty) return;
      final latestHand = latestRows.first['hand'];
      if (latestHand is! List || latestHand.length != 15) {
        return;
      }


      await Supabase.instance.client.rpc(
        'game_discard',
        params: {
          'p_table_id': tableId,
          'p_user_id': botUserId,
          'p_tile': tile,
          'p_slots': botSlots,
          'p_finish': canFinish,
          'p_is_player_action': false,
        },
      );
      _rememberBotDiscard(botUserId, tile);
    } catch (e) {
      debugPrint("BOT TURN ERROR $e");
    } finally {
      _actionInFlight = false;
    }
  }

  Future<Map<String, dynamic>?> _fetchDiscardTopForSeat(int seatIndex) async {
    try {
      final rows = await Supabase.instance.client
          .from('table_discard_tops')
          .select('tile')
          .eq('table_id', tableId)
          .eq('seat_index', seatIndex)
          .limit(1);

      if (rows is! List || rows.isEmpty) return null;
      final tile = rows.first['tile'];
      if (tile is! Map) return null;
      return Map<String, dynamic>.from(tile);
    } catch (e) {
      // Network/intermittent backend failures should not block bot turn logic.
      return null;
    }
  }

  bool _canFinishAfterTakingTopDiscard(
    List hand,
    Map<String, dynamic>? topDiscard,
  ) {
    if (topDiscard == null) return false;
    final candidate = List<Map<String, dynamic>>.from(
      hand.map((e) => Map<String, dynamic>.from(e as Map)),
    )..add(Map<String, dynamic>.from(topDiscard));

    if (candidate.length != 15) return false;
    final finishTiles = buildFinishTilesFromHand(candidate);
    return _isValidFinishHand(finishTiles);
  }

  bool _wouldDiscardTakenTop(
    List hand,
    Map<String, dynamic>? topDiscard,
    String strategy,
  ) {
    if (topDiscard == null) return false;
    final candidate = List<Map<String, dynamic>>.from(
      hand.map((e) => Map<String, dynamic>.from(e as Map)),
    )..add(Map<String, dynamic>.from(topDiscard));

    final bestDiscard = pickBestDiscardTile(candidate, strategy);
    return _sameTileMap(bestDiscard, topDiscard);
  }

  int _potentialAfterTakingDiscard(
    List hand,
    Map<String, dynamic>? topDiscard,
    String strategy,
  ) {
    if (topDiscard == null) return -999999;
    final candidate = hand
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    candidate.add(Map<String, dynamic>.from(topDiscard));
    if (candidate.length != 15) return -999999;

    final discard = pickBestDiscardTile(candidate, strategy);
    final removeIndex = candidate.indexWhere((t) => _sameTileMap(t, discard));
    if (removeIndex == -1) return -999999;
    candidate.removeAt(removeIndex);
    return _handPotentialScore(candidate);
  }

  int _immediateMeldGainFromTopDiscard(
    List hand,
    Map<String, dynamic>? topDiscard,
  ) {
    if (topDiscard == null) return 0;
    if (_isJokerMap(topDiscard)) return 0;
    final t = BotTile.fromJson(topDiscard);
    final tiles = hand
        .whereType<Map>()
        .map((e) => BotTile.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final sameValueColors = tiles
        .where((x) => x.value == t.value)
        .map((x) => x.color)
        .toSet()
        .length;
    final sameColorVals = tiles
        .where((x) => x.color == t.color)
        .map((x) => x.value)
        .toSet();

    var runTouch = 0;
    if (sameColorVals.contains(t.value - 1) || sameColorVals.contains(t.value + 1)) {
      runTouch += 1;
    }
    if (sameColorVals.contains(t.value - 2) || sameColorVals.contains(t.value + 2)) {
      runTouch += 1;
    }

    // Set contribution is based on different colors, not duplicate same color.
    if (sameValueColors >= 2) return 4;
    if (runTouch >= 2) return 3;
    if (sameValueColors >= 1 && runTouch >= 1) return 2;
    if (sameValueColors >= 1 || runTouch >= 1) return 1;
    return 0;
  }

  bool _sameTileMap(Map<String, dynamic> a, Map<String, dynamic> b) {
    final av = _tileNumber(a);
    final bv = _tileNumber(b);
    final ac = (a['color'] ?? '').toString();
    final bc = (b['color'] ?? '').toString();
    final aj = _isJokerMap(a);
    final bj = _isJokerMap(b);
    return av == bv && ac == bc && aj == bj;
  }

  int _tileNumber(Map<String, dynamic> tile) {
    return (tile['value'] ?? tile['number'] ?? 0) as int;
  }

  bool _isJokerMap(Map<String, dynamic> tile) {
    return tile['joker'] == true ||
        tile['is_joker'] == true ||
        tile['fake_joker'] == true ||
        tile['is_fake_joker'] == true;
  }

  Map<String, dynamic> _pickNonJokerTileOrFallback(List hand, String strategy) {
    final chosen = pickWorstTile(hand, strategy);
    if (!_isJokerMap(chosen)) return chosen;
    for (final raw in hand) {
      if (raw is Map<String, dynamic> && !_isJokerMap(raw)) return raw;
    }
    for (final raw in hand) {
      if (raw is Map) return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{'value': 1, 'color': 'red'};
  }

  Map<String, dynamic> _ensureLooseDiscardWhenPossible(
    List hand,
    Map<String, dynamic> selected,
    String strategy,
  ) {
    final normalized = hand
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    if (normalized.isEmpty) return selected;

    final analysis = analyzeHand(normalized);
    final groupedKeySet = <String>{};
    for (final run in analysis.runs) {
      for (final t in run) {
        groupedKeySet.add('${t.color}-${t.value}');
      }
    }
    for (final set in analysis.sets) {
      for (final t in set) {
        groupedKeySet.add('${t.color}-${t.value}');
      }
    }

    String keyOf(Map<String, dynamic> t) =>
        '${(t['color'] ?? '').toString()}-${(t['value'] ?? t['number'] ?? 0)}';

    final selectedKey = keyOf(selected);
    final hasLoose = normalized.any(
      (t) => !_isJokerMap(t) && !groupedKeySet.contains(keyOf(t)),
    );
    final selectedIsGrouped = groupedKeySet.contains(selectedKey);
    if (!hasLoose || !selectedIsGrouped) return selected;

    final looseOnly = normalized
        .where((t) => !_isJokerMap(t) && !groupedKeySet.contains(keyOf(t)))
        .toList(growable: false);
    if (looseOnly.isEmpty) return selected;

    return pickBestDiscardTile(looseOnly, strategy);
  }

  Map<String, dynamic>? _pickFinishDiscardTile(List hand) {
    final normalized = hand
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (normalized.length != 15) return null;

    for (int i = 0; i < normalized.length; i++) {
      final candidate = <Map<String, dynamic>>[];
      for (int j = 0; j < normalized.length; j++) {
        if (j != i) candidate.add(normalized[j]);
      }
      final finishTiles = buildFinishTilesFromHand(candidate);
      if (_isValidFinishHand(finishTiles)) {
        return normalized[i];
      }
    }
    return null;
  }

  void _rememberBotTile(String botUserId, Map<String, dynamic> tile) {
    final key = _tileMapKey(tile);
    final memory = _botKeepMemory.putIfAbsent(botUserId, () => <String, int>{});
    memory[key] = 8;
  }

  void _decayBotKeepMemory(String botUserId) {
    final memory = _botKeepMemory[botUserId];
    if (memory == null) return;
    final next = <String, int>{};
    memory.forEach((k, turns) {
      final left = turns - 1;
      if (left > 0) next[k] = left;
    });
    _botKeepMemory[botUserId] = next;
  }

  Set<String> _botProtectedTileKeys(String botUserId) {
    final memory = _botKeepMemory[botUserId];
    if (memory == null || memory.isEmpty) return <String>{};
    return memory.keys.toSet();
  }

  void _rememberBotDiscard(String botUserId, Map<String, dynamic> tile) {
    final key = _tileMapKey(tile);
    final memory =
        _botRecentDiscards.putIfAbsent(botUserId, () => <String, int>{});
    memory[key] = 12;
  }

  void _decayBotRecentDiscards(String botUserId) {
    final memory = _botRecentDiscards[botUserId];
    if (memory == null) return;
    final next = <String, int>{};
    memory.forEach((k, turns) {
      final left = turns - 1;
      if (left > 0) next[k] = left;
    });
    _botRecentDiscards[botUserId] = next;
  }

  String _tileMapKey(Map<String, dynamic> tile) {
    final value = _tileNumber(tile);
    final color = (tile['color'] ?? '').toString();
    final joker = _isJokerMap(tile) ? 1 : 0;
    return '$color-$value-$joker';
  }

  void _startDiscardPoll() {
    _discardPollTimer?.cancel();
    _discardPollTimer = async.Timer.periodic(const Duration(seconds: 1), (_) {
      _syncDiscardTopsFromServer();
    });
  }

  void _startLiveTablePoll() {
    _tableStatePollTimer?.cancel();
    _tableStatePollTimer = async.Timer.periodic(const Duration(seconds: 1), (
      _,
    ) {
      _pollLiveTableState();
    });
  }

  String decideStrategy(List hand) {
    final tiles = hand.map((e) => BotTile.fromJson(e)).toList();

    int runScore = 0;
    int setScore = 0;

    for (var t in tiles) {
      // run potansiyeli
      final hasNeighbor = tiles.any(
        (x) =>
            x != t &&
            x.color == t.color &&
            (x.value == t.value - 1 ||
                x.value == t.value + 1 ||
                (t.value == 1 && x.value == 13) ||
                (t.value == 13 && x.value == 1)),
      );

      if (hasNeighbor) runScore++;

      // set potansiyeli
      final sameCount = tiles.where((x) => x != t && x.value == t.value).length;

      if (sameCount >= 1) setScore++;
    }

    return runScore >= setScore ? 'run' : 'set';
  }

  Future<void> _pollLiveTableState() async {
    try {
      final rows = await Supabase.instance.client
          .from('tables')
          .select('status,current_turn,deck,turn_started_at')
          .eq('id', tableId)
          .limit(1);
      if ((rows as List).isEmpty) return;
      final table = Map<String, dynamic>.from(rows.first);
      final status = table['status']?.toString();
      if (status == 'playing' && !_gameStarted) {
        await _loadInitialState();
        return;
      }
      if (status != 'playing') {
        if (_gameStarted) {
          await _loadInitialState();
          return;
        }
        _clearRenderedHand();
        _clearTableVisualState();
        return;
      }
      final turn = table['current_turn'] as int?;
      if (turn != null && turn != currentTurn) {
        currentTurn = turn;
        _turnStartedAt =
            _parseServerTime(table['turn_started_at']) ?? DateTime.now();
        hasDrawnThisTurn = _isMyTurn() && occupiedSlots.length >= 15;
        _actionInFlight = false;
        _lastTimeoutTurnToken = null;
      }
      if (table['deck'] != null) {
        _syncDeckFromTable(table['deck']);
      }
    } catch (_) {}
  }

  bool _isMyTurn() {
    final mySeat = _resolveMySeatIndex();
    if (mySeat == null) return false;
    return currentTurn == mySeat;
  }

  int? _resolveMySeatIndex() {
    if (_mySeatIndexAbs != null) return _mySeatIndexAbs;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    for (final entry in _playerSeatMap.entries) {
      final userId = entry.value['user_id']?.toString();
      if (userId == uid) {
        _mySeatIndexAbs = entry.key;
        return _mySeatIndexAbs;
      }
    }
    return null;
  }

  void _autoPlayTimeoutMove() {
    if (!_isMyTurn()) return;
    _serverTimeoutMove();
  }

  Future<void> _ensureFreshTurnStartedAt({
    required String? status,
    required DateTime? serverTurnStartedAt,
  }) async {
    if (status != 'playing') return;
    final now = DateTime.now();
    final stale =
        serverTurnStartedAt == null ||
        now.difference(serverTurnStartedAt).inSeconds > (_turnSeconds + 2);
    if (!stale) return;
    _turnStartedAt = now;
    try {
      await Supabase.instance.client
          .from('tables')
          .update({'turn_started_at': now.toUtc().toIso8601String()})
          .eq('id', tableId)
          .eq('current_turn', currentTurn);
    } catch (_) {}
  }

  String _tileColorToString(TileColorType color) {
    switch (color) {
      case TileColorType.red:
        return 'red';
      case TileColorType.blue:
        return 'blue';
      case TileColorType.black:
        return 'black';
      case TileColorType.yellow:
        return 'yellow';
    }
  }

  Future<void> _syncWaitingOrPlayingState() async {
    try {
      final tableRows = await Supabase.instance.client
          .from('tables')
          .select('status,max_players')
          .eq('id', tableId)
          .limit(1);
      if ((tableRows as List).isEmpty) return;

      final table = Map<String, dynamic>.from(tableRows.first);
      final status = table['status']?.toString() ?? 'waiting';
      _maxPlayers = (table['max_players'] as int?) ?? _maxPlayers;

      if (status == 'playing') {
        await _loadInitialState();
        return;
      }

      final playerRows = await Supabase.instance.client
          .from('table_players')
          .select('id')
          .eq('table_id', tableId);
      final playerCount = (playerRows as List).length;

      if (status == 'waiting' && playerCount >= _maxPlayers) {
        _startCountdownIfNeeded();
      } else {
        _cancelStartCountdown();
        _countdownTriggeredForThisFullState = false;
        _hideWaitingOverlay();
      }
    } catch (e) {
      debugPrint('STATE SYNC ERROR: $e');
    }
  }

  Future<void> _ensureGameStartIfReady({
    String? knownStatus,
    int? knownPlayerCount,
  }) async {
    if (_gameStarted || _startRequestInFlight) return;

    try {
      String status = knownStatus ?? 'waiting';
      int playerCount = knownPlayerCount ?? -1;

      if (knownStatus == null) {
        final tableRows = await Supabase.instance.client
            .from('tables')
            .select('status,max_players')
            .eq('id', tableId)
            .limit(1);
        if ((tableRows as List).isEmpty) return;
        final table = Map<String, dynamic>.from(tableRows.first);
        status = table['status']?.toString() ?? 'waiting';
        _maxPlayers = (table['max_players'] as int?) ?? _maxPlayers;
      }

      if (knownPlayerCount == null) {
        final rows = await Supabase.instance.client
            .from('table_players')
            .select('id')
            .eq('table_id', tableId);
        playerCount = (rows as List).length;
      }

      if (status == 'waiting' && playerCount >= _maxPlayers) {
        _startCountdownIfNeeded();
      }
    } catch (e) {
      debugPrint('START WATCHDOG ERROR: $e');
    }
  }

  void _startCountdownIfNeeded() {
    if (_gameStarted ||
        _countdownInProgress ||
        _countdownTriggeredForThisFullState) {
      return;
    }
    _countdownTriggeredForThisFullState = true;
    _countdownInProgress = true;
    _countdownSecondsLeft = 5;
    _hideWaitingOverlay();

    _startCountdownTimer?.cancel();
    _startCountdownTimer = async.Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      if (_gameStarted) {
        _cancelStartCountdown();
        return;
      }
      _countdownSecondsLeft--;
      if (_countdownSecondsLeft > 0) {
        return;
      }

      timer.cancel();
      _countdownInProgress = false;
      if (isCreator) {
        await _tryStartGameOnServer();
      }
    });
  }

  void _cancelStartCountdown() {
    _countdownInProgress = false;
    _startCountdownTimer?.cancel();
    _startCountdownTimer = null;
  }

  void _renderMyHand(List<dynamic> rawPlayers) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    Map<String, dynamic>? me;
    for (final raw in rawPlayers) {
      if (raw is! Map<String, dynamic>) continue;
      if (raw['user_id'] == userId) {
        me = raw;
        break;
      }
    }

    if (me == null) return;
    final hand = me['hand'];
    if (hand is List) {
      final fingerprint = _handFingerprint(hand);
      if (fingerprint == _lastRenderedHandFingerprint) {
        hasDrawnThisTurn = _isMyTurn() && hand.length >= 15;
        return;
      }
      _renderHand(hand);
      _lastRenderedHandFingerprint = fingerprint;
      hasDrawnThisTurn = _isMyTurn() && hand.length >= 15;
    }
  }

  void _renderSeats() {
    final existing = world.children.whereType<SeatComponent>().toList();
    for (final seat in existing) {
      seat.removeFromParent();
    }
  }

  void _showWaitingOverlay([String text = 'Oyuncu bekleniyor...']) {
    if (_centerStatusText == null) {
      _centerStatusText = TextComponent(
        text: text,
        position: Vector2(800, 210),
        anchor: Anchor.center,
        priority: 1000,
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Color(0xFFFFF3CE),
            fontSize: 30,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                blurRadius: 8,
                color: Color(0xCC000000),
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      );
      world.add(_centerStatusText!);
      return;
    }
    _centerStatusText!.text = text;
  }

  void _hideWaitingOverlay() {
    _centerStatusText?.removeFromParent();
    _centerStatusText = null;
  }

  void _renderHand(List<dynamic> hand) {
    final parsed = <TileModel>[];
    for (final tileData in hand) {
      if (tileData is! Map<String, dynamic>) continue;
      final tileModel = _tileModelFromPayload(tileData);
      if (tileModel == null) continue;
      parsed.add(tileModel);
    }

    final slotPlan = occupiedSlots.isEmpty
        ? _buildSmartRackPlan(parsed.length, parsed)
        : _buildPreservingSlotPlan(parsed);

    // Remove every non-locked tile to prevent orphan rack tiles from
    // previous failed drags/sync races.
    final looseTiles = world.children
        .whereType<TileComponent>()
        .where((tile) => !tile.isLocked)
        .toList(growable: false);
    for (final tile in looseTiles) {
      tile.removeFromParent();
    }
    occupiedSlots.clear();

    for (int i = 0; i < parsed.length && i < slotPlan.length; i++) {
      final tileModel = parsed[i];
      final slotIndex = slotPlan[i];
      if (slotIndex < 0 || slotIndex >= slotPositions.length) continue;

      final tile = TileComponent(
        value: tileModel.value,
        colorType: mapTileColor(tileModel.color),
        position: slotPositions[slotIndex],
        isJoker: tileModel.isJoker,
        isFakeJoker: tileModel.isFakeJoker,
      );

      world.add(tile);
      occupiedSlots[slotIndex] = tile;
      tile.currentSlotIndex = slotIndex;
    }
    _pendingPreferredDrawSlot = null;
  }

  void _clearRenderedHand() {
    if (_deferredTileRemovals.isNotEmpty) {
      final pending = List<TileComponent>.from(_deferredTileRemovals);
      _deferredTileRemovals.clear();
      for (final tile in pending) {
        if (tile.isMounted) {
          tile.removeFromParent();
        }
      }
    }
    activeDraggedTile?.removeFromParent();
    activeDraggedTile = null;
    final looseTiles = world.children
        .whereType<TileComponent>()
        .where((tile) => !tile.isLocked)
        .toList(growable: false);
    for (final tile in looseTiles) {
      tile.removeFromParent();
    }
    occupiedSlots.clear();
    _lastRenderedHandFingerprint = null;
    hasDrawnThisTurn = false;
    _pendingPreferredDrawSlot = null;
    clearPreview();
    clearTemporaryShift();
  }

  void _clearTableVisualState() {
    closedPile.clear();
    _updateClosedPile(0);
    indicatorTileComponent?.removeFromParent();
    indicatorTileComponent = null;
    lastDiscardedTile?.removeFromParent();
    lastDiscardedTile = null;

    for (final tile in _discardTopTilesBySeat.values) {
      tile.removeFromParent();
    }
    _discardTopTilesBySeat.clear();

    for (final slot in _discardSlotsByIndex.values) {
      slot.currentTile = null;
    }
    _recentMoveKeys.clear();
    _recentMoveKeyOrder.clear();
  }

  List<int> _buildPreservingSlotPlan(List<TileModel> tiles) {
    final existingByKey = <String, List<int>>{};
    final existingEntries = occupiedSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in existingEntries) {
      final key = _tileKeyFromComponent(entry.value);
      existingByKey.putIfAbsent(key, () => <int>[]).add(entry.key);
    }

    final usedSlots = <int>{};
    final result = List<int>.filled(tiles.length, -1);

    for (int i = 0; i < tiles.length; i++) {
      final key = _tileKeyFromModel(tiles[i]);
      final slots = existingByKey[key];
      if (slots == null || slots.isEmpty) continue;
      while (slots.isNotEmpty && usedSlots.contains(slots.first)) {
        slots.removeAt(0);
      }
      if (slots.isEmpty) continue;
      final slot = slots.removeAt(0);
      result[i] = slot;
      usedSlots.add(slot);
    }

    final preferred = _pendingPreferredDrawSlot;
    if (preferred != null &&
        preferred >= 0 &&
        preferred < slotPositions.length &&
        !usedSlots.contains(preferred)) {
      final unresolvedIndex = result.indexOf(-1);
      if (unresolvedIndex != -1) {
        result[unresolvedIndex] = preferred;
        usedSlots.add(preferred);
      }
    }

    var nextFree = 0;
    for (int i = 0; i < result.length; i++) {
      if (result[i] != -1) continue;
      while (nextFree < slotPositions.length && usedSlots.contains(nextFree)) {
        nextFree++;
      }
      if (nextFree >= slotPositions.length) break;
      result[i] = nextFree;
      usedSlots.add(nextFree);
      nextFree++;
    }

    for (int i = 0; i < result.length; i++) {
      if (result[i] == -1) {
        result[i] = i.clamp(0, slotPositions.length - 1);
      }
    }
    return result;
  }

  String _tileKeyFromModel(TileModel t) {
    return '${t.color.name}-${t.value}-${t.isJoker ? 1 : 0}-${t.isFakeJoker ? 1 : 0}';
  }

  String _tileKeyFromComponent(TileComponent t) {
    return '${_tileColorToString(t.colorType)}-${t.value}-${t.isJoker ? 1 : 0}-${t.isFakeJoker ? 1 : 0}';
  }

  List<int> _buildSmartRackPlan(int count, List<TileModel> tiles) {
    final refs = <_TileRef>[
      for (int i = 0; i < tiles.length; i++) _TileRef(i, tiles[i]),
    ];
    final remaining = [...refs];
    final groups = <List<_TileRef>>[];

    while (true) {
      final best = _extractBestGroup(remaining);
      if (best == null) break;
      groups.add(best);
      remaining.removeWhere((r) => best.contains(r));
    }

    final orderedBottomTiles = _sortLooseTiles(remaining);

    final placement = List<int>.filled(count, -1);

    final groupRowSlots = <int>[
      for (int i = RackConfig.columns; i < slotPositions.length; i++) i,
    ];
    final looseRowSlots = <int>[
      for (int i = 0; i < RackConfig.columns && i < slotPositions.length; i++)
        i,
    ];

    // ğŸ”¥ CASE 1: hiÃ§ group yok â†’ SPLIT
    if (groups.isEmpty) {
      final topCount = (count / 2).ceil();

      for (int i = 0; i < count; i++) {
        if (i < topCount && i < looseRowSlots.length) {
          placement[i] = looseRowSlots[i];
        } else {
          final bottomIndex = i - topCount;
          if (bottomIndex < groupRowSlots.length) {
            placement[i] = groupRowSlots[bottomIndex];
          }
        }
      }

      return placement;
    }

    // ğŸ”¥ GROUP YERLEÅÄ°MÄ°
    var groupCursor = 0;
    for (final group in groups) {
      final sortedGroup = _sortGroup(group);
      for (final ref in sortedGroup) {
        if (groupCursor >= groupRowSlots.length) break;
        placement[ref.originalIndex] = groupRowSlots[groupCursor];
        groupCursor++;
      }
      if (groupCursor < groupRowSlots.length) {
        groupCursor++; // group gap
      }
      if (groupCursor >= groupRowSlots.length) break;
    }

    // ğŸ”¥ LOOSE YERLEÅÄ°MÄ° (overflow fix ile)
    var looseCursor = 0;
    for (final ref in orderedBottomTiles) {
      if (placement[ref.originalIndex] != -1) continue;

      if (looseCursor < looseRowSlots.length) {
        placement[ref.originalIndex] = looseRowSlots[looseCursor];
        looseCursor++;
      } else {
        // ğŸ”¥ overflow â†’ alt row boÅŸ slot bul
        final nextFree = groupRowSlots.firstWhere(
          (slot) => !placement.contains(slot),
          orElse: () => -1,
        );

        if (nextFree != -1) {
          placement[ref.originalIndex] = nextFree;
        }
      }
    }

    // ğŸ”¥ SAFE FALLBACK (clamp yerine)
    for (int i = 0; i < placement.length; i++) {
      if (placement[i] == -1) {
        final nextFree = List.generate(
          slotPositions.length,
          (i) => i,
        ).firstWhere((slot) => !placement.contains(slot), orElse: () => -1);

        if (nextFree != -1) {
          placement[i] = nextFree;
        }
      }
    }

    return placement;
  }

  void arrangeSerial() {
    if (occupiedSlots.isEmpty) return;
    final entries = occupiedSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final tiles = entries
        .map((e) => _tileModelFromComponent(e.value))
        .toList(growable: false);
    final plan = _buildSmartRackPlan(tiles.length, tiles);
    _applyRackArrangement(
      entries.map((e) => e.value).toList(growable: false),
      plan,
    );
  }

  void arrangePairs() {
    if (occupiedSlots.isEmpty) return;
    final entries = occupiedSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final refs = <_TileRef>[
      for (int i = 0; i < entries.length; i++)
        _TileRef(i, _tileModelFromComponent(entries[i].value)),
    ];

    final byKey = <String, List<_TileRef>>{};
    for (final ref in refs) {
      final key = _tileKeyFromModel(ref.tile);
      byKey.putIfAbsent(key, () => <_TileRef>[]).add(ref);
    }

    final pairGroups = <List<_TileRef>>[];
    final singles = <_TileRef>[];
    for (final list in byKey.values) {
      while (list.length >= 2) {
        pairGroups.add([list.removeAt(0), list.removeAt(0)]);
      }
      if (list.isNotEmpty) {
        singles.addAll(list);
      }
    }

    pairGroups.sort((a, b) {
      final ka = _tileKeyFromModel(a.first.tile);
      final kb = _tileKeyFromModel(b.first.tile);
      return ka.compareTo(kb);
    });
    singles.sort((a, b) {
      final ca = a.tile.color.index.compareTo(b.tile.color.index);
      if (ca != 0) return ca;
      final va = a.tile.value.compareTo(b.tile.value);
      if (va != 0) return va;
      return (a.tile.isJoker ? 1 : 0).compareTo(b.tile.isJoker ? 1 : 0);
    });

    final placement = List<int>.filled(entries.length, -1);
    final pairRowSlots = <int>[
      for (int i = RackConfig.columns; i < slotPositions.length; i++) i,
    ];
    final singleRowSlots = <int>[
      for (int i = 0; i < RackConfig.columns && i < slotPositions.length; i++)
        i,
    ];

    var pairCursor = 0;
    for (final pair in pairGroups) {
      for (final ref in pair) {
        if (pairCursor >= pairRowSlots.length) break;
        placement[ref.originalIndex] = pairRowSlots[pairCursor];
        pairCursor++;
      }
      if (pairCursor < pairRowSlots.length) {
        pairCursor++;
      }
      if (pairCursor >= pairRowSlots.length) break;
    }

    var singleCursor = 0;
    for (final ref in singles) {
      if (singleCursor >= singleRowSlots.length) break;
      if (placement[ref.originalIndex] != -1) continue;
      placement[ref.originalIndex] = singleRowSlots[singleCursor];
      singleCursor++;
    }

    for (int i = 0; i < placement.length; i++) {
      if (placement[i] == -1) {
        placement[i] = i.clamp(0, slotPositions.length - 1);
      }
    }

    _applyRackArrangement(
      entries.map((e) => e.value).toList(growable: false),
      placement,
    );
  }

  TileModel _tileModelFromComponent(TileComponent tile) {
    TileColor color;
    switch (tile.colorType) {
      case TileColorType.red:
        color = TileColor.red;
        break;
      case TileColorType.blue:
        color = TileColor.blue;
        break;
      case TileColorType.black:
        color = TileColor.black;
        break;
      case TileColorType.yellow:
        color = TileColor.yellow;
        break;
    }
    return TileModel(
      value: tile.value,
      color: color,
      isJoker: tile.isJoker,
      isFakeJoker: tile.isFakeJoker,
    );
  }

  void _applyRackArrangement(List<TileComponent> tiles, List<int> plan) {
    occupiedSlots.clear();
    for (int i = 0; i < tiles.length && i < plan.length; i++) {
      final tile = tiles[i];
      final slot = plan[i];
      if (slot < 0 || slot >= slotPositions.length) continue;
      occupiedSlots[slot] = tile;
      tile.currentSlotIndex = slot;
      tile.originalSlotIndex = slot;
      tile.position = slotPositions[slot];
    }
    clearPreview();
    clearTemporaryShift();
  }

  List<_TileRef>? _extractBestGroup(List<_TileRef> refs) {
    if (refs.length < 3) return null;

    final runCandidates = <List<_TileRef>>[];
    for (final color in TileColor.values) {
      final sameColor =
          refs.where((r) => r.tile.color == color && !r.tile.isJoker).toList()
            ..sort((a, b) => a.tile.value.compareTo(b.tile.value));
      if (sameColor.length < 3) continue;
      final byValue = <int, _TileRef>{};
      for (final r in sameColor) {
        byValue.putIfAbsent(r.tile.value, () => r);
      }
      final values = byValue.keys.toList()..sort();
      var current = <_TileRef>[];
      for (final v in values) {
        if (current.isEmpty || v == current.last.tile.value + 1) {
          current.add(byValue[v]!);
        } else {
          if (current.length >= 3) runCandidates.add([...current]);
          current = [byValue[v]!];
        }
      }
      if (current.length >= 3) runCandidates.add([...current]);
    }

    final setCandidates = <List<_TileRef>>[];
    final byNumber = <int, List<_TileRef>>{};
    for (final r in refs.where((r) => !r.tile.isJoker)) {
      byNumber.putIfAbsent(r.tile.value, () => []).add(r);
    }
    for (final entries in byNumber.values) {
      final byColor = <TileColor, _TileRef>{};
      for (final r in entries) {
        byColor.putIfAbsent(r.tile.color, () => r);
      }
      final set = byColor.values.toList();
      if (set.length >= 3) setCandidates.add(set);
    }

    final all = [...runCandidates, ...setCandidates];
    if (all.isEmpty) return null;
    all.sort((a, b) => b.length.compareTo(a.length));
    return all.first;
  }

  List<_TileRef> _sortGroup(List<_TileRef> group) {
    if (group.isEmpty) return group;
    final sameColor = group.every(
      (g) => g.tile.color == group.first.tile.color,
    );
    final sorted = [...group];
    if (sameColor) {
      sorted.sort((a, b) => a.tile.value.compareTo(b.tile.value));
      return sorted;
    }
    sorted.sort((a, b) {
      final byVal = a.tile.value.compareTo(b.tile.value);
      if (byVal != 0) return byVal;
      return a.tile.color.index.compareTo(b.tile.color.index);
    });
    return sorted;
  }

  List<_TileRef> _sortLooseTiles(List<_TileRef> loose) {
    final sorted = [...loose];
    sorted.sort((a, b) {
      if (a.tile.isJoker != b.tile.isJoker) {
        return a.tile.isJoker ? 1 : -1;
      }
      final byColor = a.tile.color.index.compareTo(b.tile.color.index);
      if (byColor != 0) return byColor;
      return a.tile.value.compareTo(b.tile.value);
    });
    return sorted;
  }

  TileModel? _tileModelFromPayload(Map<String, dynamic> raw) {
    final valueRaw = raw['number'] ?? raw['value'];
    final value = valueRaw is int ? valueRaw : int.tryParse('$valueRaw');
    final color = _parseColor(raw['color']);
    if (value == null || color == null) return null;

    return TileModel(
      value: value,
      color: color,
      isJoker:
          raw['joker'] == true ||
          raw['is_joker'] == true ||
          raw['isJoker'] == true,
      isFakeJoker:
          raw['fake_joker'] == true ||
          raw['is_fake_joker'] == true ||
          raw['isFakeJoker'] == true,
    );
  }

  TileColor? _parseColor(dynamic colorRaw) {
    switch ('$colorRaw'.toLowerCase()) {
      case 'red':
        return TileColor.red;
      case 'blue':
        return TileColor.blue;
      case 'black':
        return TileColor.black;
      case 'yellow':
        return TileColor.yellow;
      default:
        return null;
    }
  }

  void _syncDeckFromTable(dynamic deckRaw) {
    closedPile.clear();

    if (deckRaw is List) {
      for (final rawTile in deckRaw) {
        if (rawTile is Map<String, dynamic>) {
          final tile = _tileModelFromPayload(rawTile);
          if (tile != null) {
            closedPile.add(tile);
          }
        }
      }
    }

    final drawableCount = closedPile.isNotEmpty ? closedPile.length - 1 : 0;
    _updateClosedPile(drawableCount);
    _updateIndicatorFromDeck();
  }

  void _subscribeRealtime() {
    _tableChannel?.unsubscribe();
    _tableChannel = Supabase.instance.client
        .channel('table_$tableId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tables',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: tableId,
          ),
          callback: (payload) => _handleTableUpdate(payload.newRecord),
        )
        .subscribe();
  }

  void _subscribeRealtimeMoves() {
    _movesChannel = Supabase.instance.client
        .channel('match_moves:$tableId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'match_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: tableId,
          ),
          callback: (payload) {
            final data = payload.newRecord;
            _onMatchMove(data);
          },
        )
        .subscribe();
  }

  int? _seatFromUserId(String userId) {
    for (final entry in _playerSeatMap.entries) {
      if (entry.value['user_id'].toString() == userId) {
        return entry.key;
      }
    }
    return null;
  }

  void _onMatchMove(Map<String, dynamic> move) {
    final moveKey = _moveDedupeKey(move);
    if (moveKey != null) {
      if (_recentMoveKeys.contains(moveKey)) return;
      _recentMoveKeys.add(moveKey);
      _recentMoveKeyOrder.add(moveKey);
      if (_recentMoveKeyOrder.length > 120) {
        final evict = _recentMoveKeyOrder.removeAt(0);
        _recentMoveKeys.remove(evict);
      }
    }

    final type = move['move_type']?.toString();
    final playerId = move['player_id'];
    final rawTile = move['tile_data'];
    Map<String, dynamic>? tile;
    if (rawTile is String) {
      final decoded = jsonDecode(rawTile);
      if (decoded is Map) tile = Map<String, dynamic>.from(decoded);
    } else if (rawTile is Map) {
      tile = Map<String, dynamic>.from(rawTile);
    }

    final seat = _seatFromUserId(playerId);
    if (seat == null) return;

    if (type == 'draw_discard') {
      final mySeat = _resolveMySeatIndex();
      if (mySeat != null && seat == mySeat) {
        return;
      }
      final rawFromSeat = move['from_seat'] ?? move['source_seat'];
      final fromSeat =
          rawFromSeat is int ? rawFromSeat : int.tryParse('$rawFromSeat');
      _animateDiscardToPlayer(
        fromSeat: fromSeat ?? ((seat - 1 + _maxPlayers) % _maxPlayers),
        toSeat: seat,
        tileData: tile,
      );
      return;
    }

    if (type == 'discard') {
      final mySeat = _resolveMySeatIndex();
      // Local player's manual drag already gives enough feedback.
      if (mySeat != null && seat == mySeat) return;
      _animatePlayerToDiscard(
        seat: seat,
        tileData: tile,
      );
    }
  }

  String? _moveDedupeKey(Map<String, dynamic> move) {
    final id = move['id'];
    if (id != null) return 'id:$id';
    final createdAt = move['created_at']?.toString() ?? '';
    final player = move['player_id']?.toString() ?? '';
    final type = move['move_type']?.toString() ?? '';
    final fromSeat = (move['from_seat'] ?? move['source_seat'])?.toString() ?? '';
    final tileData = move['tile_data'];
    final tileSig = tileData is String ? tileData : (tileData?.toString() ?? '');
    final key = '$createdAt|$player|$type|$fromSeat|$tileSig';
    return key == '||||' ? null : key;
  }

  void _animateDiscardToPlayer({
    required int fromSeat,
    required int toSeat,
    Map<String, dynamic>? tileData,
  }) {
    final fromSlotIndex = _slotIndexForAbsoluteSeat(fromSeat);
    final fromSlot = _discardSlotsByIndex[fromSlotIndex];
    if (fromSlot == null) return;

    final sourceTop = _discardTopTilesBySeat[fromSeat] ?? fromSlot.currentTile;
    final model = tileData != null ? _tileModelFromPayload(tileData) : null;

    final value = model?.value ?? sourceTop?.value;
    final colorType =
        model != null ? mapTileColor(model.color) : sourceTop?.colorType;
    if (value == null || colorType == null) return;

    final transient = TileComponent(
      value: value,
      colorType: colorType,
      position: fromSlot.position.clone(),
      isJoker: model?.isJoker ?? sourceTop?.isJoker ?? false,
      isFakeJoker: model?.isFakeJoker ?? sourceTop?.isFakeJoker ?? false,
    )..priority = 80;
    transient.isLocked = true;
    world.add(transient);

    // Remove old top immediately so it is clear that the tile was taken.
    _discardTopTilesBySeat[fromSeat]?.removeFromParent();
    _discardTopTilesBySeat.remove(fromSeat);
    fromSlot.currentTile = null;

    final target = _drawAnimationTargetForSeat(toSeat);
    transient.add(
      MoveEffect.to(
        target,
        EffectController(duration: 0.28, curve: Curves.easeOutCubic),
      ),
    );

    async.Timer(const Duration(milliseconds: 320), () {
      transient.removeFromParent();
      _emitTileSfx();
    });
  }

  Vector2 _drawAnimationTargetForSeat(int absoluteSeat) {
    final relative = (absoluteSeat - (_mySeatIndexAbs ?? 0) + _maxPlayers) %
        _maxPlayers;
    if (_maxPlayers == 2) {
      return relative == 0 ? Vector2(800, 730) : Vector2(800, 170);
    }
    switch (relative) {
      case 0:
        return Vector2(800, 730);
      case 1:
        return Vector2(330, 520);
      case 2:
        return Vector2(800, 170);
      case 3:
        return Vector2(1270, 520);
      default:
        return Vector2(800, 450);
    }
  }

  void _animatePlayerToDiscard({
    required int seat,
    Map<String, dynamic>? tileData,
  }) {
    final slotIndex = _slotIndexForAbsoluteSeat(seat);
    final slot = _discardSlotsByIndex[slotIndex];
    if (slot == null) return;

    final model = tileData != null ? _tileModelFromPayload(tileData) : null;
    final fallbackTop = _discardTopTilesBySeat[seat] ?? slot.currentTile;
    final value = model?.value ?? fallbackTop?.value;
    final colorType =
        model != null ? mapTileColor(model.color) : fallbackTop?.colorType;
    if (value == null || colorType == null) return;

    final start = _drawAnimationTargetForSeat(seat);
    final transient = TileComponent(
      value: value,
      colorType: colorType,
      position: start,
      isJoker: model?.isJoker ?? fallbackTop?.isJoker ?? false,
      isFakeJoker: model?.isFakeJoker ?? fallbackTop?.isFakeJoker ?? false,
    )..priority = 79;
    transient.isLocked = true;
    world.add(transient);
    _discardAnimationInFlightSeats.add(seat);

    transient.add(
      MoveEffect.to(
        slot.position.clone(),
        EffectController(duration: 0.28, curve: Curves.easeOutCubic),
      ),
    );

    async.Timer(const Duration(milliseconds: 320), () {
      final previousTop = _discardTopTilesBySeat[seat];
      if (previousTop != null && previousTop != transient) {
        previousTop.removeFromParent();
      }
      transient.priority = 50;
      transient.position = slot.position.clone();
      _discardTopTilesBySeat[seat] = transient;
      slot.currentTile = transient;
      _discardAnimationInFlightSeats.remove(seat);
      _syncDiscardTopsFromServer();
      _emitTileSfx();
    });
  }

  bool _sameDiscardVisualTile(TileComponent existing, TileModel model) {
    return existing.value == model.value &&
        existing.colorType == mapTileColor(model.color) &&
        existing.isJoker == model.isJoker &&
        existing.isFakeJoker == model.isFakeJoker;
  }

  void _subscribeTablePlayersRealtime() {
    _tablePlayersChannel?.unsubscribe();
    _tablePlayersChannel = Supabase.instance.client
        .channel('table_players_$tableId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'table_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: tableId,
          ),
          callback: (_) async {
            if (!_gameStarted) {
              await _loadInitialState();
              await _ensureGameStartIfReady();
            }
          },
        )
        .subscribe();
  }

  void _subscribeTableDiscardsRealtime() {
    _tableDiscardsChannel?.unsubscribe();
    _tableDiscardsChannel = Supabase.instance.client
        .channel('table_discards_$tableId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'table_discards',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: tableId,
          ),
          callback: (_) async {
            if (!_gameStarted) return;
            await _syncDiscardTopsFromServer();
          },
        )
        .subscribe();
  }

  Future<void> _handleTableUpdate(Map<String, dynamic> table) async {
    final status = table['status'] as String?;
    if (status == 'playing' && !_gameStarted) {
      _gameStarted = true;
      _hideWaitingOverlay();
      await _loadInitialState();
      return;
    }
    if (status != 'playing' && _gameStarted) {
      _gameStarted = false;

      /// COIN YENÄ°LE
      await _loadInitialState();
      return;
    }

    final turn = table['current_turn'];
    final serverTurnStartedAt = _parseServerTime(table['turn_started_at']);
    if (turn is int) {
      if (currentTurn != turn) {
        _turnStartedAt = serverTurnStartedAt ?? DateTime.now();
        _actionInFlight = false;
        _lastTimeoutTurnToken = null;
      }
      currentTurn = turn;
      hasDrawnThisTurn = _isMyTurn() && occupiedSlots.length >= 15;
    }

    if (table['deck'] != null) {
      _syncDeckFromTable(table['deck']);
    }
  }

  void _updateClosedPile(int count) {
    if (closedPileComponent == null) {
      closedPileComponent = ClosedPileComponent(
        position: Vector2(750, 300),
        initialCount: count,
      );
      world.add(closedPileComponent!);
      return;
    }

    closedPileComponent!.updateCount(count);
  }

  void _updateIndicatorFromDeck() {
    indicatorTileComponent?.removeFromParent();
    indicatorTileComponent = null;
    if (closedPile.isEmpty) return;

    final indicator = closedPile.first;
    final tile = TileComponent(
      value: indicator.value,
      colorType: mapTileColor(indicator.color),
      position: Vector2(860, 300),
      isJoker: indicator.isJoker,
      isFakeJoker: indicator.isFakeJoker,
    )..isLocked = true;
    tile.priority = 55;
    world.add(tile);
    indicatorTileComponent = tile;
  }

  void _initStage() {
    world = World();
    cameraComponent = CameraComponent.withFixedResolution(
      world: world,
      width: 1600,
      height: 900,
    );

    addAll([world, cameraComponent]);
    cameraComponent.viewfinder.position = Vector2(800, 450);

    world.add(Stage());
    slotPositions.addAll(RackSlotGenerator.generate());

    previewBox = PreviewComponent(
      size: Vector2(RackConfig.tileWidth, RackConfig.tileHeight),
    );
    previewBox.isVisible = false;
    world.add(previewBox);

    _updateClosedPile(0);

    final discardPositions = [
      Vector2(350, 300),
      Vector2(1250, 300),
      Vector2(350, 475),
      Vector2(1250, 475),
    ];

    for (int i = 0; i < 4; i++) {
      final discard = DiscardSlotComponent(
        playerIndex: i,
        position: discardPositions[i],
      );
      world.add(discard);
      _discardSlotsByIndex[i] = discard;

      if (i == 3) {
        bottomRightDiscard = discard;
      } else if (i == 2) {
        bottomLeftDiscard = discard;
      }
    }
  }

  Future<void> _syncDiscardTopsFromServer() async {
    if (!_gameStarted) {
      _clearTableVisualState();
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('table_discard_tops')
          .select('seat_index,tile')
          .eq('table_id', tableId);

      final topsBySeat = <int, Map<String, dynamic>>{};
      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final seat = row['seat_index'] as int?;
        final tileRaw = row['tile'];
        if (seat == null || tileRaw is! Map<String, dynamic>) continue;
        topsBySeat[seat] = tileRaw;
      }

      // Clear seats with no top tile.
      for (final seat in List<int>.from(_discardTopTilesBySeat.keys)) {
        if (topsBySeat.containsKey(seat)) continue;
        _discardTopTilesBySeat[seat]?.removeFromParent();
        _discardTopTilesBySeat.remove(seat);
        final slotIndex = _slotIndexForAbsoluteSeat(seat);
        _discardSlotsByIndex[slotIndex]?.currentTile = null;
      }

      // Render/update current tops.
      for (final entry in topsBySeat.entries) {
        final seat = entry.key;
        if (_discardAnimationInFlightSeats.contains(seat)) continue;
        final tileModel = _tileModelFromPayload(entry.value);
        if (tileModel == null) continue;
        final slotIndex = _slotIndexForAbsoluteSeat(seat);
        final slot = _discardSlotsByIndex[slotIndex];
        if (slot == null) continue;
        final existing = _discardTopTilesBySeat[seat];
        if (existing != null && _sameDiscardVisualTile(existing, tileModel)) {
          existing.position = slot.position.clone();
          existing.priority = 50;
          existing.isLocked = true;
          slot.currentTile = existing;
          continue;
        }

        existing?.removeFromParent();
        final tile = TileComponent(
          value: tileModel.value,
          colorType: mapTileColor(tileModel.color),
          position: slot.position.clone(),
          isJoker: tileModel.isJoker,
          isFakeJoker: tileModel.isFakeJoker,
        )..isLocked = true;
        tile.priority = 50;
        world.add(tile);
        _discardTopTilesBySeat[seat] = tile;
        slot.currentTile = tile;
      }
      if (_maxPlayers == 2) {
        final oppSeat = ((_resolveMySeatIndex() ?? 0) + 1) % 2;
        final slot = _discardSlotsByIndex[_slotIndexForAbsoluteSeat(oppSeat)];
        lastDiscardedTile = slot?.currentTile;
      }
    } catch (e) {
      debugPrint('DISCARD TOP SYNC ERROR: $e');
    }
  }

  int _slotIndexForAbsoluteSeat(int absoluteSeat) {
    final my = _mySeatIndexAbs ?? 0;
    final relative = (absoluteSeat - my + _maxPlayers) % _maxPlayers;
    if (_maxPlayers == 2) {
      return relative == 0 ? 3 : 0;
    }
    switch (relative) {
      case 0:
        return 3; // me -> bottom-right
      case 1:
        return 2; // left
      case 2:
        return 0; // top
      case 3:
        return 1; // right
      default:
        return 3;
    }
  }

  DateTime? _parseServerTime(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) return null;
    return parsed.toLocal();
  }

  int _normalizeTurnSeconds(int value) {
    if (value <= 0) return 15;
    if (value < 10) return 10;
    if (value > 60) return 60;
    return value;
  }

  String _handFingerprint(List<dynamic> hand) {
    try {
      return jsonEncode(hand);
    } catch (_) {
      return hand.map((e) => e.toString()).join('|');
    }
  }

  int? _absoluteSeatForSlot(DiscardSlotComponent slot) {
    final my = _mySeatIndexAbs;
    if (my == null) return null;
    final slotIndex = slot.playerIndex;
    int relative;
    if (_maxPlayers == 2) {
      relative = slotIndex == 3 ? 0 : 1;
    } else {
      if (slotIndex == 3) {
        relative = 0;
      } else if (slotIndex == 2) {
        relative = 1;
      } else if (slotIndex == 0) {
        relative = 2;
      } else {
        relative = 3;
      }
    }
    return (my + relative) % _maxPlayers;
  }

  int? _expectedDiscardSeatForCurrentTurn() {
    final mySeat = _resolveMySeatIndex();
    if (mySeat == null) return null;
    return (mySeat - 1 + _maxPlayers) % _maxPlayers;
  }

  bool _canTakeFromDiscardSlot(DiscardSlotComponent slot) {
    if (!_isMyTurn()) return false;
    if (slot.currentTile == null) return false;
    final seat = _absoluteSeatForSlot(slot);
    final expected = _expectedDiscardSeatForCurrentTurn();
    if (seat == null || expected == null) return false;
    return seat == expected;
  }

  Future<void> _serverDraw({required String source, int? fromSeat}) async {
    if (_actionInFlight) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _actionInFlight = true;
    try {
      Future<void> callDraw({int? seat}) async {
        await Supabase.instance.client.rpc(
          'game_draw',
          params: {
            'p_table_id': tableId,
            'p_user_id': userId,
            'p_source': source,
            'p_from_seat': seat,
          },
        );
      }

      await callDraw(seat: fromSeat);
      await _loadInitialState();
      await _syncDiscardTopsFromServer();
      hasDrawnThisTurn = _isMyTurn() && occupiedSlots.length >= 15;
      _emitTileSfx();
    } catch (e) {
      debugPrint('GAME_DRAW RPC ERROR: $e');
      _pendingPreferredDrawSlot = null;
      if ('$e'.contains('NOT_YOUR_TURN')) {
        await _pollLiveTableState();
      }
      if ('$e'.contains('HAND_ALREADY_15')) {
        hasDrawnThisTurn = true;
      }
      await _loadInitialState();
    } finally {
      _actionInFlight = false;
    }
  }

  List<Map<String, dynamic>> _buildSlotsJson(Map<int, TileComponent> slotMap) {
    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < 26; i++) {
      final tile = slotMap[i];

      result.add({
        'i': i,
        'tile': tile != null
            ? {
                'color': _tileColorToString(tile.colorType),
                'number': tile.value,
                'joker': tile.isJoker,
                'fake_joker': tile.isFakeJoker,
              }
            : null,
      });
    }

    return result;
  }

  Future<void> _serverDiscard(TileComponent tile, {bool finish = false}) async {
    if (_actionInFlight) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _actionInFlight = true;

    final slots = finish ? _buildSlotsJson(occupiedSlots) : null;
    try {
      await Supabase.instance.client.rpc(
        'game_discard',
        params: {
          'p_table_id': tableId,
          'p_user_id': userId,
          'p_tile': {
            'color': _tileColorToString(tile.colorType),
            'number': tile.value,
            'joker': tile.isJoker,
            'is_joker': tile.isJoker,
            'fake_joker': tile.isFakeJoker,
            'is_fake_joker': tile.isFakeJoker,
          },
          'p_slots': slots,
          'p_finish': finish,
          'p_is_player_action': true,
        },
      );

      // Re-sync full state from server to avoid turn/desync deadlocks.
      await _loadInitialState();
      await _syncDiscardTopsFromServer();
      hasDrawnThisTurn = false;
      _pendingPreferredDrawSlot = null;
      _emitTileSfx();
    } catch (e) {
      debugPrint('GAME_DISCARD RPC ERROR: $e');
      if ('$e'.contains('NOT_YOUR_TURN')) {
        await _pollLiveTableState();
      }
      await _loadInitialState();
    } finally {
      _actionInFlight = false;
    }
  }

  Future<void> _serverTimeoutMove() async {
    if (_actionInFlight) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) return;
    _actionInFlight = true;
    try {
      // Server-side timeout function is unstable on this backend.
      // Use client fallback directly to keep turn flow deterministic.
      await _runClientTimeoutFallback();
      await _loadInitialState();
    } finally {
      _actionInFlight = false;
    }
  }

  List<Map<String, dynamic>> _buildSlotsJsonFromHand(List hand) {
    final result = <Map<String, dynamic>>[];
    final normalized = hand
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);

    for (int i = 0; i < 26; i++) {
      if (i < normalized.length) {
        final t = normalized[i];
        result.add({
          'i': i,
          'tile': {
            'color': (t['color'] ?? '').toString(),
            'number': (t['number'] ?? t['value'] ?? 0) as int,
            'joker': t['joker'] == true || t['is_joker'] == true,
            'fake_joker': t['fake_joker'] == true || t['is_fake_joker'] == true,
          },
        });
      } else {
        result.add({'i': i, 'tile': null});
      }
    }

    return result;
  }

  Future<void> _runClientTimeoutFallback() async {
    try {
      if (!_isMyTurn()) return;
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      var rows = await Supabase.instance.client
          .from('table_players')
          .select('hand')
          .eq('table_id', tableId)
          .eq('user_id', uid)
          .limit(1);
      if (rows is! List || rows.isEmpty) return;
      var hand = rows.first['hand'];
      if (hand is! List) return;

      if (hand.length == 14) {
        await Supabase.instance.client.rpc(
          'game_draw',
          params: {
            'p_table_id': tableId,
            'p_user_id': uid,
            'p_source': 'closed',
            'p_from_seat': null,
          },
        );
        rows = await Supabase.instance.client
            .from('table_players')
            .select('hand')
            .eq('table_id', tableId)
            .eq('user_id', uid)
            .limit(1);
        if (rows is! List || rows.isEmpty) return;
        hand = rows.first['hand'];
        if (hand is! List) return;
      }

      if (hand.length != 15) return;
      final strategy = decideStrategy(hand);
      final finishTile = _pickFinishDiscardTile(hand);
      final tile = finishTile ??
          pickBestDiscardTile(
            hand,
            strategy,
            protectedKeys: const <String>{},
          );
      final safeTile = _ensureLooseDiscardWhenPossible(hand, tile, strategy);
      final canFinish = finishTile != null;
      final slots = _buildSlotsJsonFromHand(hand);

      await Supabase.instance.client.rpc(
        'game_discard',
        params: {
          'p_table_id': tableId,
          'p_user_id': uid,
          'p_tile': safeTile,
          'p_slots': slots,
          'p_finish': canFinish,
          'p_is_player_action': false,
        },
      );
      hasDrawnThisTurn = false;
      await _syncDiscardTopsFromServer();
    } catch (e) {
      debugPrint('TIMEOUT FALLBACK ERROR: $e');
    }
  }

  int? getNearestSlotIndex(Vector2 pos) {
    double minDist = 60;
    int? nearest;

    for (int i = 0; i < slotPositions.length; i++) {
      final dist = slotPositions[i].distanceTo(pos);
      if (dist < minDist) {
        minDist = dist;
        nearest = i;
      }
    }

    return nearest;
  }

  bool isSlotOccupied(int index) => occupiedSlots.containsKey(index);

  bool isPointNearBottomDiscard(Vector2 worldPoint) {
    final center = bottomRightDiscard.position;
    final dx = (worldPoint.x - center.x).abs();
    final dy = (worldPoint.y - center.y).abs();
    return dx <= 75 && dy <= 95;
  }

  bool isPointNearClosedPile(Vector2 worldPoint) {
    final pile = closedPileComponent;
    if (pile == null) return false;
    final center = pile.position;
    final dx = (worldPoint.x - center.x).abs();
    final dy = (worldPoint.y - center.y).abs();
    return dx <= 85 && dy <= 115;
  }

  void occupySlot(int index, TileComponent tile) {
    occupiedSlots[index] = tile;
  }

  void freeSlot(int index) {
    occupiedSlots.remove(index);
  }

  void drawFromClosedPile() {
    if (hasDrawnThisTurn) return;
    if (occupiedSlots.length >= 15) return;
    if (closedPile.length <= 1) return;
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return;
    }
    _serverDraw(source: 'closed');
  }

  void updatePreview(Vector2 pos) {
    final index = getNearestSlotIndex(pos);
    if (index != null) {
      previewBox.position = slotPositions[index];
      previewBox.isVisible = true;
      applyTemporaryShift(index);
      return;
    }

    previewBox.isVisible = false;
    clearTemporaryShift();
  }

  void clearPreview() {
    previewBox.isVisible = false;
  }

  void insertIntoRow(int targetIndex, TileComponent tile) {
    final row = targetIndex ~/ RackConfig.columns;
    final rowStart = row * RackConfig.columns;
    final rowEnd = rowStart + RackConfig.columns - 1;

    if (tile.currentSlotIndex != null) {
      occupiedSlots.remove(tile.currentSlotIndex);
    }

    if (!occupiedSlots.containsKey(targetIndex)) {
      occupiedSlots[targetIndex] = tile;
      tile.position = slotPositions[targetIndex];
      tile.currentSlotIndex = targetIndex;
      _emitTileSfx();
      return;
    }

    int emptyIndex = -1;
    for (int i = targetIndex + 1; i <= rowEnd; i++) {
      if (!occupiedSlots.containsKey(i)) {
        emptyIndex = i;
        break;
      }
    }

    if (emptyIndex == -1) {
      _restoreTileToOriginalSlot(tile);
      return;
    }

    for (int i = emptyIndex; i > targetIndex; i--) {
      final movingTile = occupiedSlots[i - 1];
      if (movingTile != null) {
        occupiedSlots[i] = movingTile;
        movingTile.position = slotPositions[i];
        movingTile.currentSlotIndex = i;
      }
    }

    occupiedSlots.remove(targetIndex);
    occupiedSlots[targetIndex] = tile;
    tile.position = slotPositions[targetIndex];
    tile.currentSlotIndex = targetIndex;
    _emitTileSfx();
  }

  void _restoreTileToOriginalSlot(TileComponent tile) {
    final original = tile.originalSlotIndex;
    if (original != null &&
        original >= 0 &&
        original < slotPositions.length &&
        !occupiedSlots.containsKey(original)) {
      occupiedSlots[original] = tile;
      tile.currentSlotIndex = original;
      tile.position = slotPositions[original];
      return;
    }

    if (tile.currentSlotIndex != null) {
      final current = tile.currentSlotIndex!;
      if (current >= 0 && current < slotPositions.length) {
        tile.position = slotPositions[current];
        return;
      }
    }

    tile.position = tile.originalPosition;
  }

  void applyTemporaryShift(int targetIndex) {
    if (isTempShiftActive && tempShiftIndex == targetIndex) {
      return;
    }

    clearTemporaryShift();

    final row = targetIndex ~/ RackConfig.columns;
    final rowStart = row * RackConfig.columns;
    final rowEnd = rowStart + RackConfig.columns - 1;

    if (!occupiedSlots.containsKey(targetIndex)) {
      return;
    }

    int emptyIndex = -1;
    for (int i = targetIndex + 1; i <= rowEnd; i++) {
      if (!occupiedSlots.containsKey(i)) {
        emptyIndex = i;
        break;
      }
    }
    if (emptyIndex == -1) return;

    for (int i = emptyIndex; i > targetIndex; i--) {
      final tile = occupiedSlots[i - 1];
      if (tile != null) {
        tile.position = slotPositions[i];
      }
    }

    isTempShiftActive = true;
    tempShiftIndex = targetIndex;
  }

  void clearTemporaryShift() {
    if (!isTempShiftActive) return;

    for (final entry in occupiedSlots.entries) {
      entry.value.position = slotPositions[entry.key];
    }

    isTempShiftActive = false;
    tempShiftIndex = null;
  }

  bool discardTile(TileComponent tile) {
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return false;
    }
    if (_actionInFlight) return false;
    final virtualCount =
        occupiedSlots.length + (tile.currentSlotIndex == null ? 1 : 0);
    if (virtualCount != 15) return false;
    _serverDiscard(tile);
    return true;
  }

  bool finishWithTile(TileComponent tile) {
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return false;
    }
    if (_actionInFlight) return false;
    final virtualCount =
        occupiedSlots.length + (tile.currentSlotIndex == null ? 1 : 0);
    if (virtualCount != 15) return false;
    final finishHand = _buildFinishCandidateHand();
    if (!_isValidFinishHand(finishHand)) {
      _showWaitingOverlay('Elin bitmiyor');
      async.Timer(const Duration(seconds: 2), () {
        if (_gameStarted) {
          _hideWaitingOverlay();
        }
      });
      return false;
    }
    _serverDiscard(tile, finish: true);
    return true;
  }

  void placeDrawnTileIntoRack(TileComponent tile) {
    tile.removeFromParent();
  }

  void drawFromClosedPileDrag(Vector2 startPosition) {
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return;
    }
    startSourceDrawDrag(startPosition: startPosition);
  }

  void takeFromDiscard() {
    final expectedSeat = _expectedDiscardSeatForCurrentTurn();
    if (expectedSeat == null) return;
    final slotIndex = _slotIndexForAbsoluteSeat(expectedSeat);
    final slot = _discardSlotsByIndex[slotIndex];
    if (slot == null || !_canTakeFromDiscardSlot(slot)) return;
    _serverDraw(source: 'discard', fromSeat: expectedSeat);
  }

  void takeFromDiscardDrag(DiscardSlotComponent slot, Vector2 startPosition) {
    startSourceDrawDrag(startPosition: startPosition, fromDiscardSlot: slot);
  }

  void takeFromDiscardTap(DiscardSlotComponent slot) {
    if (occupiedSlots.length >= 15) return;
    if (!_canTakeFromDiscardSlot(slot)) {
      _pollLiveTableState();
      return;
    }
    final fromSeat = _absoluteSeatForSlot(slot);
    if (fromSeat == null) return;
    _serverDraw(source: 'discard', fromSeat: fromSeat);
  }

  void startSourceDrawDrag({
    required Vector2 startPosition,
    DiscardSlotComponent? fromDiscardSlot,
  }) {
    if (occupiedSlots.length >= 15) return;
    if (_actionInFlight) return;
    if (fromDiscardSlot == null && !_isMyTurn()) {
      _pollLiveTableState();
      return;
    }
    if (fromDiscardSlot == null && hasDrawnThisTurn) {
      return;
    }
    if (fromDiscardSlot != null && !_canTakeFromDiscardSlot(fromDiscardSlot)) {
      return;
    }
    _sourceDrawDragActive = true;
    _sourceDrawFromDiscardSlot = fromDiscardSlot;
    _sourceDrawDragPosition = startPosition.clone();
    activeDraggedTile?.removeFromParent();
    activeDraggedTile = _buildSourceDragTile(
      startPosition: _sourceDrawDragPosition!,
      fromDiscardSlot: fromDiscardSlot,
    );
    if (activeDraggedTile != null) {
      activeDraggedTile!.isLocked = true;
      activeDraggedTile!.priority = 130;
      world.add(activeDraggedTile!);
    }
    updatePreview(_sourceDrawDragPosition!);
  }

  void updateSourceDrawDrag(Vector2 localDelta) {
    if (!_sourceDrawDragActive || _sourceDrawDragPosition == null) return;
    final zoom = cameraComponent.viewfinder.zoom;
    _sourceDrawDragPosition = _sourceDrawDragPosition! + (localDelta / zoom);
    if (activeDraggedTile != null) {
      activeDraggedTile!.position = _sourceDrawDragPosition!.clone();
    }
    updatePreview(_sourceDrawDragPosition!);
  }

  void endSourceDrawDrag() {
    if (!_sourceDrawDragActive) {
      activeDraggedTile?.removeFromParent();
      activeDraggedTile = null;
      clearPreview();
      clearTemporaryShift();
      return;
    }

    final pos = _sourceDrawDragPosition;
    final targetSlot = pos == null ? null : getNearestSlotIndex(pos);
    if (targetSlot != null) {
      _pendingPreferredDrawSlot = targetSlot;
    }

    final fromDiscardSlot = _sourceDrawFromDiscardSlot;
    _sourceDrawDragActive = false;
    _sourceDrawFromDiscardSlot = null;
    _sourceDrawDragPosition = null;
    activeDraggedTile?.removeFromParent();
    activeDraggedTile = null;
    clearPreview();
    clearTemporaryShift();

    if (fromDiscardSlot != null) {
      if (!_canTakeFromDiscardSlot(fromDiscardSlot)) {
        _pendingPreferredDrawSlot = null;
        return;
      }
      takeFromDiscardTap(fromDiscardSlot);
    } else {
      drawFromClosedPile();
    }
  }

  TileComponent? _buildSourceDragTile({
    required Vector2 startPosition,
    DiscardSlotComponent? fromDiscardSlot,
  }) {
    final fromDiscardTile = fromDiscardSlot?.currentTile;
    if (fromDiscardTile != null) {
      return TileComponent(
        value: fromDiscardTile.value,
        colorType: fromDiscardTile.colorType,
        position: startPosition.clone(),
        isJoker: fromDiscardTile.isJoker,
        isFakeJoker: fromDiscardTile.isFakeJoker,
      );
    }

    if (closedPile.length > 1) {
      final top = closedPile.last;
      return TileComponent(
        value: top.value,
        colorType: mapTileColor(top.color),
        position: startPosition.clone(),
        isJoker: top.isJoker,
        isFakeJoker: top.isFakeJoker,
      );
    }

    return null;
  }

  List<_FinishTile> _buildFinishCandidateHand() {
    final entries = occupiedSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map((entry) => _FinishTile.fromComponent(entry.value, entry.key))
        .toList();
  }

  List<_FinishTile> buildFinishTilesFromHand(List hand) {
    return hand.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;

      final t = BotTile.fromJson(e);

      return _FinishTile(
        id: _tileId(t, i), // âœ… int
        number: t.value,
        colorType: _mapColor(t.color),
        isJoker: t.joker,
      );
    }).toList();
  }

  int _tileId(BotTile t, int index) {
    // color hash + value + index ile unique yap
    return t.value * 100 + t.color.hashCode.abs() % 100 + index;
  }

  TileColorType _mapColor(String color) {
    switch (color) {
      case 'red':
        return TileColorType.red;
      case 'blue':
        return TileColorType.blue;
      case 'black':
        return TileColorType.black;
      case 'yellow':
        return TileColorType.yellow;
      default:
        return TileColorType.red;
    }
  }

  bool _isValidFinishHand(List<_FinishTile> hand) {
    if (hand.isEmpty) return false;
    if (hand.length % 3 != 2) return false;
    final memo = <String, bool>{};
    return _canFinishRecursive(hand, memo);
  }

  bool _canFinishRecursive(List<_FinishTile> hand, Map<String, bool> memo) {
    if (hand.isEmpty) return true;
    final key = _finishMemoKey(hand);
    final cached = memo[key];
    if (cached != null) return cached;

    final sorted = [...hand]..sort(_finishTileSort);
    final jokers = sorted.where((t) => t.isJoker).toList();
    final nonJokers = sorted.where((t) => !t.isJoker).toList();

    if (nonJokers.isEmpty) {
      final ok = _canPartitionJokerOnly(sorted.length);
      memo[key] = ok;
      return ok;
    }

    final first = nonJokers.first;

    // Set denemeleri: ayni sayi, farkli renk.
    final sameNumber = nonJokers
        .where((t) => t.number == first.number)
        .toList();
    final uniqueByColor = <TileColorType, _FinishTile>{};
    for (final tile in sameNumber) {
      uniqueByColor.putIfAbsent(tile.colorType, () => tile);
    }
    final uniqueColors = uniqueByColor.values.toList();

    final allSetGroups = <List<_FinishTile>>[];
    final setGroupKeys = <String>{};
    for (final targetSize in const [3, 4]) {
      final maxNonJokerCount = uniqueColors.length.clamp(1, targetSize);
      for (
        int nonJokerCount = 1;
        nonJokerCount <= maxNonJokerCount;
        nonJokerCount++
      ) {
        final jokerNeed = targetSize - nonJokerCount;
        if (jokerNeed < 0 || jokerNeed > jokers.length) continue;
        final combos = _tileCombinations(uniqueColors, nonJokerCount);
        for (final combo in combos) {
          if (!combo.contains(first)) continue;
          final group = [...combo, ...jokers.take(jokerNeed)];
          final key =
              (group.map((t) => t.id).toList()..sort((a, b) => a.compareTo(b)))
                  .join(',');
          if (setGroupKeys.add(key)) {
            allSetGroups.add(group);
          }
        }
      }
    }

    for (final group in allSetGroups) {
      if (!group.contains(first)) continue;
      final remaining = _removeTilesById(sorted, group);
      if (_canFinishRecursive(remaining, memo)) {
        memo[key] = true;
        return true;
      }
    }

    // Seri denemeleri: ayni renk, artan sayi, joker bosluk doldurur.
    final sameColor =
        nonJokers.where((t) => t.colorType == first.colorType).toList()
          ..sort((a, b) {
            int order(int n) {
              return n == 1 ? 14 : n; // 1'i en sona at
            }

            return order(a.number).compareTo(order(b.number));
          });

    var run = <_FinishTile>[first];
    var neededJokers = 0;

    // Joker ile başlayan/biten seri varyasyonlarını da dene.
    // Mevcut akış sadece aradaki boşluğu joker ile dolduruyordu.
    void tryRunWithExtraJokers() {
      final remainingJokers = jokers.length - neededJokers;
      final maxExtra = remainingJokers.clamp(0, 3);
      for (int extra = 0; extra <= maxExtra; extra++) {
        final totalGroupSize = run.length + neededJokers + extra;
        if (totalGroupSize < 3) continue;
        final usedJokers = jokers.take(neededJokers + extra).toList();
        final group = [...run, ...usedJokers];
        final remaining = _removeTilesById(sorted, group);
        if (_canFinishRecursive(remaining, memo)) {
          memo[key] = true;
          throw const _FinishSolved();
        }
      }
    }

    try {
      tryRunWithExtraJokers();

      for (final candidate in sameColor.skip(1)) {
        int diff;

        if (candidate.number == run.last.number + 1) {
          diff = 1;
        } else if (run.last.number == 13 && candidate.number == 1) {
          diff = 1;
        } else if (candidate.number > run.last.number) {
          diff = candidate.number - run.last.number;
        } else {
          break;
        }

        if (diff == 0) {
          continue;
        }
        if (diff == 1) {
          run = [...run, candidate];
        } else {
          final need = diff - 1;
          if (need <= (jokers.length - neededJokers)) {
            neededJokers += need;
            run = [...run, candidate];
          } else {
            break;
          }
        }

        tryRunWithExtraJokers();
      }
    } on _FinishSolved {
      return true;
    }

    memo[key] = false;
    return false;
  }

  bool _canPartitionJokerOnly(int count) {
    if (count == 0) return true;
    if (count < 3) return false;
    if (_canPartitionJokerOnly(count - 3)) return true;
    if (_canPartitionJokerOnly(count - 4)) return true;
    return false;
  }

  int _finishTileSort(_FinishTile a, _FinishTile b) {
    if (a.isJoker != b.isJoker) {
      return a.isJoker ? 1 : -1;
    }
    if (a.colorType != b.colorType) {
      return a.colorType.index.compareTo(b.colorType.index);
    }
    return a.number.compareTo(b.number);
  }

  String _finishMemoKey(List<_FinishTile> hand) {
    final parts =
        hand
            .map((t) => t.isJoker ? 'J' : '${t.colorType.index}-${t.number}')
            .toList()
          ..sort();
    return parts.join('|');
  }

  List<List<_FinishTile>> _tileCombinations(
    List<_FinishTile> input,
    int choose,
  ) {
    final out = <List<_FinishTile>>[];
    void walk(int start, List<_FinishTile> current) {
      if (current.length == choose) {
        out.add([...current]);
        return;
      }
      for (int i = start; i < input.length; i++) {
        current.add(input[i]);
        walk(i + 1, current);
        current.removeLast();
      }
    }

    walk(0, <_FinishTile>[]);
    return out;
  }

  List<_FinishTile> _removeTilesById(
    List<_FinishTile> source,
    List<_FinishTile> toRemove,
  ) {
    final removeIds = toRemove.map((t) => t.id).toSet();
    return source.where((t) => !removeIds.contains(t.id)).toList();
  }
}

class _TileRef {
  final int originalIndex;
  final TileModel tile;

  _TileRef(this.originalIndex, this.tile);
}

class _FinishTile {
  final int id;
  final int number;
  final TileColorType colorType;
  final bool isJoker;

  _FinishTile({
    required this.id,
    required this.number,
    required this.colorType,
    required this.isJoker,
  });

  factory _FinishTile.fromComponent(TileComponent tile, int id) {
    return _FinishTile(
      id: id,
      number: tile.value,
      colorType: tile.colorType,
      isJoker: tile.isJoker,
    );
  }
}

class BotTile {
  final int value;
  final String color;
  final bool joker;
  bool get isOkey => joker == true;
  BotTile(this.value, this.color, this.joker);

  factory BotTile.fromJson(Map<String, dynamic> json) {
    return BotTile(
      json['value'] ?? json['number'] ?? 0, // ğŸ”¥ FIX
      json['color'] ?? '',
      json['joker'] == true ||
          json['is_joker'] == true ||
          json['is_fake_joker'] == true, // ğŸ”¥ EKSTRA
    );
  }
}

bool botCanFinish(List hand) {
  if (hand.length != 15) return false;

  for (int i = 0; i < hand.length; i++) {
    final copy = List.from(hand)..removeAt(i);

    if (_isWinning14(copy)) {
      return true;
    }
  }

  return false;
}

bool _isWinning14(List hand) {
  final analysis = analyzeHand(hand);

  int groups = analysis.runs.length + analysis.sets.length;

  return groups >= 4;
}

bool shouldTakeDiscard(
  List hand,
  Map<String, dynamic>? topDiscard,
  String strategy,
) {
  if (topDiscard == null) return false;

  final t = BotTile.fromJson(topDiscard);
  final tiles = hand.map((e) => BotTile.fromJson(e)).toList();

  if (t.joker) return false;

  int score = 0;

  // SET
  final sameCount = tiles.where((x) => x.value == t.value).length;

  if (sameCount >= 2)
    score += 100; // direkt set
  else if (sameCount == 1)
    score += 40; // set adayÄ±

  // RUN
  final hasCloseNeighbor = tiles.any(
    (x) =>
        x.color == t.color &&
        (x.value == t.value - 1 || x.value == t.value + 1),
  );

  final hasNearNeighbor = tiles.any(
    (x) =>
        x.color == t.color &&
        (x.value == t.value - 2 || x.value == t.value + 2),
  );

  if (hasCloseNeighbor) score += 60;
  if (hasNearNeighbor) score += 30;

  // STRATEGY BOOST
  if (strategy == 'run' && hasCloseNeighbor) score += 20;
  if (strategy == 'set' && sameCount >= 1) score += 20;

  return score >= 40;
}

Map<String, dynamic> pickWorstTile(List hand, String strategy) {
  final normalized = hand
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  if (normalized.isEmpty) {
    return <String, dynamic>{'value': 1, 'color': 'red'};
  }

  final tiles = normalized.map((e) => BotTile.fromJson(e)).toList();
  final analysis = analyzeHand(hand);

  final protected = <BotTile>{};

  for (var r in analysis.runs) {
    protected.addAll(r);
  }
  for (var s in analysis.sets) {
    protected.addAll(s);
  }

  BotTile? worst;
  int worstScore = 999999;

  for (var t in tiles) {
    // âŒ joker asla atÄ±lmaz
    if (t.isOkey) continue;

    int score = 0;

    // ğŸ”’ full group
    if (protected.contains(t)) {
      score += 100;
    }

    // ğŸ”¶ near run
    final hasNeighbor = tiles.any(
      (x) =>
          x != t &&
          x.color == t.color &&
          (x.value == t.value - 1 ||
              x.value == t.value + 1 ||
              (t.value == 1 && x.value == 13) ||
              (t.value == 13 && x.value == 1)),
    );

    if (hasNeighbor) score += 40;

    // ğŸ”¶ pair
    final sameCount = tiles.where((x) => x != t && x.value == t.value).length;
    if (sameCount >= 1) score += 30;

    // ğŸ¯ orta deÄŸer
    if (t.value >= 6 && t.value <= 9) score += 5;

    // âš ï¸ uÃ§ deÄŸer
    if (t.value <= 2 || t.value >= 12) score -= 5;

    // ğŸ’€ dead tile
    if (!hasNeighbor && sameCount == 0 && !protected.contains(t)) {
      score -= 50;
    }

    if (strategy == 'run') {
      // set'e giden taÅŸlarÄ± biraz dÃ¼ÅŸÃ¼r
      if (sameCount >= 1) score -= 10;
    }

    if (strategy == 'set') {
      // run'a giden taÅŸlarÄ± biraz dÃ¼ÅŸÃ¼r
      if (hasNeighbor) score -= 10;
    }

    if (score < worstScore) {
      worstScore = score;
      worst = t;
    }
  }

  worst ??= tiles.firstWhere(
    (x) => !x.isOkey,
    orElse: () => tiles.last,
  );

  for (final tile in normalized) {
    final value = (tile['value'] ?? tile['number'] ?? 0) as int;
    final color = (tile['color'] ?? '').toString();
    if (value == worst!.value && color == worst.color) {
      return tile;
    }
  }

  for (final tile in normalized) {
    final isJoker = tile['joker'] == true ||
        tile['is_joker'] == true ||
        tile['fake_joker'] == true ||
        tile['is_fake_joker'] == true;
    if (!isJoker) return tile;
  }

  return normalized.first;
}

class _FinishSolved implements Exception {
  const _FinishSolved();
}

Map<String, dynamic> pickBestDiscardTile(
  List hand,
  String strategy, {
  Set<String> protectedKeys = const <String>{},
}) {
  final normalized = hand
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  if (normalized.isEmpty) {
    return <String, dynamic>{'value': 1, 'color': 'red'};
  }

  final analysis = analyzeHand(normalized);
  final groupedCounts = <String, int>{};
  final groupedKeySet = <String>{};
  String keyOf(Map<String, dynamic> t) =>
      '${(t['color'] ?? '').toString()}-${(t['value'] ?? t['number'] ?? 0)}';
  for (final run in analysis.runs) {
    for (final t in run) {
      final k = '${t.color}-${t.value}';
      groupedKeySet.add(k);
      groupedCounts[k] = (groupedCounts[k] ?? 0) + 1;
    }
  }
  for (final set in analysis.sets) {
    for (final t in set) {
      final k = '${t.color}-${t.value}';
      groupedKeySet.add(k);
      groupedCounts[k] = (groupedCounts[k] ?? 0) + 1;
    }
  }

  final candidates = <int>[];
  for (int i = 0; i < normalized.length; i++) {
    if (!_botIsJokerMap(normalized[i])) {
      candidates.add(i);
    }
  }
  if (candidates.isEmpty) return normalized.first;

  // Human-like priority: discard loose tiles first.
  final looseCandidates = <int>[];
  for (final idx in candidates) {
    final key = keyOf(normalized[idx]);
    final left = groupedCounts[key] ?? 0;
    if (left > 0) {
      groupedCounts[key] = left - 1;
    } else {
      looseCandidates.add(idx);
    }
  }
  // Hard guard: if there are clearly non-group keys, never discard grouped keys.
  final nonGroupKeyCandidates = candidates
      .where((idx) => !groupedKeySet.contains(keyOf(normalized[idx])))
      .toList(growable: false);
  final evaluationCandidates = nonGroupKeyCandidates.isNotEmpty
      ? nonGroupKeyCandidates
      : (looseCandidates.isNotEmpty ? looseCandidates : candidates);

  Map<String, dynamic>? bestTile;
  var bestPotential = -1 << 30;
  var bestUsefulness = 1 << 30;
  var bestProtectedPenalty = 1 << 30;

  for (final idx in evaluationCandidates) {
    final tile = normalized[idx];
    final remaining = <Map<String, dynamic>>[];
    for (int i = 0; i < normalized.length; i++) {
      if (i != idx) remaining.add(normalized[i]);
    }

    final potential = _handPotentialScore(remaining);
    final usefulness = _tileUsefulnessScore(tile, normalized, strategy);
    final protectedPenalty =
        protectedKeys.contains(_botTileMapKey(tile)) ? 1000 : 0;

    final betterPotential = potential > bestPotential;
    final equalPotential = potential == bestPotential;
    final betterPenalty =
        equalPotential && protectedPenalty < bestProtectedPenalty;
    final equalPenalty = equalPotential && protectedPenalty == bestProtectedPenalty;
    final betterUsefulness = equalPenalty && usefulness < bestUsefulness;

    if (betterPotential || betterPenalty || betterUsefulness) {
      bestTile = tile;
      bestPotential = potential;
      bestUsefulness = usefulness;
      bestProtectedPenalty = protectedPenalty;
    }
  }

  return bestTile ?? pickWorstTile(hand, strategy);
}

int _handPotentialScore(List<Map<String, dynamic>> hand) {
  final analysis = analyzeHand(hand);
  var score = 0;

  for (final run in analysis.runs) {
    score += run.length * 18;
  }
  for (final set in analysis.sets) {
    score += set.length * 18;
  }

  final tiles = hand.map((e) => BotTile.fromJson(e)).toList();
  for (final t in tiles) {
    final sameCount = tiles.where((x) => x != t && x.value == t.value).length;
    if (sameCount >= 1) score += 6;

    final closeNeighbor = tiles.any(
      (x) =>
          x != t &&
          x.color == t.color &&
          (x.value == t.value - 1 ||
              x.value == t.value + 1 ||
              (t.value == 1 && x.value == 13) ||
              (t.value == 13 && x.value == 1)),
    );
    if (closeNeighbor) score += 8;
  }

  return score;
}

bool _botIsJokerMap(Map<String, dynamic> tile) {
  return tile['joker'] == true ||
      tile['is_joker'] == true ||
      tile['fake_joker'] == true ||
      tile['is_fake_joker'] == true;
}

String _botTileMapKey(Map<String, dynamic> tile) {
  final value = (tile['value'] ?? tile['number'] ?? 0) as int;
  final color = (tile['color'] ?? '').toString();
  final joker = _botIsJokerMap(tile) ? 1 : 0;
  return '$color-$value-$joker';
}

int _tileUsefulnessScore(
  Map<String, dynamic> tile,
  List<Map<String, dynamic>> hand,
  String strategy,
) {
  final t = BotTile.fromJson(tile);
  final tiles = hand.map((e) => BotTile.fromJson(e)).toList();

  var score = 0;
  final sameCount = tiles.where((x) => x.value == t.value).length - 1;
  if (sameCount >= 2) score += 60;
  if (sameCount == 1) score += 25;

  final hasCloseNeighbor = tiles.any(
    (x) =>
        x.color == t.color &&
        x.value != t.value &&
        (x.value == t.value - 1 ||
            x.value == t.value + 1 ||
            (t.value == 1 && x.value == 13) ||
            (t.value == 13 && x.value == 1)),
  );
  if (hasCloseNeighbor) score += 45;

  final hasNearNeighbor = tiles.any(
    (x) =>
        x.color == t.color &&
        x.value != t.value &&
        (x.value == t.value - 2 || x.value == t.value + 2),
  );
  if (hasNearNeighbor) score += 15;

  if (strategy == 'run' && hasCloseNeighbor) score += 10;
  if (strategy == 'set' && sameCount >= 1) score += 10;

  if (t.value >= 6 && t.value <= 9) score += 5;
  return score;
}

class HandAnalysis {
  List<List<BotTile>> runs = [];
  List<List<BotTile>> sets = [];
  List<BotTile> useless = [];
}

HandAnalysis analyzeHand(List hand) {
  final tiles = hand
      .whereType<Map>()
      .map((e) => BotTile.fromJson(Map<String, dynamic>.from(e)))
      .toList();
  final result = HandAnalysis();

  final byColor = <String, List<BotTile>>{};

  for (var t in tiles) {
    if (t.isOkey) continue;
    byColor.putIfAbsent(t.color, () => []).add(t);
  }

  /// seri analizi
  for (var color in byColor.keys) {
    final list = [...byColor[color]!];
    list.sort((a, b) => a.value.compareTo(b.value));

    // For runs, duplicate numbers of the same color don't extend sequence.
    final uniqueByValue = <int, BotTile>{};
    for (final t in list) {
      uniqueByValue.putIfAbsent(t.value, () => t);
    }
    final values = uniqueByValue.keys.toList()..sort();

    var current = <BotTile>[];
    for (final v in values) {
      final tile = uniqueByValue[v]!;
      if (current.isEmpty) {
        current.add(tile);
      } else if (v == current.last.value + 1 ||
          (current.last.value == 13 && v == 1)) {
        current.add(tile);
      } else {
        if (current.length >= 3) result.runs.add(List<BotTile>.from(current));
        current = [tile];
      }
    }
    if (current.length >= 3) result.runs.add(List<BotTile>.from(current));
  }

  /// per analizi
  final byValue = <int, List<BotTile>>{};

  for (var t in tiles) {
    if (t.isOkey) continue;
    byValue.putIfAbsent(t.value, () => []).add(t);
  }

  for (final valueGroup in byValue.values) {
    // Sets must be same number, different colors.
    final uniqueByColor = <String, BotTile>{};
    for (final t in valueGroup) {
      uniqueByColor.putIfAbsent(t.color, () => t);
    }
    final set = uniqueByColor.values.toList();
    if (set.length >= 3) {
      result.sets.add(set);
    }
  }

  return result;
}

