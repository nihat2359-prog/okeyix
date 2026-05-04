import 'dart:async' as async;
import 'dart:async';
import 'dart:convert';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart';
import 'package:okeyix/core/app_msg.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/components/closed_pile_component.dart';
import 'package:okeyix/game/components/discard_slot_component.dart';
import 'package:okeyix/game/components/finish_screen.dart';
import 'package:okeyix/game/components/seat_component.dart';
import 'package:okeyix/game/mappers/tile_mapper.dart';
import 'package:okeyix/game/rack/preview_component.dart';
import 'package:okeyix/game/rack/rack_config.dart';
import 'package:okeyix/game/rack/rack_slot_generator.dart';
import 'package:okeyix/game/rack/tile_component.dart';
import 'package:okeyix/game/stage.dart';
import 'package:okeyix/main.dart';
import 'package:okeyix/game/components/finish_rack.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OkeyGame extends FlameGame with TapDetector {
  @override
  Color backgroundColor() => const Color(0x00000000);

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
  bool _botTurnInFlight = false;
  bool _stateSyncInFlight = false;
  bool _countdownInProgress = false;
  bool _countdownTriggeredForThisFullState = false;
  String? _lastNonPlayingVisualKey;
  int _maxPlayers = 2;
  int _tableEntry = 0;
  int _countdownSecondsLeft = 0;
  int _turnSeconds = 15;
  int? _mySeatIndexAbs;
  int _round = 1;
  int _pot = 0;
  VoidCallback? onHudChanged;
  DateTime? _turnStartedAt;
  DateTime? _enteredPlayingAt;
  String? _lastRenderedHandFingerprint;
  String? _lastDeckVisualSignature;
  int _myHandCount = 0;
  bool _sourceDrawDragActive = false;
  Vector2? _sourceDrawDragPosition;
  DiscardSlotComponent? _sourceDrawFromDiscardSlot;
  int? _pendingPreferredDrawSlot;
  String? _lastTimeoutTurnToken;
  String? _lastBotTurnToken;
  Function()? onFinish;
  int? _hoverIndex;
  Timer? _hoverTimer;
  bool _uiLocked = false;
  bool _networkInFlight = false;
  DateTime? _lastDrawAttemptAt;
  final bool _stabilityMode = false;
  final List<Map<String, dynamic>> _moveQueue = [];
  bool _processingQueue = false;
  final List<Vector2> slotPositions = [];
  final Map<int, TileComponent> occupiedSlots = {};
  final Map<String, int> _lastKnownSlotByTileId = {};
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
  final Map<int, DateTime> _discardSyncHoldUntilBySeat = {};
  final bool _suppressRemoteDiscardTopAutoCreate = false;
  final Map<int, List<TileModel>> _discardStacksBySeat = {};
  final Set<String> _recentMoveKeys = <String>{};
  final List<String> _recentMoveKeyOrder = <String>[];
  final List<TileComponent> _deferredTileRemovals = [];
  FinishRack? _finishRack;
  FinishRackView? finishView;
  List<Map<String, dynamic>> playersWithProfiles = [];
  bool isFinishOpen = false;
  OkeyGame({required this.tableId, required this.isCreator, this.onTileSfx});

  bool get gameStarted => _gameStarted;
  bool _kickedHandled = false;
  int getRound() => _round;
  int getPot() => _pot;
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

  void showFinishFromGame(
    List<Map<String, dynamic>> slots,
    Map<String, dynamic> tile,
    String playerName,
    bool isWinner,
    bool isSpectator,
    int winAmount,
    bool isOkeyFinish,
    bool isDoubleFinish,
  ) {
    finishView?.removeFromParent();

    finishView = FinishRackView(
      slots,
      tile,
      playerName,
      isWinner,
      isSpectator,
      winAmount,
      isOkeyFinish,
      isDoubleFinish,
    )..priority = 9999;

    isFinishOpen = true;

    for (final slot in _discardSlotsByIndex.values) {
      slot.setHidden(true);
    }
    closedPileComponent?.setHidden(true);
    camera.viewport.add(finishView!);

    Future.delayed(const Duration(seconds: 4), () {
      hideFinish();
    });
  }

  void hideFinish() {
    finishView?.removeFromParent();
    finishView = null;
    isFinishOpen = false;
    _finishShown = false;
    for (final slot in _discardSlotsByIndex.values) {
      slot.setHidden(false);
      slot.onLoad();
    }
    closedPileComponent?.setHidden(false);
  }

  void showFinish(
    List<Map<String, dynamic>> slots,
    String name,
    bool isWinner,
    bool isSpectator,
  ) {
    _finishRack?.removeFromParent(); // varsa sil

    _finishRack = FinishRack(slots, name, isWinner, isSpectator);
    overlays.remove('Avatars');
    world.add(_finishRack!);
    onFinish?.call();
  }

  void requestDoubleMode() {
    overlays.add('DoubleConfirm');

    //  testFinish();
    // return;
  }

  void testFinish() {
    final testSlots = [
      {"i": 0},
      {"i": 1},
      {"i": 2},
      {"i": 3},
      {
        "i": 4,
        "tile": {
          "id": "T-0086",
          "color": 1,
          "value": 11,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 5,
        "tile": {
          "id": "T-0094",
          "color": 1,
          "value": 12,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 6,
        "tile": {
          "id": "T-0102",
          "color": 1,
          "value": 13,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {"i": 7},
      {"i": 8},
      {"i": 9},
      {"i": 10},
      {"i": 11},
      {"i": 12},
      {
        "i": 13,
        "tile": {
          "id": "T-0001",
          "color": 0,
          "value": 1,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 14,
        "tile": {
          "id": "T-0009",
          "color": 0,
          "value": 2,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 15,
        "tile": {
          "id": "T-0021",
          "color": 0,
          "value": 3,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 16,
        "tile": {
          "id": "T-0025",
          "color": 0,
          "value": 4,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {"i": 17},
      {
        "i": 18,
        "tile": {
          "id": "T-0077",
          "color": 0,
          "value": 10,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 19,
        "tile": {
          "id": "T-0085",
          "color": 0,
          "value": 11,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 20,
        "tile": {
          "id": "T-0089",
          "color": 0,
          "value": 12,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 21,
        "tile": {
          "id": "T-0101",
          "color": 0,
          "value": 13,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {"i": 22},
      {
        "i": 23,
        "tile": {
          "id": "T-0005",
          "color": 0,
          "value": 1,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 24,
        "tile": {
          "id": "T-0002",
          "color": 1,
          "value": 1,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
      {
        "i": 25,
        "tile": {
          "id": "T-0003",
          "color": 2,
          "value": 1,
          "isJoker": false,
          "isFakeJoker": false,
        },
      },
    ];

    final finishTile = {
      "id": "T-0096",
      "color": 3,
      "value": 12,
      "isJoker": false,
      "isFakeJoker": false,
    };
    showFinishFromGame(
      testSlots,
      finishTile,
      "Oyuncu",
      true,
      false,
      100,
      false, // 🔥 çanak
      false,
    );
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

  Map<String, dynamic>? getMyUser() {
    if (_mySeatIndexAbs == null) return null;

    final player = _playerSeatMap[_mySeatIndexAbs];
    if (player == null) return null;

    return player['user'];
  }

  Map<String, dynamic>? getWinnerUser(String? winnerSeat) {
    if (winnerSeat == null) return null;

    final seat = int.tryParse(winnerSeat);
    if (seat == null) return null;

    final player = _playerSeatMap[seat];
    if (player == null) return null;

    return player['user'];
  }

  bool isMeWinner(String? winnerUserId) {
    final myUser = getMyUser();

    if (myUser == null || winnerUserId == null) return false;

    return myUser['id']?.toString() == winnerUserId;
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

  double getTurnProgress() {
    if (!_gameStarted) return 1.0;
    if (!_isMyTurn()) return 1.0;

    final startAt = _turnStartedAt;
    if (startAt == null) return 1.0;

    final elapsed = DateTime.now().difference(startAt).inMilliseconds / 1000.0;

    return ((_turnSeconds - elapsed) / _turnSeconds).clamp(0.0, 1.0);
  }

  void onTileDoubleTap(TileComponent tile) {
    if (_actionInFlight) return;

    if (!_isMyTurn()) return;

    final virtualCount =
        occupiedSlots.length + (tile.currentSlotIndex == null ? 1 : 0);
    final canDiscardNow = hasDrawnThisTurn || virtualCount == 15;
    if (!canDiscardNow) return;

    autoDiscard(tile);
  }

  Future<void> autoDiscard(TileComponent tile) async {
    if (_uiLocked) return;

    _uiLocked = true;

    final originalPos = tile.position.clone();
    final targetPos = getMyDiscardPosition(tile);

    tile.add(
      MoveEffect.to(
        targetPos,
        EffectController(duration: 0.18, curve: Curves.easeOut),
        onComplete: () async {
          final success = await _serverDiscard(tile);
          _isAnimatingRemoteMove = false;
          if (!success) {
            tile.add(
              MoveEffect.to(originalPos, EffectController(duration: 0.2)),
            );
          }

          _uiLocked = false;
        },
      ),
    );
  }

  Vector2 getMyDiscardPosition(TileComponent tile) {
    final pos =
        bottomRightDiscard.absolutePosition + bottomRightDiscard.size / 2;

    return pos - tile.size / 2;
  }

  void _placeMyDiscardTopImmediately(TileComponent tile) {
    final mySeat = _mySeatIndexAbs;
    if (mySeat == null) {
      tile.removeFromParent();
      return;
    }

    final slotIndex = _slotIndexForAbsoluteSeat(mySeat);
    final slot = _discardSlotsByIndex[slotIndex];
    if (slot == null) {
      tile.removeFromParent();
      return;
    }

    final previousTop = _discardTopTilesBySeat[mySeat];
    if (previousTop != null && previousTop != tile) {
      previousTop.removeFromParent();
    }

    tile.priority = 50;
    tile.isLocked = true;
    tile.position = slot.position.clone();
    _discardTopTilesBySeat[mySeat] = tile;
    slot.currentTile = tile;
  }

  void _showMyDiscardTopOptimistic(TileModel model) {
    final mySeat = _mySeatIndexAbs;
    if (mySeat == null) return;
    final slotIndex = _slotIndexForAbsoluteSeat(mySeat);
    final slot = _discardSlotsByIndex[slotIndex];
    if (slot == null) return;

    final previousTop = _discardTopTilesBySeat[mySeat];
    if (previousTop != null) {
      previousTop.removeFromParent();
    }

    final visual = TileComponent(
      tile: model,
      position: slot.position.clone(),
    )
      ..priority = 50
      ..isLocked = true;

    world.add(visual);
    _discardTopTilesBySeat[mySeat] = visual;
    slot.currentTile = visual;
    _pushDiscardStack(mySeat, model);
  }

  TileModel _cloneTileModel(TileModel t) {
    return TileModel(
      id: t.id,
      value: t.value,
      color: t.color,
      isJoker: t.isJoker,
      isFakeJoker: t.isFakeJoker,
    );
  }

  void _pushDiscardStack(int seat, TileModel model) {
    final stack = _discardStacksBySeat.putIfAbsent(seat, () => <TileModel>[]);
    if (stack.isNotEmpty && stack.last.id == model.id) return;
    stack.add(_cloneTileModel(model));
    if (stack.length > 32) {
      stack.removeAt(0);
    }
  }

  TileModel? _popDiscardStack(int seat) {
    final stack = _discardStacksBySeat[seat];
    if (stack == null || stack.isEmpty) return null;
    return stack.removeLast();
  }

  TileModel? _peekDiscardStack(int seat) {
    final stack = _discardStacksBySeat[seat];
    if (stack == null || stack.isEmpty) return null;
    return stack.last;
  }

  void _removeTileFromRackState(TileComponent tile) {
    final keysToRemove = tileComponentMap.entries
        .where((entry) => identical(entry.value, tile))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in keysToRemove) {
      tileComponentMap.remove(key);
    }

    if (tile.currentSlotIndex != null) {
      occupiedSlots.remove(tile.currentSlotIndex);
    } else {
      occupiedSlots.removeWhere((_, v) => identical(v, tile));
    }
    tile.currentSlotIndex = null;
  }

  void scheduleTileRemoval(TileComponent tile) {
    if (_deferredTileRemovals.contains(tile)) return;
    _deferredTileRemovals.add(tile);
  }

  Future<void> _loadInitialState({bool forceHandSync = false}) async {
    final supabase = Supabase.instance.client;
    final wasGameStarted = _gameStarted;

    final res = await supabase.rpc(
      'get_full_table_state',
      params: {'p_table_id': tableId},
    );

    if (res == null) return;

    final table = Map<String, dynamic>.from(res['table']);
    final league = res['league'];
    final rawPlayers = res['players'] as List;
    _maybeShowFinishFromTable(table);

    //-------------------------------------------------
    // TABLE
    //-------------------------------------------------
    _maxPlayers = (table['max_players'] as int?) ?? 2;

    _tableEntry = (table['entry_coin'] as int?) ?? 0;
    final tableRoundRaw = table['round_count'];
    bool roundChanged = false;
    if (tableRoundRaw is int) {
      roundChanged = tableRoundRaw != _round;
      _round = tableRoundRaw < 1 ? 1 : tableRoundRaw;
    }
    if (roundChanged && _gameStarted) {
      // New round started -> allow next finish overlay exactly once.
      _finishShown = false;
      _lastHandledFinishId = null;
    }
    _pot = (table['pot_amount'] as int?) ?? _pot;

    final nextTurn = (table['current_turn'] as int?) ?? 0;
    final serverTurnStartedAt = _parseServerTime(table['turn_started_at']);

    if (currentTurn != nextTurn) {
      _turnStartedAt = serverTurnStartedAt ?? DateTime.now();
      _lastTimeoutTurnToken = null;
    }

    currentTurn = nextTurn;
    _turnStartedAt = serverTurnStartedAt ?? _turnStartedAt ?? DateTime.now();

    //-------------------------------------------------
    // LEAGUE + TURN SECONDS
    //-------------------------------------------------
    if (league != null) {
      _league = Map<String, dynamic>.from(league);

      final leagueTurn = league['turn_seconds'] as int?;
      if (leagueTurn != null && leagueTurn > 0) {
        _turnSeconds = leagueTurn;
      }
    }

    final override = table['turn_seconds'] as int?;
    if (override != null && override > 0) {
      _turnSeconds = override;
    }

    _turnSeconds = _normalizeTurnSeconds(_turnSeconds);

    //-------------------------------------------------
    // PLAYERS (TEK LOOP OPTİMİZE)
    //-------------------------------------------------
    final uid = supabase.auth.currentUser?.id;

    bool stillInTable = false;
    int? mySeat;

    final playersList = <Map<String, dynamic>>[];

    for (final p in rawPlayers) {
      final map = p as Map<String, dynamic>;

      if (map['user_id']?.toString() == uid) {
        stillInTable = true;
        mySeat = map['seat_index'];
      }

      playersList.add(map);
    }

    playersWithProfiles = playersList;
    _mySeatIndexAbs = mySeat;

    //-------------------------------------------------
    // KICK CONTROL
    //-------------------------------------------------
    if (!stillInTable && !_kickedHandled) {
      _kickedHandled = true;

      debugPrint("PLAYER REMOVED FROM TABLE");

      _gameStarted = false;
      overlays.clear();
      overlays.add('LobbyOverlay');
      return;
    }

    //-------------------------------------------------
    // MAPS
    //-------------------------------------------------
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

    //-------------------------------------------------
    // RENDER
    //-------------------------------------------------
    _renderSeats();

    //-------------------------------------------------
    // STATUS
    //-------------------------------------------------
    final status = table['status'] as String?;

    if (status != 'playing') {
      _gameStarted = false;
      _lastTimeoutTurnToken = null;

      _clearRenderedHand();
      _clearTableVisualState();
      _hideWaitingOverlay();

      await _ensureGameStartIfReady(
        knownStatus: status,
        knownPlayerCount: playersWithProfiles.length,
      );
      return;
    }

    //-------------------------------------------------
    // GAME STARTED
    //-------------------------------------------------
    _gameStarted = true;
    _enteredPlayingAt = DateTime.now();
    _cancelStartCountdown();
    _hideWaitingOverlay();

    await Future.wait([
      _ensureFreshTurnStartedAt(
        status: status,
        serverTurnStartedAt: serverTurnStartedAt,
      ),
      _syncDiscardTopsFromServer(),
    ]);

    _turnStartedAt ??= DateTime.now();

    if (isLoaded) {
      final shouldSyncMyHand =
          forceHandSync ||
          !wasGameStarted ||
          tileComponentMap.isEmpty ||
          roundChanged;
      final shouldHardResync =
          shouldSyncMyHand &&
          (roundChanged || !wasGameStarted || tileComponentMap.isEmpty);
      _renderMyHand(
        playersWithProfiles,
        applyServerDiff: shouldSyncMyHand,
        hardReset: shouldHardResync,
      );
    }
  }

  Map<String, dynamic>? getLeague() {
    return _league;
  }

  int getPlayerCount() {
    return _maxPlayers;
  }

  int getTableEntry() {
    return _tableEntry;
  }

  int getTurnSeconds() {
    return _turnSeconds;
  }

  int getMyHandCount() {
    return _myHandCount;
  }

  void resetGameState() {
    _playerSeatMap.clear();
    _botSeats.clear();

    _mySeatIndexAbs = null;
    _maxPlayers = 2;
    _gameStarted = false;

    _tableEntry = 0;
  }

  Future<bool> _tryStartGameOnServer() async {
    if (_startRequestInFlight) return false;
    _startRequestInFlight = true;
    final supabase = Supabase.instance.client;
    try {
      final tableRows = await supabase
          .from('tables')
          .select('status,max_players')
          .eq('id', tableId)
          .limit(1);
      if (tableRows is! List || tableRows.isEmpty) {
        debugPrint('START GAME PRECHECK ERROR: table not found');
        return false;
      }

      final table = Map<String, dynamic>.from(tableRows.first);
      final status = table['status']?.toString() ?? 'waiting';
      final maxPlayers = (table['max_players'] as int?) ?? _maxPlayers;

      final playersRows = await supabase
          .from('table_players')
          .select('id')
          .eq('table_id', tableId);
      final playerCount = (playersRows as List).length;

      if (status == 'playing') {
        if (!_stateSyncInFlight) {
          await _loadInitialState(forceHandSync: true);
        }
        return true;
      }

      if (playerCount < maxPlayers) {
        debugPrint('START GAME PRECHECK: table not full ($playerCount/$maxPlayers)');
        return false;
      }

      if (status != 'waiting' && status != 'start') {
        debugPrint('START GAME PRECHECK: table status is $status');
        return false;
      }

      await supabase.rpc('start_game', params: {'p_table_id': tableId});
      if (!_stateSyncInFlight) {
        await _loadInitialState(forceHandSync: true);
      }
      return true;
    } catch (e, st) {
      // Keep the game loop alive in debug; do not bubble to main isolate.
      debugPrint('START GAME RPC ERROR: $e');
      debugPrintStack(stackTrace: st);
      return false;
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
    _turnTimer = async.Timer.periodic(const Duration(milliseconds: 100), (_) {
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
    if (!isCreator) return;
    if (_actionInFlight || _botTurnInFlight) return;

    if (!_botSeats.contains(currentTurn)) return;

    final startAt = _turnStartedAt ?? DateTime.now();

    final token = '${currentTurn}_${startAt.millisecondsSinceEpoch}';

    if (_lastBotTurnToken == token) return;

    final elapsedMs = DateTime.now().difference(startAt).inMilliseconds;

    if (elapsedMs < 1800) return;

    _lastBotTurnToken = token;

    _botTurnInFlight = true;
    _playBotTurn().whenComplete(() {
      _botTurnInFlight = false;
    });
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

        final canFinishWithTop = _canFinishAfterTakingTopDiscard(
          hand,
          topDiscard,
        );

        final topIsRecentOwnDiscard =
            topDiscard != null &&
            _botRecentDiscards[botUserId]?.containsKey(
                  _tileMapKey(topDiscard),
                ) ==
                true;
        final topIsFakeJoker =
            topDiscard != null &&
            (topDiscard['fake_joker'] == true ||
                topDiscard['is_fake_joker'] == true);
        final immediateMeldValue = _immediateMeldGainFromTopDiscard(
          hand,
          topDiscard,
        );
        final wouldThrowBackTop = _wouldDiscardTakenTop(
          hand,
          topDiscard,
          strategy,
        );

        // Human-like rule:
        // take from discard when it clearly improves immediate meld quality
        // (especially completing/strengthening sets), otherwise draw closed.
        final shouldTakeTop =
            canFinishWithTop ||
            (!topIsRecentOwnDiscard &&
                !topIsFakeJoker &&
                ((immediateMeldValue >= 4) ||
                    (!wouldThrowBackTop && (immediateMeldValue >= 3))));

        var source = (topDiscard != null && shouldTakeTop)
            ? 'discard'
            : 'closed';

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
            debugPrint('BOT DRAW ERROR (closed): $e');
            return;
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

      final finishPlan = _buildBotFinishPlan(hand);
      final canFinish = finishPlan != null;
      final finishDiscardTile = canFinish
          ? Map<String, dynamic>.from(finishPlan['last_tile'] as Map)
          : null;
      final botSlots = canFinish
          ? List<Map<String, dynamic>>.from(finishPlan['slots'] as List)
          : _buildSlotsJsonFromHand(hand);

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

      if (canFinish) {
        try {
          final res = await Supabase.instance.client.rpc(
            'game_finish',
            params: {
              'p_table_id': tableId,
              'p_user_id': botUserId,
              'p_slots': botSlots,
              'p_last_tile': finishDiscardTile,
            },
          );

          if (res != null && res['ok'] == true) {}
        } catch (e) {
          debugPrint("BOT FINISH ERROR: $e");
          // Always fallback to discard if finish fails so bot turn cannot freeze.
          await Supabase.instance.client.rpc(
            'game_discard_fast',
            params: {
              'p_table_id': tableId,
              'p_user_id': botUserId,
              'p_tile': tile,
            },
          );
        }
      } else {
        await Supabase.instance.client.rpc(
          'game_discard_fast',
          params: {
            'p_table_id': tableId,
            'p_user_id': botUserId,
            'p_tile': tile,
          },
        );
      }

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
    if (sameColorVals.contains(t.value - 1) ||
        sameColorVals.contains(t.value + 1)) {
      runTouch += 1;
    }
    if (sameColorVals.contains(t.value - 2) ||
        sameColorVals.contains(t.value + 2)) {
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
    final memory = _botRecentDiscards.putIfAbsent(
      botUserId,
      () => <String, int>{},
    );
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
          .select(
            'status,current_turn,deck,turn_started_at,pot_amount,round_count,last_finish_at',
          )
          .eq('id', tableId)
          .limit(1);
      if ((rows as List).isEmpty) return;
      final table = Map<String, dynamic>.from(rows.first);

      final newRound = _normalizedRoundFromTable(table);
      final newPot = table['pot_amount'] as int?;

      bool changed = false;

      if (newRound != null && newRound != _round) {
        _round = newRound;
        changed = true;
      }

      if (newPot != null && newPot != _pot) {
        _pot = newPot;
        changed = true;
      }

      if (changed) {
        onHudChanged?.call(); // 🔥 UI yenile
      }

      final status = table['status']?.toString();
      if (status == 'playing' && !_gameStarted) {
        //await _loadInitialState();
        return;
      }
      if (status != 'playing') {
        // Avoid transient poll jitter from wiping discard visuals.
        // Table-state transitions are handled by _loadInitialState/_handleTableUpdate.
        return;
      }
      final turn = table['current_turn'] as int?;
      if (turn != null && turn != currentTurn) {
        currentTurn = turn;
        _turnStartedAt =
            _parseServerTime(table['turn_started_at']) ?? DateTime.now();
        hasDrawnThisTurn = _isMyTurn() && _myHandCount >= 15;
        _actionInFlight = false;
        _lastTimeoutTurnToken = null;
      }
      if (table['deck'] != null) {
        _syncDeckFromTable(table['deck']);
      }
      if (_gameStarted && _myHandCount < 14 && !_stateSyncInFlight) {
        _stateSyncInFlight = true;
        _loadInitialState(forceHandSync: true).whenComplete(() {
          _stateSyncInFlight = false;
        });
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

  String tileColorToString(TileColor color) {
    switch (color) {
      case TileColor.red:
        return 'red';
      case TileColor.blue:
        return 'blue';
      case TileColor.black:
        return 'black';
      case TileColor.yellow:
        return 'yellow';
    }
  }

  Future<void> _syncWaitingOrPlayingState() async {
    try {
      final tableRows = await Supabase.instance.client
          .from('tables')
          .select('status, max_players, ready_since')
          .eq('id', tableId)
          .limit(1);

      if ((tableRows as List).isEmpty) return;

      final table = Map<String, dynamic>.from(tableRows.first);

      final status = table['status']?.toString() ?? 'waiting';
      _maxPlayers = (table['max_players'] as int?) ?? _maxPlayers;

      // 🔥 ready_since oku
      final readySinceStr = table['ready_since'];
      if (readySinceStr != null) {
        _readySince = DateTime.parse(readySinceStr).toLocal();
      } else {
        _readySince = null;
      }

      // 🔥 oyun başladıysa init
      if (status == 'playing') {
        _startCalled = false; // reset
        await _loadInitialState();
        return;
      }

      // 🔥 waiting UI kontrol
      final playerRows = await Supabase.instance.client
          .from('table_players')
          .select('id')
          .eq('table_id', tableId);

      final playerCount = (playerRows as List).length;

      if (status == 'waiting') {
        if (playerCount < _maxPlayers) {
          _hideWaitingOverlay(); // oyuncu bekleniyor
        }
        // else → UI countdown gösterecek (ready_since üzerinden)
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

      if ((status == 'waiting' || status == 'start') &&
          playerCount >= _maxPlayers) {
        _startCountdownIfNeeded();
      }
    } catch (e) {
      debugPrint('START WATCHDOG ERROR: $e');
    }
  }

  void _startCountdownIfNeeded() {
    if (_gameStarted || _countdownInProgress) {
      return;
    }
    _countdownInProgress = true;
    _countdownSecondsLeft = 5;
    _localCountdownStart = DateTime.now();
    _countdownRunning = true;
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
      _countdownRunning = false;
      final started = await _tryStartGameOnServer();
      if (!started) {
        // Retry with a fresh local countdown instead of getting stuck.
        _startCountdownIfNeeded();
      }
    });
  }

  void _cancelStartCountdown() {
    _countdownInProgress = false;
    _countdownRunning = false;
    _localCountdownStart = null;
    _startCountdownTimer?.cancel();
    _startCountdownTimer = null;
  }

  void _renderMyHand(
    List<dynamic> rawPlayers, {
    bool applyServerDiff = true,
    bool hardReset = false,
  }) {
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
      // Server can briefly emit incomplete hand snapshots during round start.
      // Ignore invalid counts to avoid wiping rack visuals.
      if (hand.length < 14) {
        _myHandCount = occupiedSlots.length;
        hasDrawnThisTurn = _isMyTurn() && _myHandCount >= 15;
        return;
      }
      if (!applyServerDiff) {
        _myHandCount = occupiedSlots.length;
        hasDrawnThisTurn = _isMyTurn() && _myHandCount >= 15;
        return;
      }
      if (hardReset) {
        _clearRenderedHand();
      }
      _myHandCount = hand.length;
      final fingerprint = _handFingerprint(hand);
      final incomingCount = hand.whereType<Map>().length;
      if (fingerprint == _lastRenderedHandFingerprint &&
          tileComponentMap.length == incomingCount) {
        hasDrawnThisTurn = _isMyTurn() && _myHandCount >= 15;
        return;
      }
      if (hardReset || tileComponentMap.isEmpty) {
        _renderHand(hand);
      } else {
        _syncHandIncremental(hand);
      }
      _lastRenderedHandFingerprint = fingerprint;
      hasDrawnThisTurn = _isMyTurn() && _myHandCount >= 15;
    }
  }

  void _syncHandIncremental(List<dynamic> hand) {
    final parsedById = <String, TileModel>{};
    final rawIds = <String>{};
    if (hand.length < 14) {
      return;
    }

    for (final raw in hand) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = map['id']?.toString();
      if (id != null && id.isNotEmpty) {
        rawIds.add(id);
      }
      final model = _tileModelFromPayload(map);
      if (model == null) continue;
      parsedById[model.id] = model;
      tileMap[model.id] = model;
    }

    // Guard: do not wipe rack on transient/invalid payload.
    if (tileComponentMap.isNotEmpty && rawIds.length < 14) {
      return;
    }

    final existingIds = tileComponentMap.keys.toList(growable: false);
    for (final id in existingIds) {
      if (rawIds.contains(id)) continue;
      final tile = tileComponentMap.remove(id);
      if (tile == null) continue;
      if (tile.currentSlotIndex != null) {
        _lastKnownSlotByTileId[id] = tile.currentSlotIndex!;
        occupiedSlots.remove(tile.currentSlotIndex);
      } else {
        occupiedSlots.removeWhere((_, t) => identical(t, tile));
      }
      tile.removeFromParent();
    }

    occupiedSlots.removeWhere((_, tile) => !tile.isMounted);

    for (final model in parsedById.values) {
      if (tileComponentMap.containsKey(model.id)) continue;
      int slotIndex;
      int? preferredSlot;
      if (_pendingPreferredDrawSlot != null) {
        preferredSlot = _pendingPreferredDrawSlot!;
        slotIndex = preferredSlot;
        _pendingPreferredDrawSlot = null;
      } else {
        slotIndex = _pickStableSlotForTileId(model.id);
      }
      if (slotIndex == -1) continue;

      final tile = TileComponent(
        tile: model,
        position: slotPositions[slotIndex].clone(),
      );
      tileComponentMap[model.id] = tile;
      world.add(tile);

      final shouldInsertWithShift =
          preferredSlot != null &&
          (_mountedTileAtSlot(preferredSlot, ignore: tile) != null ||
              occupiedSlots.containsKey(preferredSlot));

      if (shouldInsertWithShift) {
        tile.currentSlotIndex = null;
        insertIntoRow(preferredSlot, tile);
        if (tile.currentSlotIndex != null) {
          _lastKnownSlotByTileId[model.id] = tile.currentSlotIndex!;
        }
      } else {
        tile.currentSlotIndex = slotIndex;
        _lastKnownSlotByTileId[model.id] = slotIndex;
        occupiedSlots[slotIndex] = tile;
      }
    }
  }

  void _renderSeats() {
    final existing = world.children.whereType<SeatComponent>().toList();
    for (final seat in existing) {
      seat.removeFromParent();
    }
  }

  void _hideWaitingOverlay() {
    _centerStatusText?.removeFromParent();
    _centerStatusText = null;
  }

  Map<String, TileComponent> tileComponentMap = {}; // 🔥 kritik
  Map<String, TileModel> tileMap = {}; // id → model

  void _purgeRackTilesHard() {
    final looseTiles = world.children
        .whereType<TileComponent>()
        .where((tile) => !tile.isLocked)
        .toList(growable: false);
    for (final tile in looseTiles) {
      tile.removeFromParent();
    }
    occupiedSlots.clear();
    tileComponentMap.clear();
  }

  void _renderHand(List<dynamic> hand) {
    final parsed = <TileModel>[];
    final incomingRawIds = <String>{};
    final wasHandEmptyBeforeRender = tileComponentMap.isEmpty;
    if (hand.length < 14) {
      return;
    }

    //-------------------------------------------------
    // 0. PARSE
    //-------------------------------------------------
    for (final raw in hand) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final rawId = map['id']?.toString();
      if (rawId != null && rawId.isNotEmpty) {
        incomingRawIds.add(rawId);
      }

      final model = _tileModelFromPayload(map);
      if (model == null) continue;

      parsed.add(model);
      tileMap[model.id] = model;
    }

    if (parsed.length < 14) {
      return;
    }

    if (wasHandEmptyBeforeRender) {
      // Safety: prevent duplicate full-hand visuals from stale local components.
      _purgeRackTilesHard();
    }

    // Guard: if we already have tiles and incoming payload has no ids,
    // ignore this frame instead of clearing everything.
    if (tileComponentMap.isNotEmpty && incomingRawIds.length < 14) {
      return;
    }

    // Remove stale tiles from previous hand snapshot so deterministic tile ids
    // across rounds do not get treated as "already rendered".
    final staleIds = tileComponentMap.keys
        .where((id) => !incomingRawIds.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      final staleTile = tileComponentMap.remove(id);
      if (staleTile == null) continue;
      if (staleTile.currentSlotIndex != null) {
        _lastKnownSlotByTileId[id] = staleTile.currentSlotIndex!;
        occupiedSlots.remove(staleTile.currentSlotIndex);
      }
      staleTile.removeFromParent();
    }

    occupiedSlots.removeWhere((_, tile) => !tile.isMounted);
    List<int>? slotPlan;
    if (wasHandEmptyBeforeRender) {
      slotPlan = _buildSmartRackPlan(parsed.length, parsed);
    }

    //-------------------------------------------------
    // 3. ADD → sadece yeni gelenleri ekle
    //-------------------------------------------------
    for (int i = 0; i < parsed.length; i++) {
      final model = parsed[i];

      // Already rendered and mounted: keep it.
      final existing = tileComponentMap[model.id];
      if (existing != null) {
        if (existing.isMounted) continue;
        tileComponentMap.remove(model.id);
      }

      int slotIndex;

      if (_pendingPreferredDrawSlot != null) {
        slotIndex = _pendingPreferredDrawSlot!;
        _pendingPreferredDrawSlot = null;
      } else if (slotPlan != null && i < slotPlan.length) {
        slotIndex = slotPlan[i];
      } else {
        slotIndex = _pickStableSlotForTileId(model.id);
      }

      if (slotIndex == -1) continue;

      //-------------------------------------------------
      // TILE OLUŞTUR
      //-------------------------------------------------
      final tile = TileComponent(
        tile: model,
        position: (closedPileComponent?.position ?? Vector2(800, 430)).clone(),
      );

      tile.currentSlotIndex = slotIndex;
      _lastKnownSlotByTileId[model.id] = slotIndex;
      tileComponentMap[model.id] = tile;
      occupiedSlots[slotIndex] = tile;

      world.add(tile);
      if (wasHandEmptyBeforeRender) {
        tile.add(
          MoveEffect.to(
            slotPositions[slotIndex],
            EffectController(
              duration: 0.22,
              startDelay: i * 0.025,
              curve: Curves.easeOutCubic,
            ),
          ),
        );
      } else {
        tile.position = slotPositions[slotIndex];
      }
    }
  }

  int _findFirstEmptySlot() {
    for (int i = 0; i < slotPositions.length; i++) {
      if (!occupiedSlots.containsKey(i)) {
        return i;
      }
    }
    return -1; // hiç boş yok
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
    _myHandCount = 0;
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
    _lastDeckVisualSignature = null;

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
      final key = entry.value.tile.id; // 🔥 artık bu
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
    // Tile identity must be stable per physical tile; value/color-based keys
    // cause duplicate tiles (e.g. two red-12) to swap places unexpectedly.
    return t.id;
  }

  int _pickStableSlotForTileId(String tileId) {
    final preferred = _lastKnownSlotByTileId[tileId];
    if (preferred != null &&
        preferred >= 0 &&
        preferred < slotPositions.length &&
        !occupiedSlots.containsKey(preferred)) {
      return preferred;
    }
    return _findFirstEmptySlot();
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
    final tiles = entries.map((e) => e.value.tile).toList(growable: false);
    final plan = _buildSmartRackPlan(tiles.length, tiles);
    _applyRackArrangement(
      entries.map((e) => e.value).toList(growable: false),
      plan,
    );
  }

  bool doubleMode = false;

  Future<void> confirmDoubleMode() async {
    if (doubleMode) return;

    doubleMode = true;

    final userId = UserState.userId;
    if (userId == null) return;

    try {
      await supabase
          .from('table_players')
          .update({'is_double_mode': true})
          .eq('table_id', tableId)
          .eq('user_id', userId);
    } catch (_) {}
  }

  void arrangePairs() {
    if (occupiedSlots.isEmpty) return;
    final entries = occupiedSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final refs = <_TileRef>[
      for (int i = 0; i < entries.length; i++)
        _TileRef(i, entries[i].value.tile),
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

  void _applyRackArrangement(List<TileComponent> tiles, List<int> plan) {
    occupiedSlots.clear();
    _lastKnownSlotByTileId.clear();
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
    final id = raw['id'];
    if (id == null || id.toString().isEmpty) return null;

    final valueRaw = raw['number'] ?? raw['value'];
    final value = valueRaw is int ? valueRaw : int.tryParse('$valueRaw');

    final color = _parseColor(raw['color']);

    if (value == null || color == null) return null;

    return TileModel(
      id: id.toString(), // 🔥 ZORUNLU
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
    String signature;
    try {
      signature = jsonEncode(deckRaw);
    } catch (_) {
      signature = deckRaw?.toString() ?? '';
    }
    if (_lastDeckVisualSignature == signature) {
      return;
    }
    _lastDeckVisualSignature = signature;

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
    // 🔥 eskiyi temizle
    if (_tableChannel != null) {
      Supabase.instance.client.removeChannel(_tableChannel!);
      _tableChannel = null;
    }

    final channel = Supabase.instance.client.channel('table_$tableId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'tables',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: tableId,
      ),
      callback: (payload) {
        _handleTableUpdate(payload.newRecord);
      },
    );

    // 🔥 EN KRİTİK KISIM
    channel.subscribe((status, [error]) {
      print("📡 TABLE STATUS: $status");

      if (error != null) {
        print("❌ TABLE ERROR: $error");
      }

      if (status == RealtimeSubscribeStatus.subscribed) {
        print("✅ TABLE CONNECTED");
      }

      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed) {
        print("💥 TABLE DROPPED → RECONNECT");

        _reconnectTableChannel();
      }
    });

    _tableChannel = channel;
  }

  int _reconnectAttempt = 0;

  void _reconnectTableChannel() {
    if (_reconnectAttempt > 5) return;

    _reconnectAttempt++;

    final delay = Duration(seconds: _reconnectAttempt);

    print("🔁 Reconnecting in ${delay.inSeconds}s...");

    Future.delayed(delay, () {
      _subscribeRealtime();
    });
  }

  @override
  void onDetach() {
    if (_tableChannel != null) {
      Supabase.instance.client.removeChannel(_tableChannel!);
      _tableChannel = null;
    }

    super.onDetach();
  }

  void _subscribeRealtimeMoves() {
    if (_stabilityMode) return;
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

  bool _isAnimatingRemoteMove = false;

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

    _moveQueue.add(move);

    // 🔥 created_at göre sırala (EN KRİTİK)
    _moveQueue.sort((a, b) {
      final t1 = DateTime.parse(a['created_at']);
      final t2 = DateTime.parse(b['created_at']);
      return t1.compareTo(t2);
    });

    _processMoveQueue();
  }

  Future<void> _processMoveQueue() async {
    if (_processingQueue) return;

    _processingQueue = true;

    while (_moveQueue.isNotEmpty) {
      final move = _moveQueue.removeAt(0);
      await _handleMove(move); // 🔥 sırayla işlenir
    }

    _processingQueue = false;
  }

  Future<void> _handleMove(Map<String, dynamic> move) async {
    final type = move['move_type']?.toString();
    final playerId = move['player_id'];

    final seat = _seatFromUserId(playerId);
    if (seat == null) return;

    final mySeat = _resolveMySeatIndex();

    // 🔥 kendi hareketini ignore
    if (mySeat != null && seat == mySeat) return;

    final rawTile = move['tile_data'];
    Map<String, dynamic>? tile;

    if (rawTile is String) {
      final decoded = jsonDecode(rawTile);
      if (decoded is Map) tile = Map<String, dynamic>.from(decoded);
    } else if (rawTile is Map) {
      tile = Map<String, dynamic>.from(rawTile);
    }

    if (type == 'draw_discard') {
      final fromSeat = move['from_seat'];
      if (fromSeat == null) return;
      _holdDiscardSeatSync(fromSeat);

      await _animateDiscardToPlayer(
        fromSeat: fromSeat,
        toSeat: seat,
        tileData: tile,
      );
      return;
    }

    if (type == 'discard') {
      _holdDiscardSeatSync(seat);
      _animatePlayerToDiscard(seat: seat, tileData: tile);
      return;
    }
  }

  void _holdDiscardSeatSync(int seat, {Duration duration = const Duration(milliseconds: 900)}) {
    _discardSyncHoldUntilBySeat[seat] = DateTime.now().add(duration);
  }

  Future<void> _animateDiscardToPlayer({
    required int fromSeat,
    required int toSeat,
    Map<String, dynamic>? tileData,
  }) async {
    final fromSlotIndex = _slotIndexForAbsoluteSeat(fromSeat);
    final fromSlot = _discardSlotsByIndex[fromSlotIndex];
    if (fromSlot == null) return;

    final model = tileData != null ? _tileModelFromPayload(tileData) : null;
    final fallbackTop =
        _discardTopTilesBySeat[fromSeat] ?? fromSlot.currentTile;

    final tileModel = model ?? fallbackTop?.tile;

    final value = tileModel?.value;

    final colorType = tileModel?.color;

    if (value == null || colorType == null) return;

    // 🔥 başlangıç: discard slotu (SENDE VAR)
    final start = fromSlot.position.clone();

    // 🔥 hedef: oyuncunun çekme noktası (SENDE VAR)
    final end = _drawAnimationTargetForSeat(toSeat);

    final transient = TileComponent(
      tile: tileModel!, // 🔥 zorunlu
      position: start,
    )..priority = 79;

    transient.isLocked = true;
    world.add(transient);

    // 🔥 discard üstündeki taşı kaldır + local stack'ten alttakini anında göster
    final removed = _popDiscardStack(fromSeat);
    final revealed = _peekDiscardStack(fromSeat);
    final previousTop = _discardTopTilesBySeat[fromSeat];
    if (previousTop != null) {
      previousTop.removeFromParent();
      _discardTopTilesBySeat.remove(fromSeat);
      fromSlot.currentTile = null;
    }
    if (revealed != null) {
      final revealedTile = TileComponent(
        tile: revealed,
        position: fromSlot.position.clone(),
      )
        ..priority = 50
        ..isLocked = true;
      world.add(revealedTile);
      _discardTopTilesBySeat[fromSeat] = revealedTile;
      fromSlot.currentTile = revealedTile;
    } else if (removed != null) {
      _fetchAndShowPreviousDiscardTop(fromSeat, removed.id);
    }

    final completer = Completer<void>();

    transient.add(
      MoveEffect.to(
        end,
        EffectController(duration: 0.28, curve: Curves.easeOutCubic),
      ),
    );

    async.Timer(const Duration(milliseconds: 320), () {
      transient.removeFromParent();
      completer.complete();
    });

    return completer.future;
  }

  String? _moveDedupeKey(Map<String, dynamic> move) {
    final id = move['id'];
    if (id != null) return 'id:$id';
    final createdAt = move['created_at']?.toString() ?? '';
    final player = move['player_id']?.toString() ?? '';
    final type = move['move_type']?.toString() ?? '';
    final fromSeat =
        (move['from_seat'] ?? move['source_seat'])?.toString() ?? '';
    final tileData = move['tile_data'];
    final tileSig = tileData is String
        ? tileData
        : (tileData?.toString() ?? '');
    final key = '$createdAt|$player|$type|$fromSeat|$tileSig';
    return key == '||||' ? null : key;
  }

  void _placeTileToRackFromDraw({
    required int value,
    required TileColorType colorType,
    TileModel? model,
  }) {
    /// 🔥 boş slot bul
    int? slotIndex;
    for (int i = 0; i < slotPositions.length; i++) {
      if (!occupiedSlots.containsKey(i)) {
        slotIndex = i;
        break;
      }
    }

    if (slotIndex == null) return;

    final pos = slotPositions[slotIndex];

    final tileModel = model;

    if (tileModel == null) return; // 🔥 güvenlik

    final tile = TileComponent(tile: tileModel, position: pos.clone());

    world.add(tile);

    occupiedSlots[slotIndex] = tile;
    tile.currentSlotIndex = slotIndex;
  }

  Vector2 _drawAnimationTargetForSeat(int absoluteSeat) {
    final relative =
        (absoluteSeat - (_mySeatIndexAbs ?? 0) + _maxPlayers) % _maxPlayers;
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

    // 🔥 TEK KAYNAK: TileModel
    final tileModel = model ?? fallbackTop?.tile;

    if (tileModel == null) return;
    _pushDiscardStack(seat, tileModel);

    if (_discardAnimationInFlightSeats.contains(seat)) return;
    final existingTop = _discardTopTilesBySeat[seat] ?? slot.currentTile;
    if (existingTop != null && existingTop.tile.id == tileModel.id) {
      return;
    }

    final start = _drawAnimationTargetForSeat(seat);

    final transient = TileComponent(tile: tileModel, position: start)
      ..priority = 79;
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
      // _emitTileSfx();
    });
  }

  bool _sameDiscardVisualTile(TileComponent existing, TileModel model) {
    return existing.tile.id == model.id;
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

  bool _finishShown = false;
  bool _initialized = false;
  String? _lastHandledFinishId;
  String? _lastHandledFinishCore;
  DateTime? _lastLocalFinishAt;
  bool _startCalled = false;
  DateTime? _readySince;
  DateTime? _localCountdownStart;
  bool _countdownRunning = false;

  String _buildFinishCoreId({
    required dynamic winnerId,
    required List<Map<String, dynamic>> slots,
    required Map<String, dynamic> finishTile,
  }) {
    final slotTileIds = <String>[];
    for (final s in slots) {
      final tile = s['tile'];
      if (tile is Map<String, dynamic>) {
        final id = tile['id']?.toString();
        if (id != null && id.isNotEmpty) {
          slotTileIds.add(id);
        }
      }
    }
    slotTileIds.sort();
    final finishTileId = finishTile['id']?.toString() ?? '';
    return '${winnerId ?? ''}|$finishTileId|${slotTileIds.join(',')}';
  }

  bool _maybeShowFinishFromTable(Map<String, dynamic> table) {
    final status = table['status']?.toString();
    if (status == 'playing') return false;
    final hasFinishData =
        table['last_winner_user_id'] != null &&
        table['last_final_slots'] != null &&
        table['last_finish_tile'] != null;
    if (!hasFinishData) return false;

    final finishAt = table['last_finish_at']?.toString() ?? '';
    if (finishAt.isEmpty) return false;
    final winnerId = table['last_winner_user_id'];
    final slots = List<Map<String, dynamic>>.from(table['last_final_slots'] ?? []);
    final finishTile = Map<String, dynamic>.from(table['last_finish_tile'] ?? {});
    final finishCore = _buildFinishCoreId(
      winnerId: winnerId,
      slots: slots,
      finishTile: finishTile,
    );
    final finishId = '$finishAt|$finishCore';
    if (_lastHandledFinishId == finishId) {
      return false;
    }
    final now = DateTime.now();
    if (_lastHandledFinishCore == finishCore &&
        _lastLocalFinishAt != null &&
        now.difference(_lastLocalFinishAt!).inSeconds < 10) {
      _lastHandledFinishId = finishId;
      return false;
    }

    _finishShown = true;
    _gameStarted = false;
    _lastHandledFinishId = finishId;
    _lastHandledFinishCore = finishCore;
    final winAmount = table['last_win_amount'] ?? 0;
    final isWinner = isMeWinner(winnerId);

    try {
      showFinishFromGame(
        slots,
        finishTile,
        getPlayerName(winnerId),
        isWinner,
        false,
        winAmount,
        table['pot_amount'] == 0,
        false,
      );
    } catch (e) {
      debugPrint("Finish UI crash: $e");
    }

    _clearRenderedHand();
    _clearTableVisualState();
    return true;
  }

  Future<void> _handleTableUpdate(Map<String, dynamic> table) async {
    try {
      final status = table['status'] as String?;
      if (status == null) {
        return;
      }
      _maybeShowFinishFromTable(table);

      if (status == 'playing' && !_gameStarted) {
        _gameStarted = true;
        _enteredPlayingAt = DateTime.now();
        _hideWaitingOverlay();
        if (!_stateSyncInFlight) {
          await _loadInitialState(forceHandSync: true);
        }
        return;
      }

      if (status != 'playing' && _gameStarted) {
        final enteredAt = _enteredPlayingAt;
        final inGraceWindow =
            enteredAt != null &&
            DateTime.now().difference(enteredAt).inSeconds < 8;
        if (inGraceWindow) {
          // Ignore transient stale non-playing updates right after game start.
          return;
        }
        _gameStarted = false;
        _countdownTriggeredForThisFullState = false;
        _cancelStartCountdown();
        if (!_stateSyncInFlight) {
          await _loadInitialState(forceHandSync: false);
        }
      }

      // 🔥 PLAYING
      if (status == 'playing') {
        _startCalled = false;
        _countdownRunning = false;
        _localCountdownStart = null;
        _initialized = false;
        _hideWaitingOverlay();
        _gameStarted = true;
        _enteredPlayingAt = DateTime.now();
      }

      // 🔥 WAITING → sadece oyuncu bekleme
      if (status == 'waiting') {
        final nonPlayingKey =
            'waiting_${table['round_count']}_${table['last_finish_at']}';
        if (_lastNonPlayingVisualKey != nonPlayingKey) {
          _lastNonPlayingVisualKey = nonPlayingKey;
          _clearRenderedHand();
          _clearTableVisualState();
        }
        if (_gameStarted) {
          _gameStarted = false;
        }

        final currentPlayers = playersWithProfiles.length;
        if (currentPlayers < _maxPlayers) {
          _cancelStartCountdown();
          _startCalled = false;
        }

        await _ensureGameStartIfReady(
          knownStatus: status,
        );

        return;
      }

      // 🔥 START → countdown burada başlar
      if (status == 'start') {
        final nonPlayingKey =
            'start_${table['round_count']}_${table['last_finish_at']}';
        if (_lastNonPlayingVisualKey != nonPlayingKey) {
          _lastNonPlayingVisualKey = nonPlayingKey;
          _clearRenderedHand();
          _clearTableVisualState();
        }
        await _ensureGameStartIfReady(
          knownStatus: status,
        );
        return;
      }

      // 🔥 TURN SYNC (sadece playing'de anlamlı)
      final turn = table['current_turn'];
      final serverTurnStartedAt = _parseServerTime(table['turn_started_at']);

      if (turn is int) {
        if (currentTurn != turn) {
          _turnStartedAt = serverTurnStartedAt ?? DateTime.now();
          _actionInFlight = false;
          _lastTimeoutTurnToken = null;
        }
        currentTurn = turn;
        hasDrawnThisTurn = _isMyTurn() && _myHandCount >= 15;
      }

      if (table['deck'] != null && !_initialized) {
        _syncDeckFromTable(table['deck']);
        _initialized = true;
      }
    } catch (e, s) {
      debugPrint("🔥 TABLE UPDATE CRASH: $e");
      debugPrint("$s");
    }
  }

  int getCountdown() {
    if (_countdownInProgress) {
      return _countdownSecondsLeft > 0 ? _countdownSecondsLeft : 0;
    }
    if (!_countdownRunning || _localCountdownStart == null) return 0;

    final elapsed = DateTime.now().difference(_localCountdownStart!).inSeconds;
    final remain = 5 - elapsed;

    return remain > 0 ? remain : 0;
  }

  Future<void> _fetchCurrentTable() async {
    try {
      final res = await Supabase.instance.client
          .from('tables')
          .select()
          .eq('id', tableId)
          .single();

      print("📥 FETCH OK");

      await _handleTableUpdate(res);
    } catch (e) {
      print("❌ FETCH ERROR: $e");
    }
  }

  String getPlayerName(dynamic userId) {
    final p = playersWithProfiles
        .where((x) => x['user_id'] == userId)
        .cast<Map<String, dynamic>?>()
        .firstWhere((x) => x != null, orElse: () => null);

    return p?['username'] ?? "Oyuncu";
  }

  int _normalizedRoundFromTable(Map<String, dynamic> table) {
    final raw = table['round_count'] as int?;
    if (raw == null || raw < 1) return 1;
    return raw;
  }

  void _updateClosedPile(int count) async {
    if (closedPileComponent == null) {
      closedPileComponent = ClosedPileComponent(
        position: Vector2(750, 270),
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

    final indicator = closedPile.first; // 🔥 TileModel

    final tile = TileComponent(tile: indicator, position: Vector2(860, 270))
      ..isLocked = true
      ..priority = 55;

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
      Vector2(350, 285),
      Vector2(1250, 285),
      Vector2(350, 460),
      Vector2(1250, 460),
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

      // Render/update current tops. Do not aggressively clear missing seats,
      // otherwise eventual consistency makes discard visuals disappear/return.
      final mySeat = _resolveMySeatIndex();
      for (final entry in topsBySeat.entries) {
        final seat = entry.key;
        final holdUntil = _discardSyncHoldUntilBySeat[seat];
        if (holdUntil != null && holdUntil.isAfter(DateTime.now())) {
          continue;
        }
        if (_discardAnimationInFlightSeats.contains(seat)) continue;
        final tileModel = _tileModelFromPayload(entry.value);
        if (tileModel == null) continue;
        final slotIndex = _slotIndexForAbsoluteSeat(seat);
        final slot = _discardSlotsByIndex[slotIndex];
        if (slot == null) continue;
        final existing = _discardTopTilesBySeat[seat];
        if (_suppressRemoteDiscardTopAutoCreate &&
            mySeat != null &&
            seat != mySeat &&
            existing == null) {
          continue;
        }
        if (existing != null && _sameDiscardVisualTile(existing, tileModel)) {
          existing.position = slot.position.clone();
          existing.priority = 50;
          existing.isLocked = true;
          slot.currentTile = existing;
          continue;
        }

        existing?.removeFromParent();
        final tile = TileComponent(
          tile: tileModel,
          position: slot.position.clone(),
        )..isLocked = true;
        tile.priority = 50;
        world.add(tile);
        _discardTopTilesBySeat[seat] = tile;
        slot.currentTile = tile;
        final stack = _discardStacksBySeat.putIfAbsent(seat, () => <TileModel>[]);
        if (stack.isEmpty || stack.last.id != tileModel.id) {
          stack.add(_cloneTileModel(tileModel));
          if (stack.length > 32) {
            stack.removeAt(0);
          }
        }
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
      final ids = <String>[];
      for (final e in hand) {
        if (e is Map && e['id'] != null) {
          ids.add(e['id'].toString());
        }
      }
      ids.sort();
      return ids.join('|');
    } catch (_) {
      return hand.length.toString();
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
      await _loadInitialState(forceHandSync: true);
      await _syncDiscardTopsFromServer();
      hasDrawnThisTurn = _isMyTurn() && _myHandCount >= 15;
      //_emitTileSfx();
    } catch (e) {
      debugPrint('GAME_DRAW RPC ERROR: $e');
      _pendingPreferredDrawSlot = null;
      if ('$e'.contains('NOT_YOUR_TURN')) {
        await _pollLiveTableState();
      }
      if ('$e'.contains('HAND_ALREADY_15')) {
        hasDrawnThisTurn = true;
      }
      await _loadInitialState(forceHandSync: true);
    } finally {
      _actionInFlight = false;
    }
  }

  List<Map<String, dynamic>> _buildSlotsJson(Map<int, TileComponent> slotMap) {
    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < 26; i++) {
      final tile = slotMap[i];

      if (tile != null) {
        result.add({
          'i': i,
          'tile': tile.tile.toJson(), // 🔥 FIX
        });
      } else {
        result.add({'i': i});
      }
    }

    return result;
  }

  // Future<bool> _serverDiscard(TileComponent tile, {bool finish = false}) async {
  //   // if (_actionInFlight) return false;

  //   final userId = Supabase.instance.client.auth.currentUser?.id;
  //   if (userId == null) return false;

  //   _actionInFlight = true;

  //   final slots = finish ? _buildSlotsJson(occupiedSlots) : null;

  //   try {
  //     final res = await Supabase.instance.client.rpc(
  //       'game_discard_fast',
  //       params: {
  //         'p_table_id': tableId,
  //         'p_user_id': userId,
  //         'p_tile': {
  //           'color': _tileColorToString(tile.colorType),
  //           'number': tile.value,
  //           'joker': tile.isJoker,
  //           'is_joker': tile.isJoker,
  //           'fake_joker': tile.isFakeJoker,
  //           'is_fake_joker': tile.isFakeJoker,
  //         },
  //       },
  //     );

  //     // 🔥 SERVER RESPONSE OKU
  //     if (res != null && res is Map) {
  //       final ok = res['ok'] == true;

  //       if (!ok) {
  //         /// ❗ SADECE HATA DURUMUNDA SYNC
  //         await _loadInitialState();

  //         final error = res['error'];

  //         if (error == 'INVALID_HAND') {
  //           AppMsg.show('El geçersiz');
  //         } else if (error == 'NOT_YOUR_TURN') {
  //           AppMsg.show('Sıra sende değil');
  //         } else {
  //           AppMsg.show('İşlem başarısız');
  //         }

  //         return false;
  //       }

  //       /// 🔥 BAŞARILI → HİÇBİR ŞEY YAPMA
  //       if (res['finish'] == true) {
  //         _showWaitingOverlay('Kazandın! 🎉');
  //       }
  //     }

  //     hasDrawnThisTurn = false;
  //     _pendingPreferredDrawSlot = null;
  //     return true;
  //     // 🔥 STATE SYNC
  //   } catch (e) {
  //     final err = e.toString();

  //     debugPrint('GAME_DISCARD RPC ERROR: $err');

  //     if (err.contains('INVALID_FINISH')) {
  //       AppMsg.show('El geçersiz');
  //     } else if (err.contains('NOT_YOUR_TURN')) {
  //       AppMsg.show('Sıra sende değil');
  //       await _pollLiveTableState();
  //     } else {
  //       AppMsg.show('İşlem başarısız');
  //     }

  //     Future.delayed(const Duration(seconds: 2), _hideWaitingOverlay);

  //     await _loadInitialState();
  //     return false;
  //   } finally {
  //     _actionInFlight = false;
  //   }
  // }

  Future<bool> _serverDiscard(TileComponent tile, {bool finish = false}) async {
    if (_networkInFlight) return false;

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;

    _networkInFlight = true;

    try {
      final mySeat = _resolveMySeatIndex();
      if (mySeat != null) {
        _showMyDiscardTopOptimistic(tile.tile);
        _holdDiscardSeatSync(
          mySeat,
          duration: const Duration(milliseconds: 1200),
        );
      }
      final res = await client.rpc(
        'game_discard_fast',
        params: {
          'p_table_id': tableId,
          'p_user_id': userId,
          'p_tile': {
            'id': tile.tile.id,
            'color': tileColorToString(tile.tile.color),
            'number': tile.tile.value,
            'joker': tile.tile.isJoker,
            'is_joker': tile.tile.isJoker,
            'fake_joker': tile.tile.isFakeJoker,
            'is_fake_joker': tile.tile.isFakeJoker,
          },
        },
      );

      if (res == null || res is! Map || res['ok'] != true) {
        await _loadInitialState(forceHandSync: true);
        return false;
      }

      _removeTileFromRackState(tile);
      if (tile.isMounted) {
        tile.removeFromParent();
      }
      _myHandCount = (_myHandCount - 1).clamp(0, 30);
      hasDrawnThisTurn = false;
      _pendingPreferredDrawSlot = null;
      // Discard success: only removed tile should change in my hand.
      // Keep hand untouched to prevent unintended slot moves.
      await _loadInitialState(forceHandSync: false);
      return true;
    } catch (e) {
      await _loadInitialState(forceHandSync: true);
      return false;
    } finally {
      _networkInFlight = false;
    }
  }

  Future<void> _serverTimeoutMove() async {
    if (_actionInFlight) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _actionInFlight = true;

    try {
      // 🔥 server'a timeout işlemini yaptır
      await Supabase.instance.client.rpc(
        'game_timeout_move',
        params: {'p_table_id': tableId, 'p_user_id': userId},
      );

      // 🔥 yeni state'i çek (taşlar burada güncellenir)
      await _loadInitialState(forceHandSync: true);
    } catch (e) {
      // ⚠️ süre dolmadıysa hata verir, ignore edebilirsin
      debugPrint("TIMEOUT MOVE ERROR: $e");
      final err = e.toString();
      if (err.contains('TABLE_NOT_PLAYING')) {
        _gameStarted = false;
        _cancelStartCountdown();
        await _loadInitialState(forceHandSync: false);
      }
    } finally {
      _actionInFlight = false;
    }
  }

  List<Map<String, dynamic>> _buildSlotsJsonFromHand(
    List hand, {
    Map<String, dynamic>? lastTile,
  }) {
    final normalized = hand
        .whereType<Map>()
        .map((e) => _normalizeTilePayload(Map<String, dynamic>.from(e)))
        .where((e) => (e['id']?.toString().isNotEmpty ?? false))
        .toList(growable: true);

    if (lastTile != null) {
      final normalizedLast = _normalizeTilePayload(Map<String, dynamic>.from(lastTile));
      _removeSingleTileByIdOrSignature(normalized, normalizedLast);
    }

    // Finish validator expects exactly 14 tiles in grouped slots.
    if (normalized.length == 14) {
      final groups = _buildValidatorCompatibleGroups(normalized);
      if (groups != null) {
        final result = <Map<String, dynamic>>[];
        var slot = 0;
        for (int g = 0; g < groups.length && slot < 26; g++) {
          final group = groups[g];
          for (final tile in group) {
            if (slot >= 26) break;
            result.add({'i': slot, 'tile': tile});
            slot++;
          }
          if (g < groups.length - 1 && slot < 26) {
            result.add({'i': slot});
            slot++;
          }
        }
        while (slot < 26) {
          result.add({'i': slot});
          slot++;
        }
        return result;
      }
    }

    // Fallback: deterministic left-packed layout.
    normalized.sort((a, b) {
      final colorA = (a['color'] ?? '').toString();
      final colorB = (b['color'] ?? '').toString();
      final colorCompare = colorA.compareTo(colorB);
      if (colorCompare != 0) return colorCompare;

      final numA = (a['value'] ?? 0) as int;
      final numB = (b['value'] ?? 0) as int;
      final numCompare = numA.compareTo(numB);
      if (numCompare != 0) return numCompare;

      return (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString());
    });

    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < 26; i++) {
      if (i < normalized.length) {
        result.add({'i': i, 'tile': normalized[i]});
      } else {
        result.add({'i': i});
      }
    }
    return result;
  }

  Map<String, dynamic> _normalizeTilePayload(Map<String, dynamic> raw) {
    final valueRaw = raw['value'] ?? raw['number'] ?? 0;
    final value = valueRaw is int ? valueRaw : int.tryParse('$valueRaw') ?? 0;
    return {
      'id': (raw['id'] ?? '').toString(),
      'value': value,
      'color': (raw['color'] ?? '').toString(),
      'isJoker':
          raw['isJoker'] == true ||
          raw['joker'] == true ||
          raw['is_joker'] == true,
      'isFakeJoker':
          raw['isFakeJoker'] == true ||
          raw['fake_joker'] == true ||
          raw['is_fake_joker'] == true,
    };
  }

  void _removeSingleTileByIdOrSignature(
    List<Map<String, dynamic>> list,
    Map<String, dynamic> target,
  ) {
    final targetId = (target['id'] ?? '').toString();
    if (targetId.isNotEmpty) {
      final idx = list.indexWhere((t) => (t['id'] ?? '').toString() == targetId);
      if (idx >= 0) {
        list.removeAt(idx);
        return;
      }
    }

    final value = (target['value'] ?? 0) as int;
    final color = (target['color'] ?? '').toString();
    final isJoker = target['isJoker'] == true;
    final idx = list.indexWhere(
      (t) =>
          (t['value'] ?? 0) == value &&
          (t['color'] ?? '').toString() == color &&
          (t['isJoker'] == true) == isJoker,
    );
    if (idx >= 0) {
      list.removeAt(idx);
    }
  }

  List<List<Map<String, dynamic>>>? _buildValidatorCompatibleGroups(
    List<Map<String, dynamic>> hand14,
  ) {
    if (hand14.length != 14) return null;
    final tiles = <_BotFinishTile>[
      for (final t in hand14)
        _BotFinishTile(
          id: (t['id'] ?? '').toString(),
          value: (t['value'] ?? 0) as int,
          color: (t['color'] ?? '').toString(),
          isJoker: t['isJoker'] == true,
          payload: t,
        ),
    ];

    final memo = <String, List<List<_BotFinishTile>>?>{};
    final solved = _solveBotFinishGroups(tiles, memo);
    if (solved == null) return null;
    return solved
        .map((g) => g.map((t) => Map<String, dynamic>.from(t.payload)).toList())
        .toList();
  }

  List<List<_BotFinishTile>>? _solveBotFinishGroups(
    List<_BotFinishTile> tiles,
    Map<String, List<List<_BotFinishTile>>?> memo,
  ) {
    if (tiles.isEmpty) return <List<_BotFinishTile>>[];

    final key = (tiles.map((t) => t.id).toList()..sort()).join('|');
    if (memo.containsKey(key)) return memo[key];

    final first = tiles.firstWhere(
      (t) => !t.isJoker,
      orElse: () => tiles.first,
    );

    final candidates = _candidateGroupsForFirst(tiles, first);
    for (final group in candidates) {
      final groupIds = group.map((t) => t.id).toSet();
      final remaining = tiles.where((t) => !groupIds.contains(t.id)).toList();
      final rest = _solveBotFinishGroups(remaining, memo);
      if (rest != null) {
        final out = <List<_BotFinishTile>>[group, ...rest];
        memo[key] = out;
        return out;
      }
    }

    memo[key] = null;
    return null;
  }

  List<List<_BotFinishTile>> _candidateGroupsForFirst(
    List<_BotFinishTile> tiles,
    _BotFinishTile first,
  ) {
    final out = <List<_BotFinishTile>>[];
    final jokers = tiles.where((t) => t.isJoker).toList();
    final nonJokers = tiles.where((t) => !t.isJoker).toList();

    // SET candidates (size 3..4): same value, distinct colors + jokers.
    final sameValue = nonJokers.where((t) => t.value == first.value).toList();
    final uniqueByColor = <String, _BotFinishTile>{};
    for (final t in sameValue) {
      uniqueByColor.putIfAbsent(t.color, () => t);
    }
    final colorUnique = uniqueByColor.values.toList();

    for (final targetSize in const [3, 4]) {
      for (int nonJokerCount = 1; nonJokerCount <= colorUnique.length; nonJokerCount++) {
        final jokerNeed = targetSize - nonJokerCount;
        if (jokerNeed < 0 || jokerNeed > jokers.length) continue;
        final combos = _botTileCombinations(colorUnique, nonJokerCount);
        for (final combo in combos) {
          if (!combo.contains(first)) continue;
          final g = [...combo, ...jokers.take(jokerNeed)];
          if (_isValidatorSetGroup(g)) out.add(g);
        }
      }
    }

    // RUN candidates (size >=3): same color, with jokers filling gaps, including 13->1 wrap.
    final sameColor = nonJokers.where((t) => t.color == first.color).toList();
    for (int size = 3; size <= 5; size++) {
      final target = size.clamp(1, sameColor.length).toInt();
      final combos = _botTileCombinations(sameColor, target);
      for (final combo in combos) {
        if (!combo.contains(first)) continue;
        if (_isValidatorRunGroup(combo)) out.add(combo);
      }
      for (int nonJokerCount = 2; nonJokerCount <= sameColor.length; nonJokerCount++) {
        final jokerNeed = size - nonJokerCount;
        if (jokerNeed <= 0 || jokerNeed > jokers.length) continue;
        final baseCombos = _botTileCombinations(sameColor, nonJokerCount);
        for (final base in baseCombos) {
          if (!base.contains(first)) continue;
          final g = [...base, ...jokers.take(jokerNeed)];
          if (_isValidatorRunGroup(g)) out.add(g);
        }
      }
    }

    // Prefer larger groups first for fewer separators.
    out.sort((a, b) => b.length.compareTo(a.length));
    return out;
  }

  bool _isValidatorSetGroup(List<_BotFinishTile> g) {
    if (g.length < 3 || g.length > 4) return false;
    final jokers = g.where((t) => t.isJoker).length;
    final non = g.where((t) => !t.isJoker).toList();
    if (non.isEmpty) return false;
    final sameValue = non.every((t) => t.value == non.first.value);
    if (!sameValue) return false;
    final colors = non.map((t) => t.color).toSet();
    if (colors.length != non.length) return false;
    return (non.length + jokers) >= 3 && (non.length + jokers) <= 4;
  }

  bool _isValidatorRunGroup(List<_BotFinishTile> g) {
    if (g.length < 3) return false;
    final non = g.where((t) => !t.isJoker).toList();
    if (non.isEmpty) return false;
    final jokers = g.where((t) => t.isJoker).length;

    final colors = non.map((t) => t.color).toSet();
    if (colors.length != 1) return false;

    final vals = non.map((t) => t.value).toList()..sort();
    final uniq = vals.toSet();
    if (uniq.length != vals.length) return false;

    int gap = 0;
    for (int i = 1; i < vals.length; i++) {
      final d = vals[i] - vals[i - 1];
      if (d <= 0) return false;
      gap += (d - 1);
    }
    if (gap <= jokers) return true;

    // wrap check: treat 1 as 14
    final wrap = non.map((t) => t.value == 1 ? 14 : t.value).toList()..sort();
    gap = 0;
    for (int i = 1; i < wrap.length; i++) {
      final d = wrap[i] - wrap[i - 1];
      if (d <= 0) return false;
      gap += (d - 1);
    }
    return gap <= jokers;
  }

  List<List<_BotFinishTile>> _botTileCombinations(
    List<_BotFinishTile> input,
    int choose,
  ) {
    if (choose <= 0 || choose > input.length) return <List<_BotFinishTile>>[];
    final out = <List<_BotFinishTile>>[];
    void walk(int start, List<_BotFinishTile> current) {
      if (current.length == choose) {
        out.add(List<_BotFinishTile>.from(current));
        return;
      }
      for (int i = start; i < input.length; i++) {
        current.add(input[i]);
        walk(i + 1, current);
        current.removeLast();
      }
    }

    walk(0, <_BotFinishTile>[]);
    return out;
  }

  bool _isServerValidSlotsPayload(List<Map<String, dynamic>> slots) {
    final groups = <List<_BotFinishTile>>[];
    var current = <_BotFinishTile>[];
    var total = 0;

    for (final slot in slots) {
      final tileRaw = slot['tile'];
      if (tileRaw == null) {
        if (current.isNotEmpty) {
          groups.add(current);
          current = <_BotFinishTile>[];
        }
        continue;
      }
      if (tileRaw is! Map) return false;
      final map = Map<String, dynamic>.from(tileRaw);
      final id = (map['id'] ?? '').toString();
      if (id.isEmpty) return false;
      final valueRaw = map['value'] ?? map['number'] ?? 0;
      final value = valueRaw is int ? valueRaw : int.tryParse('$valueRaw');
      if (value == null) return false;
      final color = (map['color'] ?? '').toString();
      if (color.isEmpty) return false;
      final isJoker =
          map['isJoker'] == true ||
          map['joker'] == true ||
          map['is_joker'] == true;
      current.add(
        _BotFinishTile(
          id: id,
          value: value,
          color: color,
          isJoker: isJoker,
          payload: map,
        ),
      );
    }
    if (current.isNotEmpty) {
      groups.add(current);
    }

    for (final g in groups) {
      if (g.length < 3) return false;
      total += g.length;
      final ids = g.map((t) => t.id).toList();
      if (ids.toSet().length != ids.length) return false;
      if (!_isValidatorSetGroup(g) && !_isValidatorRunGroup(g)) {
        return false;
      }
    }

    return total == 14;
  }

  Map<String, dynamic>? _buildBotFinishPlan(List hand) {
    final normalized = hand
        .whereType<Map>()
        .map((e) => _normalizeTilePayload(Map<String, dynamic>.from(e)))
        .where((e) => (e['id']?.toString().isNotEmpty ?? false))
        .toList(growable: true);
    if (normalized.length != 15) return null;

    for (int i = 0; i < normalized.length; i++) {
      final candidateLast = Map<String, dynamic>.from(normalized[i]);
      final remaining = <Map<String, dynamic>>[
        for (int j = 0; j < normalized.length; j++)
          if (j != i) Map<String, dynamic>.from(normalized[j]),
      ];
      final groups = _buildValidatorCompatibleGroups(remaining);
      if (groups == null) continue;

      final slots = <Map<String, dynamic>>[];
      var slot = 0;
      for (int g = 0; g < groups.length && slot < 26; g++) {
        final group = groups[g];
        for (final tile in group) {
          if (slot >= 26) break;
          slots.add({'i': slot, 'tile': tile});
          slot++;
        }
        if (g < groups.length - 1 && slot < 26) {
          slots.add({'i': slot});
          slot++;
        }
      }
      while (slot < 26) {
        slots.add({'i': slot});
        slot++;
      }

      if (_isServerValidSlotsPayload(slots)) {
        return {
          'last_tile': candidateLast,
          'slots': slots,
        };
      }
    }
    return null;
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
    final now = DateTime.now();
    if (_lastDrawAttemptAt != null &&
        now.difference(_lastDrawAttemptAt!).inMilliseconds < 250) {
      return;
    }
    _lastDrawAttemptAt = now;
    if (hasDrawnThisTurn) return;
    if (_myHandCount >= 15) return;
    if (closedPile.length <= 1) return;
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return;
    }
    _serverDraw(source: 'closed');
  }

  void updatePreview(Vector2 pos) {
    final index = getNearestSlotIndex(pos);

    if (index == null) {
      previewBox.isVisible = false;
      _cancelHover();
      clearTemporaryShift();
      return;
    }

    previewBox.position = slotPositions[index];
    previewBox.isVisible = true;

    // 🔥 aynı yerdeyse hiçbir şey yapma
    if (_hoverIndex == index) return;

    _cancelHover();

    _hoverIndex = index;

    // 🔥 gecikmeli shift
    _hoverTimer = Timer(
      0.14, // 🔥 140ms → sweet spot
      onTick: () {
        if (_hoverIndex == index) {
          applyTemporaryShift(index);
        }
      },
    )..start();
  }

  void _cancelHover() {
    _hoverTimer?.stop();
    _hoverTimer = null;
    _hoverIndex = null;
  }

  void clearPreview() {
    previewBox.isVisible = false;
  }

  void moveTileSmooth(PositionComponent tile, Vector2 target) {
    if (tile is TileComponent) {
      tile.currentTarget = target.clone();
    }

    // 🔥 sadece mevcut move effect'i kaldır
    tile.children.whereType<MoveEffect>().toList().forEach(
      (e) => e.removeFromParent(),
    );

    tile.add(
      MoveEffect.to(
        target,
        EffectController(duration: 0.16, curve: Curves.easeOutBack),
      ),
    );
  }

  int? _lastPreviewIndex;

  void _rebuildOccupiedSlots() {
    occupiedSlots.clear();
    for (final tile in tileComponentMap.values) {
      if (!tile.isMounted) continue;
      final idx = tile.currentSlotIndex;
      if (idx == null) continue;
      if (idx < 0 || idx >= slotPositions.length) continue;
      occupiedSlots[idx] = tile;
    }
  }

  bool _slotHasMountedTile(int index, {TileComponent? ignore}) {
    final slotPos = slotPositions[index];
    for (final tile in tileComponentMap.values) {
      if (!tile.isMounted) continue;
      if (ignore != null && identical(tile, ignore)) continue;
      if (tile.currentSlotIndex == index) return true;
      // Fallback: treat tile as occupying this slot if it is visually on it.
      if (tile.position.distanceTo(slotPos) < 1.0) return true;
    }
    return false;
  }

  TileComponent? _mountedTileAtSlot(int index, {TileComponent? ignore}) {
    final slotPos = slotPositions[index];
    for (final tile in tileComponentMap.values) {
      if (!tile.isMounted) continue;
      if (ignore != null && identical(tile, ignore)) continue;
      if (tile.currentSlotIndex == index) return tile;
      if (tile.position.distanceTo(slotPos) < 1.0) return tile;
    }
    return null;
  }

  void applyPreviewShift(int targetIndex, TileComponent draggingTile) {
    _rebuildOccupiedSlots();
    if (_lastPreviewIndex == targetIndex) return;

    _lastPreviewIndex = targetIndex;

    for (final entry in occupiedSlots.entries) {
      final i = entry.key;
      final tile = entry.value;

      if (tile == draggingTile) continue; // 🔥 önemli

      int newIndex = i;

      if (i >= targetIndex) {
        newIndex = i + 1;
      }

      final targetPos = slotPositions[newIndex];

      moveTileSmooth(tile, targetPos); // 🔥 BURASI
    }
  }

  void insertIntoRow(int targetIndex, TileComponent tile) {
    _rebuildOccupiedSlots();
    final row = targetIndex ~/ RackConfig.columns;
    final rowStart = row * RackConfig.columns;
    final rowEnd = rowStart + RackConfig.columns - 1;

    if (tile.currentSlotIndex != null) {
      occupiedSlots.remove(tile.currentSlotIndex);
    }

    final targetMounted = _mountedTileAtSlot(targetIndex, ignore: tile);
    if (targetMounted == null && !occupiedSlots.containsKey(targetIndex)) {
      occupiedSlots[targetIndex] = tile;
      tile.currentSlotIndex = targetIndex;

      moveTileSmooth(tile, slotPositions[targetIndex]); // ✅
      return;
    }
    if (targetMounted != null) {
      occupiedSlots[targetIndex] = targetMounted;
      targetMounted.currentSlotIndex = targetIndex;
    }

    int emptyIndex = -1;
    for (int i = targetIndex + 1; i <= rowEnd; i++) {
      if (_mountedTileAtSlot(i, ignore: tile) == null &&
          !occupiedSlots.containsKey(i)) {
        emptyIndex = i;
        break;
      }
    }

    if (emptyIndex == -1) {
      _restoreTileToOriginalSlot(tile);
      return;
    }

    // 🔥 SHIFT ANİMASYONU
    for (int i = emptyIndex; i > targetIndex; i--) {
      final movingTile = occupiedSlots[i - 1];
      if (movingTile != null) {
        occupiedSlots[i] = movingTile;
        movingTile.currentSlotIndex = i;

        moveTileSmooth(movingTile, slotPositions[i]); // ✅ BURASI
      }
    }

    occupiedSlots.remove(targetIndex);
    occupiedSlots[targetIndex] = tile;
    tile.currentSlotIndex = targetIndex;

    moveTileSmooth(tile, slotPositions[targetIndex]); // ✅ BURASI
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
    _rebuildOccupiedSlots();
    if (_lastPreviewIndex == targetIndex) return; // 🔥 jitter fix

    _lastPreviewIndex = targetIndex;

    final row = targetIndex ~/ RackConfig.columns;
    final rowStart = row * RackConfig.columns;
    final rowEnd = rowStart + RackConfig.columns - 1;

    if (_mountedTileAtSlot(targetIndex, ignore: activeDraggedTile) == null &&
        !occupiedSlots.containsKey(targetIndex)) {
      return;
    }

    int emptyIndex = -1;
    for (int i = targetIndex + 1; i <= rowEnd; i++) {
      if (_mountedTileAtSlot(i, ignore: activeDraggedTile) == null &&
          !occupiedSlots.containsKey(i)) {
        emptyIndex = i;
        break;
      }
    }
    if (emptyIndex == -1) return;

    for (int i = emptyIndex; i > targetIndex; i--) {
      final tile = occupiedSlots[i - 1];
      if (tile != null) {
        if (tile == activeDraggedTile) continue; // 🔥 önemli

        moveTileSmooth(tile, slotPositions[i]); // 🔥 ANİMASYON
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

  Future<bool> discardTile(TileComponent tile) async {
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return false;
    }
    if (_actionInFlight) return false;
    if (_myHandCount != 15) return false;
    final success = await _serverDiscard(tile);
    return success;
  }

  Future<bool> finishWithTile(TileComponent tile) async {
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return false;
    }

    if (_actionInFlight) return false;

    if (_myHandCount != 15) return false;

    return _tryFinish(tile); // 🔥 BURASI DEĞİŞTİ
  }

  Future<bool> _tryFinish(TileComponent tile) async {
    _actionInFlight = true;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _actionInFlight = false;
      return false;
    }

    final slots = _buildSlotsJson(occupiedSlots);

    try {
      final res = await Supabase.instance.client.rpc(
        'game_finish',
        params: {
          'p_table_id': tableId,
          'p_user_id': userId,
          'p_slots': slots,
          'p_last_tile': tile.tile.toJson(),
        },
      );

      if (res != null && res['ok'] == true) {
        // Show finish immediately on client; do not wait for table status roundtrip.
        _finishShown = true;
        _gameStarted = false;
        _cancelStartCountdown();
        final winAmount = (res['win_amount'] as int?) ?? 0;
        final isOkeyFinish = res['is_okey'] == true;
        final isDoubleFinish = res['is_double'] == true;
        final winnerName =
            (res['winner_name']?.toString().isNotEmpty ?? false)
                ? res['winner_name'].toString()
                : getPlayerName(userId);
        final slotPayload = List<Map<String, dynamic>>.from(slots);
        final finishTile = tile.tile.toJson();
        _lastHandledFinishCore = _buildFinishCoreId(
          winnerId: userId,
          slots: slotPayload,
          finishTile: finishTile,
        );
        _lastLocalFinishAt = DateTime.now();
        _clearRenderedHand();
        _clearTableVisualState();
        showFinishFromGame(
          slotPayload,
          finishTile,
          winnerName,
          true,
          false,
          winAmount,
          isOkeyFinish,
          isDoubleFinish,
        );
        return true;
      } else {
        AppMsg.show('El geçersiz');
        return false;
      }
    } catch (e) {
      print(e);
      String msg = 'Bitirme başarısız';

      final err = e.toString();

      if (err.contains('INVALID_FINISH')) {
        msg = 'Geçersiz bitiş';
      } else if (err.contains('INVALID_HAND_COUNT')) {
        msg = 'Taş sayısı hatalı';
      } else if (err.contains('HAND_MISMATCH')) {
        msg = 'Veri senkron hatası';
      } else if (err.contains('INVALID_LAST_TILE')) {
        msg = 'Yanlış taş ile bitiş';
      } else if (err.contains('TABLE_NOT_PLAYING')) {
        msg = 'Oyun aktif değil';
        _gameStarted = false;
        _cancelStartCountdown();
        await _loadInitialState(forceHandSync: false);
      }

      AppMsg.show(msg);
      return false;
    } finally {
      _actionInFlight = false;
    }
    return false;
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
    final now = DateTime.now();
    if (_lastDrawAttemptAt != null &&
        now.difference(_lastDrawAttemptAt!).inMilliseconds < 250) {
      return;
    }
    _lastDrawAttemptAt = now;
    if (_myHandCount >= 15) return;
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
    if (_myHandCount >= 15) return;
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
        tile: fromDiscardTile.tile, // 🔥 direkt model
        position: startPosition.clone(),
      );
    }

    if (closedPile.length > 1) {
      final top = closedPile.last; // 🔥 zaten TileModel
      return TileComponent(tile: top, position: startPosition.clone());
    }

    return null;
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

  TileColor _mapColor(String color) {
    switch (color) {
      case 'red':
        return TileColor.red;
      case 'blue':
        return TileColor.blue;
      case 'black':
        return TileColor.black;
      case 'yellow':
        return TileColor.yellow;
      default:
        return TileColor.red;
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
    final uniqueByColor = <TileColor, _FinishTile>{};
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
    bool tryRunWithExtraJokers() {
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
          return true;
        }
      }
      return false;
    }

    if (tryRunWithExtraJokers()) {
      return true;
    }

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

      if (tryRunWithExtraJokers()) {
        return true;
      }
    }

    memo[key] = false;
    return false;
  }

  Future<void> _fetchAndShowPreviousDiscardTop(int seat, String removedTileId) async {
    try {
      final rows = await Supabase.instance.client
          .from('table_discards')
          .select('tile')
          .eq('table_id', tableId)
          .eq('seat_index', seat)
          .order('created_at', ascending: false)
          .limit(6);
      if (rows is! List) return;

      Map<String, dynamic>? candidate;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final tileRaw = raw['tile'];
        if (tileRaw is! Map) continue;
        final tile = Map<String, dynamic>.from(tileRaw);
        final id = tile['id']?.toString();
        if (id == null || id.isEmpty) continue;
        if (id == removedTileId) continue;
        candidate = tile;
        break;
      }
      if (candidate == null) return;
      final model = _tileModelFromPayload(candidate);
      if (model == null) return;

      final slotIndex = _slotIndexForAbsoluteSeat(seat);
      final slot = _discardSlotsByIndex[slotIndex];
      if (slot == null) return;

      final existing = _discardTopTilesBySeat[seat];
      if (existing != null) {
        if (existing.tile.id == model.id) return;
        existing.removeFromParent();
      }

      final top = TileComponent(
        tile: model,
        position: slot.position.clone(),
      )
        ..priority = 50
        ..isLocked = true;
      world.add(top);
      _discardTopTilesBySeat[seat] = top;
      slot.currentTile = top;
      _pushDiscardStack(seat, model);
    } catch (_) {}
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

class _BotFinishTile {
  final String id;
  final int value;
  final String color;
  final bool isJoker;
  final Map<String, dynamic> payload;

  _BotFinishTile({
    required this.id,
    required this.value,
    required this.color,
    required this.isJoker,
    required this.payload,
  });
}

class _FinishTile {
  final int id;
  final int number;
  final TileColor colorType;
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
      colorType: tile.tile.color,
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

  worst ??= tiles.firstWhere((x) => !x.isOkey, orElse: () => tiles.last);

  for (final tile in normalized) {
    final value = (tile['value'] ?? tile['number'] ?? 0) as int;
    final color = (tile['color'] ?? '').toString();
    if (value == worst!.value && color == worst.color) {
      return tile;
    }
  }

  for (final tile in normalized) {
    final isJoker =
        tile['joker'] == true ||
        tile['is_joker'] == true ||
        tile['fake_joker'] == true ||
        tile['is_fake_joker'] == true;
    if (!isJoker) return tile;
  }

  return normalized.first;
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
    final protectedPenalty = protectedKeys.contains(_botTileMapKey(tile))
        ? 1000
        : 0;

    final betterPotential = potential > bestPotential;
    final equalPotential = potential == bestPotential;
    final betterPenalty =
        equalPotential && protectedPenalty < bestProtectedPenalty;
    final equalPenalty =
        equalPotential && protectedPenalty == bestProtectedPenalty;
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
