import 'dart:async' as async;
import 'confirmed_draw.dart';
import 'game_latency_trace.dart';
import 'components/themed_tile_back.dart';
import 'dart:async';
import 'dart:convert';
import 'rack/timeout_discard_selection.dart';
import 'rack/serial_rack_plan.dart';
import 'dart:math' as math;
import 'game_activity_probe.dart';
import 'bot/bot_observation.dart';
import 'bot/bot_runner.dart';
import 'bot/bot_engine.dart';
import 'observed_effect.dart';
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
import 'package:okeyix/services/debug_event_service.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'bot/okey_bot_turn.dart';

class OkeyGame extends FlameGame with TapDetector implements GameActivityProbeHost {
  final GameActivityProbe? activityProbe = GameActivityProbe.enabled ? GameActivityProbe() : null;
  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  late final World world;
  late final CameraComponent cameraComponent;

  final String tableId;
  final bool isCreator;
  final SupabaseClient? _realtimeClient;
  final SupabaseClient? _botClientOverride;
  final Future<BotDecision> Function(BotObservation)? _botDecisionWorker;
  SupabaseClient get _botClient => _botClientOverride ?? Supabase.instance.client;
  SupabaseClient get _tableRealtimeClient =>
      _realtimeClient ?? Supabase.instance.client;
  bool _lifecycleRemoved = false;
  bool _lifecycleDetached = false;
  int _tableChannelGeneration = 0;
  async.Timer? _reconnectTimer;
  Future<void>? _tableChannelClosing;
  async.Timer? _finishHideTimer;
  DateTime? _finishHideAt;
  bool get _lifecycleActive => !_lifecycleRemoved && !_lifecycleDetached;
  final VoidCallback? onTileSfx;
  final VoidCallback? onStartDealSfx;
  bool isTempShiftActive = false;
  int? tempShiftIndex;

  int currentTurn = 0;
  bool hasDrawnThisTurn = false;
  bool _gameStarted = false;
  bool _startRequestInFlight = false;
  bool _actionInFlight = false;
  bool _botTurnInFlight = false;
  DateTime? _botTurnStartedAt;
  DateTime? _botNoHandRetryAfter;
  String? _lastStallRecoveryToken;
  DateTime? _lastStallRecoveryAt;
  String? _lastBotStallRecoveryToken;
  DateTime? _lastBotStallRecoveryAt;
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
  int? _finishedRoundGuard;
  int _handStateEpoch = 0;
  int _pot = 0;
  bool _hasDrawnFromSourceThisRound = false;
  bool _indicatorBonusClaimedThisRound = false;
  bool _indicatorBonusInFlight = false;
  bool _indicatorBonusAcceptAnyTileForTest = false;
  VoidCallback? onHudChanged;
  void Function(int amount)? onIndicatorBonusAwarded;
  void Function(bool visible)? onFinishVisibilityChanged;
  DateTime? _turnStartedAt;
  DateTime? _lastServerTurnAt;
  int? _lastServerTurnRound;
  DateTime? _enteredPlayingAt;
  String? _lastRenderedHandFingerprint;
  String? _lastDeckVisualSignature;
  int _myHandCount = 0;
  int _committedHandRevision = 0;
  bool _initialDealInProgress = false;
  int _dealtHandRevision = 0;
  Future<TileModel?>? _preparedClosedDraw;
  int _preparedDrawGeneration = 0;
  String? _drawCommittedTurnKey;
  bool _sourceDrawDragActive = false;
  Vector2? _sourceDrawDragPosition;
  DiscardSlotComponent? _sourceDrawFromDiscardSlot;
  TileComponent? _dragHiddenDiscardTile;
  TileComponent? _dragRevealedDiscardTile;
  int? _pendingPreferredDrawSlot;
  TileComponent? _pendingDrawVisualTile;
  Vector2? _rackDrawArrivalStart;
  String? _lastTimeoutTurnToken;
  String? _lastBotTurnToken;
  Function()? onFinish;
  int? _hoverIndex;
  Timer? _hoverTimer;
  bool _uiLocked = false;
  bool _networkInFlight = false;
  DateTime? _lastDrawAttemptAt;
  DateTime? _lastInvariantResyncAt;
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

  // Dragged tiles are painted above the Flutter avatar overlay.
  final ValueNotifier<int> dragOverlayRevision = ValueNotifier<int>(0);
  final Set<TileComponent> _dragOverlayTiles = <TileComponent>{};
  Iterable<TileComponent> get dragOverlayTiles => _dragOverlayTiles;
  bool get _rackInteractionActive =>
      _sourceDrawDragActive || activeDraggedTile != null || _dragOverlayTiles.isNotEmpty;

  void showTileAboveAvatars(TileComponent tile) {
    if (_dragOverlayTiles.add(tile)) {
      tile.renderInDragOverlay = true;
      overlays.add('DraggedTiles');
    }
    notifyDraggedTileMoved();
  }

  void hideTileAboveAvatars(TileComponent tile) {
    if (_dragOverlayTiles.remove(tile)) {
      tile.renderInDragOverlay = false;
      if (_dragOverlayTiles.isEmpty) overlays.remove('DraggedTiles');
      notifyDraggedTileMoved();
    }
  }

  void notifyDraggedTileMoved() {
    dragOverlayRevision.value++;
  }

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
  RealtimeChannel? _indicatorChannel;
  async.Timer? _startWatchdogTimer;
  async.Timer? _startCountdownTimer;
  async.Timer? _turnTimer;
  async.Timer? _handIntegrityTimer;
  bool _handIntegrityInFlight = false;
  async.Timer? _discardPollTimer;
  async.Timer? _tableStatePollTimer;
  TextComponent? _centerStatusText;
  final Map<int, DiscardSlotComponent> _discardSlotsByIndex = {};
  final Map<int, TileComponent> _discardTopTilesBySeat = {};
  final Set<int> _discardAnimationInFlightSeats = <int>{};
  final Map<int, DateTime> _discardSyncHoldUntilBySeat = {};
  // Reject responses that started before a newer local/realtime discard move.
  final Map<int, int> _discardRevisionBySeat = {};
  final Map<int, String> _consumedDiscardTileBySeat = {};
  bool _discardSyncInFlight = false;
  bool _discardSyncRequested = false;

  int _discardRevision(int seat) => _discardRevisionBySeat[seat] ?? 0;
  void _discardChanged(int seat) {
    _discardRevisionBySeat[seat] = _discardRevision(seat) + 1;
  }

  final bool _suppressRemoteDiscardTopAutoCreate = false;
  final Map<int, List<TileModel>> _discardStacksBySeat = {};
  final Set<String> _recentMoveKeys = <String>{};
  final List<String> _recentMoveKeyOrder = <String>[];
  final List<TileComponent> _deferredTileRemovals = [];
  FinishRackView? finishView;
  List<Map<String, dynamic>> playersWithProfiles = [];
  bool isFinishOpen = false;
  int? _lastStartDealSfxRound;
  OkeyGame({
    required this.tableId,
    required this.isCreator,
    this.onTileSfx,
    this.onStartDealSfx,
    SupabaseClient? realtimeClient,
    SupabaseClient? botClient,
    Future<BotDecision> Function(BotObservation)? botDecisionWorker,
  }) : _realtimeClient = realtimeClient, _botClientOverride = botClient,
       _botDecisionWorker = botDecisionWorker;

  void _dbg(
    String tag,
    Map<String, dynamic> data, {
    String? key,
    Duration minInterval = const Duration(seconds: 3),
  }) {
    if (key == null) {
      DebugEventService.log(tag: tag, tableId: tableId, data: data);
      return;
    }
    DebugEventService.logThrottled(
      key: '$tableId:$key',
      tag: tag,
      tableId: tableId,
      data: data,
      minInterval: minInterval,
    );
  }

  void _emitTileSfx() {
    try {
      onTileSfx?.call();
    } catch (_) {
      // Keep gameplay safe even if sound layer fails.
    }
  }

  void _emitStartDealSfx() {
    activityProbe?.event('dealRequested');
    try {
      onStartDealSfx?.call();
    } catch (_) {
      // Keep gameplay safe even if sound layer fails.
    }
  }

  bool get gameStarted => _gameStarted;
  // A dealt tile stays in the hand while its rack slot is free during dragging.
  // Initial-deal completion separately waits for every tile to reach its slot.
  bool get isHandReadyForPlay => _gameStarted && !_initialDealInProgress &&
      !isFinishOpen && tileComponentMap.length >= 14;
  bool _kickedHandled = false;
  int getRound() => _round;
  int getPot() => _pot;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _sessionStartedAt = DateTime.now();
    _initStage();
    await _loadInitialState();
    if (!_lifecycleActive) return;
    _subscribeRealtime();
    _subscribeTablePlayersRealtime();
    _subscribeTableDiscardsRealtime();
    _startStartWatchdog();
    _startTurnTimer();
    _startHandIntegrityMonitor();
    _startDiscardPoll();
    _startLiveTablePoll();
    _subscribeRealtimeMoves();
    _subscribeIndicatorReveals();
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
    // Guarantee clean rack before showing finish overlay.
    if (!_lifecycleActive) return;
    _finishHideTimer?.cancel();
    _clearRenderedHand();
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
    onFinishVisibilityChanged?.call(true);

    for (final slot in _discardSlotsByIndex.values) {
      slot.setHidden(true);
    }
    closedPileComponent?.setHidden(true);
    camera.viewport.add(finishView!);

    _finishHideAt = DateTime.now().add(const Duration(seconds: 4));
    _scheduleFinishHide();
  }

  void _scheduleFinishHide() {
    _finishHideTimer?.cancel();
    final deadline = _finishHideAt;
    if (!_lifecycleActive || deadline == null || !isFinishOpen) return;
    final displayed = finishView;
    final remaining = deadline.difference(DateTime.now());
    _finishHideTimer = async.Timer(remaining.isNegative ? Duration.zero : remaining, () {
      _finishHideTimer = null;
      if (!_lifecycleActive || !identical(finishView, displayed)) return;
      hideFinish();
    });
  }

  void hideFinish() {
    _finishHideTimer?.cancel();
    _finishHideTimer = null;
    _finishHideAt = null;
    if (!_lifecycleActive || (!isFinishOpen && finishView == null)) return;
    finishView?.removeFromParent();
    finishView = null;
    isFinishOpen = false;
    onFinishVisibilityChanged?.call(false);
    _finishShown = false;
    for (final slot in _discardSlotsByIndex.values) {
      slot.setHidden(false);
      slot.onLoad();
    }
    closedPileComponent?.setHidden(false);
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
    if (_lifecycleRemoved) return;
    _lifecycleRemoved = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _finishHideTimer?.cancel();
    _finishHideTimer = null;
    _finishHideAt = null;
    activityProbe?.dispose();
    _releaseTableChannel();

    if (_tablePlayersChannel != null) {
      supabase.removeChannel(_tablePlayersChannel!);
    }

    if (_tableDiscardsChannel != null) {
      supabase.removeChannel(_tableDiscardsChannel!);
    }

    if (_movesChannel != null) {
      supabase.removeChannel(_movesChannel!);
    }
    if (_indicatorChannel != null) {
      supabase.removeChannel(_indicatorChannel!);
    }

    _startWatchdogTimer?.cancel();
    _startCountdownTimer?.cancel();
    _turnTimer?.cancel();
    _handIntegrityTimer?.cancel();
    _discardPollTimer?.cancel();
    _tableStatePollTimer?.cancel();

    _tableChannel = null;
    _tablePlayersChannel = null;
    _tableDiscardsChannel = null;
    _movesChannel = null;
    _indicatorChannel = null;

    _startWatchdogTimer = null;
    _startCountdownTimer = null;
    _turnTimer = null;
    _discardPollTimer = null;
    _tableStatePollTimer = null;

    for (final tile in _dragOverlayTiles) {
      tile.renderInDragOverlay = false;
    }
    _dragOverlayTiles.clear();
    dragOverlayRevision.dispose();
    super.onRemove();
  }

  @override
  void update(double dt) {
    if (GameActivityProbe.enabled) _sampleActivity();
    super.update(dt);
    if (_initialDealInProgress && tileComponentMap.length >= 14 &&
        tileComponentMap.values.every((tile) => tile.isMounted &&
          !tile.isRemoving && !tile.isMovingOnRack &&
          tile.currentSlotIndex != null &&
          identical(occupiedSlots[tile.currentSlotIndex], tile))) {
      _initialDealInProgress = false;
      unawaited(_processMoveQueue());
      unawaited(_syncDiscardTopsFromServer());
      onHudChanged?.call();
    }
    if (_deferredTileRemovals.isEmpty) return;
    final pending = List<TileComponent>.from(_deferredTileRemovals);
    _deferredTileRemovals.clear();
    for (final tile in pending) {
      if (tile.isMounted) {
        tile.removeFromParent();
      }
    }
  }

  void _sampleActivity() {
    final probe = activityProbe;
    if (probe == null) return;
    probe.sample(this,
      pending: hasLifecycleEvents || _deferredTileRemovals.isNotEmpty || _networkInFlight || _actionInFlight || _stateSyncInFlight || _uiLocked || _handIntegrityInFlight,
      dragging: activeDraggedTile != null || _sourceDrawDragActive || _dragOverlayTiles.isNotEmpty);
  }
  @override
  void onGameResize(Vector2 size) {
    activityProbe?.notifyWake(GameWakeReason.resize);
    super.onGameResize(size);
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
    if (!_allowTurnAction()) return;
    if (tile.isJoker && !tile.isFakeJoker) return;
    if (!canDiscardByVoice() || _networkInFlight || tile.isLocked) return;

    autoDiscard(tile);
  }

  Future<void> autoDiscard(TileComponent tile) async {
    if (tile.isJoker && !tile.isFakeJoker) return;
    if (_uiLocked) return;

    tile.stopRackMotion();
    _uiLocked = true;
    final wasLocked = tile.isLocked;
    tile.isLocked = true;

    final originalPos = tile.position.clone();
    final targetPos = getMyDiscardPosition(tile);

    tile.add(
      observeGameEffect(MoveEffect.to(
        targetPos,
        EffectController(duration: 0.18, curve: Curves.easeOut),
        onComplete: () async {
          try {
            final success = await _serverDiscard(tile);
            if (!success && tile.isMounted) {
              tile.add(
                observeGameEffect(MoveEffect.to(originalPos, EffectController(duration: 0.2)), activityProbe, 'okey_game.dart:2'),
              );
            }
          } finally {
            tile.isLocked = wasLocked;
            _isAnimatingRemoteMove = false;
            _uiLocked = false;
          }
        },
      ), activityProbe, 'okey_game.dart:1'),
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

    final visual = TileComponent(tile: model, position: slot.position.clone())
      ..priority = 50
      ..isLocked = true;

    world.add(visual);
    _discardTopTilesBySeat[mySeat] = visual;
    slot.currentTile = visual;
    _pushDiscardStack(mySeat, model);
    _consumedDiscardTileBySeat.remove(mySeat);
    _discardChanged(mySeat);
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
    final requestEpoch = _handStateEpoch;
    final handRevision = _committedHandRevision;
    final dealRevision = _dealtHandRevision;

    dynamic res;
    try {
      res = await supabase.rpc('okeyix_full_table_state',
        params: {'p_table_id': tableId});
    } on PostgrestException catch (error) {
      if (error.code != 'PGRST202') rethrow;
      res = await supabase.rpc('get_full_table_state',
        params: {'p_table_id': tableId});
    }

    if (res == null || requestEpoch != _handStateEpoch) return;

    final table = Map<String, dynamic>.from(res['table']);
    if (table['round_count'] is! int) {
      // Never deal an unversioned hand as round 1 and clear it when polling
      // discovers the actual round. Older RPCs must be upgraded first.
      debugPrint('GAME_SNAPSHOT_ROUND_MISSING: apply 20261028000700_round_aware_game_snapshot.sql');
      return;
    }
    if (table['status'] != 'playing' && dealRevision != _dealtHandRevision) return;
    if (_staleTurnSnapshot(table)) return;
    final incomingRound = table['round_count'];
    final normalizedIncomingRound = _normalizedRoundFromTable(table);
    if (normalizedIncomingRound < _round) return;
    if (table['status'] == 'playing' &&
        _finishedRoundGuard != null &&
        incomingRound is int &&
        incomingRound <= _finishedRoundGuard!)
      return;
    final league = res['league'];
    final rawPlayers = res['players'] as List;
    if (_maybeShowFinishFromTable(table)) return;

    //-------------------------------------------------
    // TABLE
    //-------------------------------------------------
    _maxPlayers = (table['max_players'] as int?) ?? 2;

    _tableEntry = (table['entry_coin'] as int?) ?? 0;
    final tableRoundRaw = table['round_count'];
    bool roundChanged = false;
    if (tableRoundRaw is int) {
      roundChanged = normalizedIncomingRound != _round;
      _round = normalizedIncomingRound;
    }
    if (roundChanged) {
      _handStateEpoch++;
      _clearRenderedHand();
    }
    final snapshotEpoch = _handStateEpoch;
    if (roundChanged && _gameStarted) {
      // New round started -> allow next finish overlay exactly once.
      _finishShown = false;
      // Keep the previous finish receipt deduplicated across round transitions.
    }
    if (roundChanged) {
      _hasDrawnFromSourceThisRound = false;
      _indicatorBonusClaimedThisRound = false;
    }
    _pot = (table['pot_amount'] as int?) ?? _pot;

    final serverTurnStartedAt = _parseServerTime(table['turn_started_at']);
    _applyTurnSnapshot(table);

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
    final playerUserIds = <String>{};

    for (final p in rawPlayers) {
      final map = p as Map<String, dynamic>;
      final userId = map['user_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        playerUserIds.add(userId);
      }

      if (map['user_id']?.toString() == uid) {
        stillInTable = true;
        mySeat = map['seat_index'];
      }

      playersList.add(map);
    }

    // Keep known bot flags while refreshing metadata outside the state/deal
    // transaction. No network await may split applying a table snapshot.
    for (final p in playersList) {
      final known = _playerSeatMap.values.where(
        (old) => old['user_id'] == p['user_id']).firstOrNull;
      if (p['is_bot'] == null && p['user']?['is_bot'] == null && known != null) {
        p['is_bot'] = known['is_bot'] == true || known['user']?['is_bot'] == true;
      }
    }

    // Metadata can arrive after a newer deal/finish or the transition to playing.
    // Do not let an older waiting snapshot clear a rack that is already dealt.
    if (snapshotEpoch != _handStateEpoch ||
        (table['status'] != 'playing' && dealRevision != _dealtHandRevision) ||
        (!wasGameStarted && _gameStarted && table['status'] != 'playing')) {
      return;
    }

    playersWithProfiles = playersList;
    _mySeatIndexAbs = mySeat;

    //-------------------------------------------------
    // KICK CONTROL
    //-------------------------------------------------
    if (!stillInTable && !_kickedHandled) {
      _kickedHandled = true;
      _gameStarted = false;
      // Never clear overlays here; transient player list races can hide HUD/avatars.
      // Screen-level flow should decide navigation/leave behavior.
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
            .where((p) => p['user']?['is_bot'] == true || p['is_bot'] == true)
            .map((p) => p['seat_index'] as int),
      );

    //-------------------------------------------------
    // RENDER
    //-------------------------------------------------
    _renderSeats();
    if (playerUserIds.isNotEmpty) {
      unawaited(_refreshBotMetadata(playersList, snapshotEpoch));
    }

    //-------------------------------------------------
    // STATUS
    //-------------------------------------------------
    final status = table['status'] as String?;
    _dbg(
      'LOAD_INITIAL_STATE',
      {
        'status': status,
        'round': _round,
        'current_turn': currentTurn,
        'player_count': playersWithProfiles.length,
        'max_players': _maxPlayers,
        'force_sync': forceHandSync,
        'game_started': _gameStarted,
      },
      key: 'load_initial_state',
      minInterval: const Duration(seconds: 30),
    );

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

    if (mySeat != null && slotPositions.isNotEmpty &&
        handRevision == _committedHandRevision) {
      final initial = tileComponentMap.isEmpty;
      if (initial) _initialDealInProgress = true;
      _renderMyHand(playersList, applyServerDiff: forceHandSync ||
        !wasGameStarted || initial || roundChanged, hardReset: false);
      if (initial && tileComponentMap.isNotEmpty) _dealtHandRevision++;
    }

    final presentationSync = Future.wait([
      _ensureFreshTurnStartedAt(
        status: status,
        serverTurnStartedAt: serverTurnStartedAt,
      ),
      _syncDiscardTopsFromServer(),
    ]);

    _turnStartedAt ??= DateTime.now();

    // All table/hand state above is applied synchronously, once per snapshot.
    await presentationSync;
    await _validateCriticalInvariants('load_initial_state');
  }

  Future<void> _refreshBotMetadata(List<Map<String, dynamic>> players, int epoch) async {
    try {
      final rows = await Supabase.instance.client.from('users').select('id,is_bot')
        .inFilter('id', players.map((p) => p['user_id']).toList());
      if (!_lifecycleActive || epoch != _handStateEpoch ||
          !identical(playersWithProfiles, players)) return;
      final bots = {for (final row in rows) row['id']: row['is_bot'] == true};
      for (final player in players) {
        if (!bots.containsKey(player['user_id'])) continue;
        final bot = bots[player['user_id']]!;
        player['is_bot'] = bot;
        final user = player['user'] is Map
          ? Map<String, dynamic>.from(player['user'] as Map) : <String, dynamic>{};
        user['is_bot'] = bot;
        player['user'] = user;
      }
      _botSeats
        ..clear()
        ..addAll(players.where((p) => p['is_bot'] == true)
          .map((p) => p['seat_index'] as int));
    } catch (_) {}
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
    return _effectiveHandCount();
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
        _dbg('TRY_START_PRECHECK_ALREADY_PLAYING', {
          'status': status,
          'player_count': playerCount,
          'max_players': maxPlayers,
        }, key: 'try_start_already_playing');
        if (!_stateSyncInFlight) {
          await _loadInitialState(forceHandSync: true);
        }
        return true;
      }

      if (playerCount < maxPlayers) {
        _dbg('TRY_START_PRECHECK_NOT_FULL', {
          'status': status,
          'player_count': playerCount,
          'max_players': maxPlayers,
        }, key: 'try_start_not_full');
        debugPrint(
          'START GAME PRECHECK: table not full ($playerCount/$maxPlayers)',
        );
        return false;
      }

      if (status != 'waiting' && status != 'start') {
        _dbg('TRY_START_PRECHECK_BAD_STATUS', {
          'status': status,
          'player_count': playerCount,
          'max_players': maxPlayers,
        }, key: 'try_start_bad_status');
        debugPrint('START GAME PRECHECK: table status is $status');
        return false;
      }

      await supabase.rpc('start_game', params: {'p_table_id': tableId});
      _dbg('TRY_START_RPC_OK', {
        'status': status,
        'player_count': playerCount,
        'max_players': maxPlayers,
      });
      if (!_stateSyncInFlight) {
        await _loadInitialState(forceHandSync: true);
      }
      return true;
    } catch (e, st) {
      _dbg('TRY_START_RPC_ERROR', {'error': '$e'}, key: 'try_start_rpc_error');
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
      if (_initialDealInProgress) return;
      _maybeRecoverStalledHumanTurn();
      if (_botTurnInFlight &&
          _botTurnStartedAt != null &&
          DateTime.now().difference(_botTurnStartedAt!).inSeconds > 14) {
        final botUserId = _playerSeatMap[currentTurn]?['user_id']?.toString();
        _botTurnInFlight = false;
        _actionInFlight = false;
        _lastBotTurnToken = null;
        if (botUserId != null) {
          unawaited(
            _recoverBotStall(
              botUserId: botUserId,
              expectedTurnToken:
                  '${currentTurn}_${(_turnStartedAt ?? DateTime.now()).millisecondsSinceEpoch}',
            ),
          );
        }
      }
      _maybePlayBotTurn();
      _maybeRecoverStalledBotTurn();
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

  void _maybeRecoverStalledBotTurn() {
    if (!isCreator) return;
    if (!_gameStarted) return;
    if (currentTurn < 0) return;
    if (!_botSeats.contains(currentTurn)) return;
    if (_actionInFlight || _botTurnInFlight) return;

    final startAt = _turnStartedAt;
    if (startAt == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(startAt).inSeconds;
    if (elapsed < (_turnSeconds + 2)) return;

    final token = '${currentTurn}_${startAt.millisecondsSinceEpoch}';
    if (_lastBotStallRecoveryToken == token &&
        _lastBotStallRecoveryAt != null &&
        now.difference(_lastBotStallRecoveryAt!).inSeconds < 3) {
      return;
    }

    final botUserId = _playerSeatMap[currentTurn]?['user_id']?.toString();
    if (botUserId == null || botUserId.isEmpty) return;

    _lastBotStallRecoveryToken = token;
    _lastBotStallRecoveryAt = now;
    unawaited(_recoverBotStall(botUserId: botUserId, expectedTurnToken: token));
  }

  void _maybeRecoverStalledHumanTurn() {
    if (!isCreator) return;
    if (!_gameStarted) return;
    if (_actionInFlight || _botTurnInFlight) return;
    if (currentTurn < 0) return;
    if (_botSeats.contains(currentTurn))
      return; // botlar için ayrı akış zaten var
    final startAt = _turnStartedAt;
    if (startAt == null) return;

    final now = DateTime.now();
    final elapsed = now.difference(startAt).inSeconds;
    if (elapsed < (_turnSeconds + 2)) return;

    final token = '${currentTurn}_${startAt.millisecondsSinceEpoch}';
    if (_lastStallRecoveryToken == token &&
        _lastStallRecoveryAt != null &&
        now.difference(_lastStallRecoveryAt!).inSeconds < 3) {
      return;
    }

    final stalledUserId = _playerSeatMap[currentTurn]?['user_id']?.toString();
    if (stalledUserId == null || stalledUserId.isEmpty) return;

    _lastStallRecoveryToken = token;
    _lastStallRecoveryAt = now;
    unawaited(_recoverStalledHumanTurn(stalledUserId, token));
  }

  Future<void> _recoverStalledHumanTurn(
    String userId,
    String expectedTurnToken,
  ) async {
    try {
      final nowToken =
          '${currentTurn}_${(_turnStartedAt ?? DateTime.now()).millisecondsSinceEpoch}';
      if (nowToken != expectedTurnToken) return;
      await _requestTimeoutMove(userId).timeout(const Duration(seconds: 6));

      await _loadInitialState(forceHandSync: false);
    } catch (e) {
      debugPrint('HUMAN STALL RECOVERY ERROR: $e');
    }
  }

  void _maybePlayBotTurn() {
    if (_initialDealInProgress) return;
    // Bot turns should be orchestrated by any seated human player.
    // In auto-created bot tables, created_by may belong to a system owner user.
    if (_mySeatIndexAbs == null) return;
    if (_actionInFlight || _botTurnInFlight) return;
    if (_botNoHandRetryAfter != null &&
        DateTime.now().isBefore(_botNoHandRetryAfter!)) {
      return;
    }

    if (!_botSeats.contains(currentTurn)) return;

    final startAt = _turnStartedAt ?? DateTime.now();

    final token = '${currentTurn}_${startAt.millisecondsSinceEpoch}';

    if (_lastBotTurnToken == token) return;

    final elapsedMs = DateTime.now().difference(startAt).inMilliseconds;

    if (elapsedMs < 1800) return;

    _lastBotTurnToken = token;

    _botTurnInFlight = true;
    _botTurnStartedAt = DateTime.now();
    _playBotTurn().whenComplete(() {
      _botTurnInFlight = false;
      _botTurnStartedAt = null;
    });
  }

  bool _botPairsEndpointUnavailable = false;
  Future<void> _playBotTurn() => _playStrategicBotTurn();

  @visibleForTesting
  Future<void> debugRunBotTurn({required int seat, required DateTime startedAt,
      int round = 1}) {
    currentTurn = seat;
    _round = round;
    _turnStartedAt = startedAt;
    _botSeats.add(seat);
    _playerSeatMap[seat] = {'user_id': 'bot'};
    _playerSeatMap[1 - seat] = {'user_id': 'human'};
    return _playBotTurn();
  }

  Future<void> _recoverBotStall({
    required String botUserId,
    required String expectedTurnToken,
  }) async {
    try {
      final nowToken =
          '${currentTurn}_${(_turnStartedAt ?? DateTime.now()).millisecondsSinceEpoch}';
      // Turn already progressed, no recovery needed.
      if (nowToken != expectedTurnToken) return;
      if (!_botSeats.contains(currentTurn)) return;

      await Supabase.instance.client
          .rpc(
            'game_timeout_move',
            params: {'p_table_id': tableId, 'p_user_id': botUserId},
          )
          .timeout(const Duration(seconds: 6));
      await _loadInitialState(forceHandSync: false);
    } catch (e) {
      debugPrint('BOT STALL RECOVERY ERROR: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchDiscardTopForSeat(int seatIndex) async {
    try {
      final rows = await _botClient
          .from('table_discards')
          .select('tile')
          .eq('table_id', tableId)
          .eq('seat_index', seatIndex)
          .isFilter('drawn_at', null)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(1)
          .timeout(const Duration(seconds: 2));

      if (rows.isEmpty) {
        return null;
      }
      final tile = rows.first['tile'];
      if (tile is! Map) return null;
      return Map<String, dynamic>.from(tile);
    } catch (_) {
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
    return _buildBotFinishPlan(candidate) != null;
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

  Future<void>? _liveTablePollInFlight;

  Future<void> _pollLiveTableState({bool fresh = false}) async {
    final pending = _liveTablePollInFlight;
    if (pending != null) {
      await pending;
      if (!fresh) return;
      // A post-commit turn read must start after the commit, not reuse an older
      // periodic snapshot which may still contain the previous turn.
      final newer = _liveTablePollInFlight;
      if (newer != null && !identical(newer, pending)) {
        return newer;
      }
    }
    if (!_lifecycleActive) return;
    final probe = activityProbe;
    final operation = probe == null
        ? _pollLiveTableStateObservedBody()
        : probe.observeOperation(() => _pollLiveTableStateObservedBody());
    _liveTablePollInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_liveTablePollInFlight, operation)) {
        _liveTablePollInFlight = null;
      }
    }
  }

  Future<void> _pollLiveTableStateObservedBody() async {
    final pollEpoch = _handStateEpoch;
    try {
      final rows = await Supabase.instance.client
          .from('tables')
          .select(
            'status,current_turn,deck,turn_started_at,pot_amount,round_count,last_finish_at',
          )
          .eq('id', tableId)
          .limit(1);
      if (!_lifecycleActive || pollEpoch != _handStateEpoch) return;
      if ((rows as List).isEmpty) return;
      final table = Map<String, dynamic>.from(rows.first);
      if (_staleTurnSnapshot(table)) return;

      final newRound = _normalizedRoundFromTable(table);
      final newPot = table['pot_amount'] as int?;

      bool changed = false;

      if (newRound != null && newRound > _round) {
        _initialDealInProgress = true;
        _round = newRound;
        _hasDrawnFromSourceThisRound = false;
        _indicatorBonusClaimedThisRound = false;
        _handStateEpoch++;
        _clearRenderedHand();
        changed = true;
        // Yeni turun eli mutlaka sunucudan yeniden kurulmalı.
        unawaited(_loadInitialState(forceHandSync: true));
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
      _applyTurnSnapshot(table);
      if (table['deck'] != null) {
        _syncDeckFromTable(table['deck']);
      }
      if (_gameStarted && _myHandCount < 14 && !_stateSyncInFlight) {
        _stateSyncInFlight = true;
        _loadInitialState(forceHandSync: true).whenComplete(() {
          _stateSyncInFlight = false;
        });
      }
      await _validateCriticalInvariants('poll_live_table_state');
    } catch (_) {}
  }

  bool _isMyTurn() {
    final mySeat = _resolveMySeatIndex();
    if (mySeat == null) return false;
    return currentTurn == mySeat;
  }

  bool _staleTurnSnapshot(Map<String, dynamic> table) {
    final round = _normalizedRoundFromTable(table);
    if (round < _round) return true;
    final stamp = _parseServerTime(table['turn_started_at']);
    return table['status'] == 'playing' && round == _lastServerTurnRound &&
        stamp != null && _lastServerTurnAt != null &&
        stamp.isBefore(_lastServerTurnAt!);
  }

  void _applyTurnSnapshot(Map<String, dynamic> table) {
    if (_staleTurnSnapshot(table)) return;
    final turn = table['current_turn'];
    if (turn is! int) return;
    final stamp = _parseServerTime(table['turn_started_at']);
    final round = _normalizedRoundFromTable(table);
    final newTurn = currentTurn != turn || (stamp != null &&
        (round != _lastServerTurnRound || stamp != _lastServerTurnAt));
    currentTurn = turn;
    if (stamp != null) {
      _lastServerTurnAt = stamp;
      _lastServerTurnRound = round;
      _turnStartedAt = stamp;
    } else if (newTurn) {
      _turnStartedAt = DateTime.now();
    }
    if (newTurn) {
      _actionInFlight = false;
      _lastTimeoutTurnToken = null;
      onHudChanged?.call();
    }
    _recomputeDrawState();
  }

  bool get isMyTurnForLocalUser => _isMyTurn();

  String _currentTurnKey() {
    final turnStartMs = _turnStartedAt?.toUtc().millisecondsSinceEpoch ?? 0;
    return '$_round:$currentTurn:$turnStartMs';
  }

  bool _localDrawCommittedThisTurn() =>
      _drawCommittedTurnKey != null &&
      _drawCommittedTurnKey == _currentTurnKey();

  int _effectiveHandCount() {
    final visible = occupiedSlots.length;
    return _myHandCount > visible ? _myHandCount : visible;
  }

  void _recomputeDrawState() {
    hasDrawnThisTurn =
        _isMyTurn() &&
        (_localDrawCommittedThisTurn() || _effectiveHandCount() >= 15);
  }

  bool _canDrawNow() {
    if (_initialDealInProgress) return false;
    if (!_isMyTurn()) return false;
    if (_indicatorBonusInFlight) {
      AppMsg.show('Gösterge işlemi devam ediyor.');
      return false;
    }
    if (_actionInFlight || _networkInFlight) return false;
    if (_effectiveHandCount() >= 15) return false;
    if (hasDrawnThisTurn || _localDrawCommittedThisTurn()) return false;
    return true;
  }

  void _markDrawCommittedForCurrentTurn() {
    _drawCommittedTurnKey = _currentTurnKey();
    hasDrawnThisTurn = true;
  }

  void _clearDrawCommitForCurrentTurn() {
    _drawCommittedTurnKey = null;
    hasDrawnThisTurn = false;
  }

  int _mountedRackTileCount() {
    var count = 0;
    for (final tile in tileComponentMap.values) {
      if (!tile.isMounted) continue;
      final slot = tile.currentSlotIndex;
      if (slot == null) continue;
      if (slot < 0 || slot >= slotPositions.length) continue;
      count++;
    }
    return count;
  }

  int _mountedLooseRackTileCountInWorld() {
    return world.children
        .whereType<TileComponent>()
        .where((tile) => !tile.isLocked)
        .length;
  }

  Future<void> _hardResyncFromInvariant(String reason) async {
    if (_stateSyncInFlight) return;
    final now = DateTime.now();
    if (_lastInvariantResyncAt != null &&
        now.difference(_lastInvariantResyncAt!).inMilliseconds < 1500) {
      return;
    }
    _lastInvariantResyncAt = now;
    _dbg(
      'INVARIANT_RESYNC',
      {
        'reason': reason,
        'my_turn': _isMyTurn(),
        'hand_count': _myHandCount,
        'visible_count': occupiedSlots.length,
        'mounted_count': _mountedRackTileCount(),
        'has_drawn': hasDrawnThisTurn,
        'draw_committed': _localDrawCommittedThisTurn(),
        'round': _round,
        'turn': currentTurn,
      },
      key: 'invariant_resync',
      minInterval: const Duration(seconds: 1),
    );
    _stateSyncInFlight = true;
    try {
      await _loadInitialState(forceHandSync: true);
    } finally {
      _stateSyncInFlight = false;
    }
  }

  // Reconcile with the authoritative server hand even when local counts look
  // internally consistent (e.g. 13 rendered tiles after a 14-tile hand).
  void _startHandIntegrityMonitor() {
    _handIntegrityTimer?.cancel();
    _handIntegrityTimer = async.Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(_checkAuthoritativeHandIntegrity()),
    );
  }

  Future<void> _checkAuthoritativeHandIntegrity() {
    final probe = activityProbe;
    if (probe == null) return _checkAuthoritativeHandIntegrityObservedBody();
    return probe.observeOperation(() => _checkAuthoritativeHandIntegrityObservedBody());
  }

  Future<void> _checkAuthoritativeHandIntegrityObservedBody() async {
    if (!_gameStarted ||
        isFinishOpen ||
        _handIntegrityInFlight ||
        _actionInFlight ||
        _networkInFlight ||
        _stateSyncInFlight ||
        _sourceDrawDragActive ||
        activeDraggedTile != null ||
        _dragOverlayTiles.isNotEmpty ||
        _uiLocked ||
        _mySeatIndexAbs == null)
      return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _handIntegrityInFlight = true;
    final epoch = _handStateEpoch;
    final round = _round;
    final handRevision = _committedHandRevision;
    try {
      final rows = await Supabase.instance.client
          .from('table_players')
          .select('hand')
          .eq('table_id', tableId)
          .eq('user_id', uid)
          .limit(1)
          .timeout(const Duration(seconds: 7));
      if (handRevision != _committedHandRevision ||
          epoch != _handStateEpoch ||
          round != _round ||
          !_gameStarted ||
          isFinishOpen ||
          _actionInFlight ||
          _networkInFlight ||
          _sourceDrawDragActive ||
          activeDraggedTile != null ||
          _dragOverlayTiles.isNotEmpty ||
          _uiLocked)
        return;
      if (rows is! List || rows.isEmpty) return;
      final hand = rows.first['hand'];
      if (hand is! List || (hand.length != 14 && hand.length != 15)) return;
      final serverIds = <String>{};
      for (final raw in hand) {
        if (raw is! Map) return;
        final id = raw['id']?.toString();
        if (id == null || id.isEmpty || !serverIds.add(id)) return;
      }
      final localIds = tileComponentMap.keys.toSet();
      final consistent =
          serverIds.length == hand.length &&
          localIds.length == serverIds.length &&
          localIds.containsAll(serverIds) &&
          occupiedSlots.length == serverIds.length &&
          tileComponentMap.values.every(
            (tile) =>
                tile.currentSlotIndex != null &&
                occupiedSlots[tile.currentSlotIndex] == tile,
          );
      if (consistent) return;
      _dbg(
        'HAND_SERVER_MISMATCH',
        {
          'server_count': serverIds.length,
          'local_count': localIds.length,
          'slotted_count': occupiedSlots.length,
          'missing_ids': serverIds.difference(localIds).toList(),
          'extra_ids': localIds.difference(serverIds).toList(),
          'round': round,
        },
        key: 'hand_server_mismatch',
        minInterval: const Duration(seconds: 1),
      );
      _renderMyHand([
        <String, dynamic>{'user_id': uid, 'hand': hand},
      ], applyServerDiff: true);
      // Never clear/redeal a live rack as a fallback for an integrity check.
      // An incomplete incremental repair is retried on the next monitor tick.
      // Clearing here destroys the player's private slot arrangement.
      final repaired = tileComponentMap.keys.toSet();
      if (repaired.length != serverIds.length ||
          !repaired.containsAll(serverIds) ||
          occupiedSlots.length != serverIds.length) {
        _dbg(
          'HAND_REPAIR_DEFERRED',
          {
            'server_count': serverIds.length,
            'local_count': repaired.length,
            'slotted_count': occupiedSlots.length,
          },
          key: 'hand_repair_deferred',
          minInterval: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      _dbg(
        'HAND_INTEGRITY_CHECK_ERROR',
        {'error': '$e'},
        key: 'hand_integrity_error',
        minInterval: const Duration(seconds: 15),
      );
    } finally {
      _handIntegrityInFlight = false;
    }
  }

  Future<void> _validateCriticalInvariants(String source) async {
    // A dragged rack tile deliberately has no slot until drop. This is not a
    // corrupt hand, nor is an in-flight draw/discard a stable snapshot to audit.
    if (!_gameStarted || _rackInteractionActive || _actionInFlight ||
        _networkInFlight || _uiLocked) return;
    // Flame mounts added tiles on a later lifecycle pass. The slot map is
    // already committed during dealing; comparing it with mounted-only counts
    // in this interval would incorrectly request another full hand.
    if (tileComponentMap.values.any((tile) =>
        !tile.isMounted && !tile.isRemoving && !tile.isRemoved)) return;

    final effective = _effectiveHandCount();
    final mounted = _mountedRackTileCount();
    final worldMounted = _mountedLooseRackTileCountInWorld();
    final visible = occupiedSlots.length;
    final myTurn = _isMyTurn();
    final drawCommitted = _localDrawCommittedThisTurn();

    if (effective > 15 || mounted > 15 || visible > 15) {
      await _hardResyncFromInvariant('$source:hand_overflow');
      return;
    }

    if (worldMounted > mounted) {
      await _hardResyncFromInvariant('$source:orphan_world_tiles');
      return;
    }

    if (mounted != visible) {
      await _hardResyncFromInvariant('$source:rack_map_mismatch');
      return;
    }

    if (myTurn && (hasDrawnThisTurn || drawCommitted) && effective < 15) {
      await _hardResyncFromInvariant('$source:draw_state_without_15');
      return;
    }

    if (!myTurn && effective > 14) {
      await _hardResyncFromInvariant('$source:not_my_turn_with_15');
      return;
    }
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

      // 🔥 waiting/start UI + start recovery kontrol
      final playerRows = await Supabase.instance.client
          .from('table_players')
          .select('id')
          .eq('table_id', tableId);

      final playerCount = (playerRows as List).length;
      _dbg('SYNC_WAITING_PLAYING', {
        'status': status,
        'player_count': playerCount,
        'max_players': _maxPlayers,
        'game_started': _gameStarted,
      }, key: 'sync_waiting_playing');

      if (status == 'waiting' || status == 'start') {
        if (playerCount < _maxPlayers) {
          _hideWaitingOverlay(); // oyuncu bekleniyor
          _cancelStartCountdown();
          _startCalled = false;
          return;
        }
        // Table is full but not playing yet: aggressively re-run start flow.
        await _ensureGameStartIfReady(
          knownStatus: status,
          knownPlayerCount: playerCount,
        );
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
        _dbg('ENSURE_START_READY', {
          'status': status,
          'player_count': playerCount,
          'max_players': _maxPlayers,
          'countdown_in_progress': _countdownInProgress,
          'game_started': _gameStarted,
        }, key: 'ensure_start_ready');
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
    _dbg('COUNTDOWN_STARTED', {
      'seconds_left': 5,
      'current_turn': currentTurn,
      'game_started': _gameStarted,
    }, key: 'countdown_started');
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
      _dbg('COUNTDOWN_DONE_TRY_START', {
        'started': started,
        'game_started': _gameStarted,
      }, key: 'countdown_done_try_start');
      if (!started) {
        // Retry with a fresh local countdown instead of getting stuck.
        _dbg('COUNTDOWN_RETRY', {
          'game_started': _gameStarted,
          'current_turn': currentTurn,
        }, key: 'countdown_retry');
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
    if (_rackInteractionActive && !hardReset) return;
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
        _recomputeDrawState();
        return;
      }
      if (!applyServerDiff) {
        _myHandCount = occupiedSlots.length;
        _recomputeDrawState();
        return;
      }
      _myHandCount = hand.length;
      final fingerprint = _handFingerprint(hand);
      final incomingCount = hand.whereType<Map>().length;
      final incomingIds = hand
          .whereType<Map>()
          .map((tile) => tile['id']?.toString())
          .whereType<String>()
          .toSet();
      if (fingerprint == _lastRenderedHandFingerprint &&
          tileComponentMap.keys.toSet().containsAll(incomingIds) &&
          tileComponentMap.length == incomingCount &&
          occupiedSlots.length == incomingCount &&
          tileComponentMap.values.every(
            (tile) =>
                tile.currentSlotIndex != null &&
                occupiedSlots[tile.currentSlotIndex] == tile,
          )) {
        _recomputeDrawState();
        return;
      }
      if (hardReset || tileComponentMap.isEmpty) {
        // Concurrent start refreshes may both request a hard reset. Check the
        // existing rack above first so the same deal is only laid out once.
        if (hardReset) _clearRenderedHand();
        _myHandCount = hand.length;
        _renderHand(hand);
      } else {
        _syncHandIncremental(hand);
      }
      // Never acknowledge a hand snapshot unless every server tile has a rack slot.
      // Otherwise the next identical snapshot must retry the missing tile.
      final fullyPlaced =
          tileComponentMap.length == incomingCount &&
          occupiedSlots.length == incomingCount &&
          tileComponentMap.values.every(
            (tile) =>
                tile.currentSlotIndex != null &&
                occupiedSlots[tile.currentSlotIndex] == tile,
          );
      _lastRenderedHandFingerprint = fullyPlaced ? fingerprint : null;
      if (!fullyPlaced) {
        _dbg(
          'HAND_RENDER_INCOMPLETE',
          {
            'server_count': incomingCount,
            'tracked_count': tileComponentMap.length,
            'slotted_count': occupiedSlots.length,
            'round': _round,
          },
          key: 'hand_render_incomplete',
          minInterval: const Duration(seconds: 1),
        );
      }
      _recomputeDrawState();
      unawaited(_validateCriticalInvariants('render_my_hand'));
    }
  }

  void _syncHandIncremental(List<dynamic> hand) {
    _cleanupOrphanRackTiles();
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

    _rebuildOccupiedSlots();

    // A server snapshot is authoritative for tile membership, never for the
    // user's visual rack order. Keep every surviving tile in its local slot.
    _repairRackSlotAssignments();
    final preservedSlots = <String, int>{};
    for (final entry in tileComponentMap.entries) {
      final slot = entry.value.currentSlotIndex;
      if (slot != null && slot >= 0 && slot < slotPositions.length) {
        preservedSlots[entry.key] = slot;
      }
    }
    final hasNewTiles = parsedById.keys.any(
      (id) => !tileComponentMap.containsKey(id),
    );

    for (final model in parsedById.values) {
      final existing = tileComponentMap[model.id];
      if (existing != null && !existing.isRemoving && !existing.isRemoved) continue;
      if (existing != null) tileComponentMap.remove(model.id);
      int slotIndex;
      int? preferredSlot;
      bool forceInsertWithShift = false;
      if (_pendingPreferredDrawSlot != null) {
        preferredSlot = _pendingPreferredDrawSlot!;
        slotIndex = preferredSlot;
        _pendingPreferredDrawSlot = null;
      } else {
        slotIndex = _pickStableSlotForTileId(model.id);
      }
      if (preferredSlot != null) {
        final preferredBusy =
            _mountedTileAtSlot(preferredSlot, ignore: null) != null ||
            occupiedSlots.containsKey(preferredSlot);
        if (preferredBusy) {
          // Keep spawn at preferred slot so insert animation does not "jump"
          // through a temporary empty slot.
          slotIndex = preferredSlot;
          forceInsertWithShift = true;
        } else {
          slotIndex = _resolveSafeRackSlot(slotIndex);
        }
      } else {
        slotIndex = _resolveSafeRackSlot(slotIndex);
      }
      if (slotIndex == -1) {
        // An animated tile can visually overlap a free slot for a frame.
        // Its authoritative rack slot is currentSlotIndex, not its position.
        slotIndex = _findFirstUnmappedRackSlot();
      }
      if (slotIndex == -1) {
        _dbg(
          'HAND_TILE_NO_SLOT',
          {
            'tile_id': model.id,
            'tracked_count': tileComponentMap.length,
            'slot_count': occupiedSlots.length,
            'capacity': slotPositions.length,
          },
          key: 'hand_tile_no_slot',
          minInterval: const Duration(seconds: 1),
        );
        continue;
      }

      final arrivalStart = _pendingDrawVisualTile?.position.clone() ?? _rackDrawArrivalStart?.clone();
      if (arrivalStart != null) _clearPendingDrawVisualTile();
      final tile = TileComponent(
        tile: model,
        position: arrivalStart ?? slotPositions[slotIndex].clone(),
      );
      tileComponentMap[model.id] = tile;
      world.add(tile);

      final shouldInsertWithShift =
          forceInsertWithShift ||
          (preferredSlot != null &&
              (_mountedTileAtSlot(preferredSlot, ignore: tile) != null ||
                  occupiedSlots.containsKey(preferredSlot)));

      if (shouldInsertWithShift) {
        tile.currentSlotIndex = null;
        insertIntoRow(preferredSlot ?? slotIndex, tile);
        if (tile.currentSlotIndex != null) {
          _lastKnownSlotByTileId[model.id] = tile.currentSlotIndex!;
        }
      } else {
        tile.currentSlotIndex = slotIndex;
        _lastKnownSlotByTileId[model.id] = slotIndex;
        occupiedSlots[slotIndex] = tile;
        if (arrivalStart != null) tile.moveOnRack(slotPositions[slotIndex]);
      }
    }

    // Do not undo the intended rack insertion shift when a new drawn tile is
    // inserted into an occupied preferred slot. Otherwise restore exact slots
    // for all surviving tiles after a membership-only reconciliation.
    if (!hasNewTiles) {
      for (final entry in preservedSlots.entries) {
        final tile = tileComponentMap[entry.key];
        if (tile == null || !tile.isMounted) continue;
        tile.currentSlotIndex = entry.value;
        final target = slotPositions[entry.value];
        if (!tile.isMovingOnRack || tile.currentTarget == null ||
            tile.currentTarget!.distanceToSquared(target) >= .001) {
          tile.stopRackMotion();
          tile.position = target.clone();
        }
        _lastKnownSlotByTileId[entry.key] = entry.value;
      }
      _rebuildOccupiedSlots();
    }
    _repairRackSlotAssignments();
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

  void _cleanupOrphanRackTiles() {
    final tracked = tileComponentMap.values.toSet();
    final rackTiles = world.children
        .whereType<TileComponent>()
        .where((tile) => !tile.isLocked)
        .toList(growable: false);
    for (final tile in rackTiles) {
      if (tracked.contains(tile)) continue;
      tile.removeFromParent();
    }
    _rebuildOccupiedSlots();
  }

  void _renderHand(List<dynamic> hand) {
    activityProbe?.event('handRenderCandidate');
    _cleanupOrphanRackTiles();
    final parsed = <TileModel>[];
    final parsedIds = <String>{};
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

      if (!parsedIds.add(model.id)) continue;
      parsed.add(model);
      tileMap[model.id] = model;
    }

    if (parsed.length < 14) {
      return;
    }

    if (wasHandEmptyBeforeRender) {
      // Safety: prevent duplicate full-hand visuals from stale local components.
      _purgeRackTilesHard();
      if (_lastStartDealSfxRound != _round) {
        _lastStartDealSfxRound = _round;
        _emitStartDealSfx();
      }
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

    _rebuildOccupiedSlots();
    List<int>? slotPlan;
    if (wasHandEmptyBeforeRender) {
      slotPlan = _buildSmartRackPlan(parsed);
    }

    //-------------------------------------------------
    // 3. ADD → sadece yeni gelenleri ekle
    //-------------------------------------------------
    for (int i = 0; i < parsed.length; i++) {
      final model = parsed[i];

      // Already rendered and mounted: keep it.
      final existing = tileComponentMap[model.id];
      if (existing != null) {
        if (!existing.isRemoving) {
          final existingSlot = existing.currentSlotIndex;
          if (existingSlot != null &&
              existingSlot >= 0 &&
              existingSlot < slotPositions.length) {
            occupiedSlots[existingSlot] = existing;
          }
          continue;
        }
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

      slotIndex = _resolveSafeRackSlot(slotIndex);
      if (slotIndex == -1) {
        // An animated tile can visually overlap a free slot for a frame.
        // Its authoritative rack slot is currentSlotIndex, not its position.
        slotIndex = _findFirstUnmappedRackSlot();
      }
      if (slotIndex == -1) {
        _dbg(
          'HAND_TILE_NO_SLOT',
          {
            'tile_id': model.id,
            'tracked_count': tileComponentMap.length,
            'slot_count': occupiedSlots.length,
            'capacity': slotPositions.length,
          },
          key: 'hand_tile_no_slot',
          minInterval: const Duration(seconds: 1),
        );
        continue;
      }

      //-------------------------------------------------
      // TILE OLUŞTUR
      //-------------------------------------------------
      final initialPos = wasHandEmptyBeforeRender
          ? (closedPileComponent?.position ?? Vector2(800, 430)).clone()
          : slotPositions[slotIndex].clone();
      final tile = TileComponent(tile: model, position: initialPos);

      tile.currentSlotIndex = slotIndex;
      _lastKnownSlotByTileId[model.id] = slotIndex;
      tileComponentMap[model.id] = tile;
      occupiedSlots[slotIndex] = tile;

      world.add(tile);
      if (wasHandEmptyBeforeRender) {
        // Absolute, cancellable motion: a snapshot/drag/sort may pin this tile
        // mid-deal without a queued relative effect moving it off the rack.
        tile.dealOnRack(slotPositions[slotIndex], startDelay: i * .025);
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

  int _findFirstActuallyEmptySlot({TileComponent? ignore}) {
    for (int i = 0; i < slotPositions.length; i++) {
      final hasMapped = occupiedSlots.containsKey(i);
      final hasMounted = _slotHasMountedTile(i, ignore: ignore);
      if (!hasMapped && !hasMounted) {
        return i;
      }
    }
    return -1;
  }

  // Fallback only when transient visual overlap blocks a logically free slot.
  // Do not overwrite a tile already assigned to that slot.
  int _findFirstUnmappedRackSlot() {
    final assigned = <int>{...occupiedSlots.keys};
    for (final tile in tileComponentMap.values) {
      final slot = tile.currentSlotIndex;
      if (slot != null && slot >= 0 && slot < slotPositions.length) {
        assigned.add(slot);
      }
    }
    for (var i = 0; i < slotPositions.length; i++) {
      if (!assigned.contains(i)) return i;
    }
    return -1;
  }

  int _resolveSafeRackSlot(int preferred, {TileComponent? ignore}) {
    final preferredValid = preferred >= 0 && preferred < slotPositions.length;
    if (preferredValid) {
      final mappedConflict = occupiedSlots.containsKey(preferred);
      final mountedConflict = _slotHasMountedTile(preferred, ignore: ignore);
      if (!mappedConflict && !mountedConflict) {
        return preferred;
      }
    }
    return _findFirstActuallyEmptySlot(ignore: ignore);
  }

  void _clearRenderedHand() {
    for (final tile in _indicatorRevealTiles) {
      tile.removeFromParent();
    }
    _indicatorRevealTiles.clear();
    // Pending additions are not in world.children yet. Cancel them as well,
    // otherwise the previous deal can appear after the next deal was queued.
    for (final tile in tileComponentMap.values.toList()) {
      tile.removeFromParent();
    }
    if (_deferredTileRemovals.isNotEmpty) {
      final pending = List<TileComponent>.from(_deferredTileRemovals);
      _deferredTileRemovals.clear();
      for (final tile in pending) {
        if (tile.isMounted) {
          tile.removeFromParent();
        }
      }
    }
    if (activeDraggedTile != null) hideTileAboveAvatars(activeDraggedTile!);
    activeDraggedTile?.removeFromParent();
    activeDraggedTile = null;
    _clearPendingDrawVisualTile();
    _rackDrawArrivalStart = null;
    final looseTiles = world.children
        .whereType<TileComponent>()
        .where((tile) => !tile.isLocked)
        .toList(growable: false);
    for (final tile in looseTiles) {
      tile.removeFromParent();
    }
    tileComponentMap.clear();
    tileMap.clear();
    _lastKnownSlotByTileId.clear();
    occupiedSlots.clear();
    _lastRenderedHandFingerprint = null;
    _myHandCount = 0;
    _clearDrawCommitForCurrentTurn();
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

  String _pairKeyFromModel(TileModel t) {
    final joker = t.isJoker || t.isFakeJoker ? 1 : 0;
    return '${t.color.index}-${t.value}-$joker';
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

  List<int> _buildSmartRackPlan(List<TileModel> tiles) {
    return serialRackPlan(tiles, columns: RackConfig.columns);
  }

  void arrangeSerial() {
    if (occupiedSlots.isEmpty) return;
    final entries = occupiedSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final tiles = entries.map((e) => e.value.tile).toList(growable: false);
    final plan = _buildSmartRackPlan(tiles);
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
      final key = _pairKeyFromModel(ref.tile);
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
      final ka = _pairKeyFromModel(a.first.tile);
      final kb = _pairKeyFromModel(b.first.tile);
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
      tile.stopRackMotion();
      occupiedSlots[slot] = tile;
      tile.currentSlotIndex = slot;
      tile.originalSlotIndex = slot;
      tile.position = slotPositions[slot];
    }
    clearPreview();
    clearTemporaryShift();
  }

  bool arrangeSerialByVoice() {
    if (occupiedSlots.isEmpty) return false;
    arrangeSerial();
    return true;
  }

  bool isPointNearIndicator(Vector2 worldPoint) {
    final indicator = indicatorTileComponent;
    if (indicator == null || !indicator.isMounted) return false;
    final center = indicator.position;
    final dx = (worldPoint.x - center.x).abs();
    final dy = (worldPoint.y - center.y).abs();
    return dx <= 70 && dy <= 95;
  }

  bool _isMatchingIndicatorTile(TileComponent tile) {
    if (_indicatorBonusAcceptAnyTileForTest) return true;
    final indicator = indicatorTileComponent;
    if (indicator == null) return false;
    if (tile.isJoker || tile.isFakeJoker) return false;
    return tile.value == indicator.value && tile.color == indicator.color;
  }

  Future<bool> tryClaimIndicatorBonus(TileComponent tile) async {
    if (_indicatorBonusInFlight) return false;
    if (_indicatorBonusClaimedThisRound) {
      AppMsg.show('Gösterge bonusu bu elde zaten alındı');
      return false;
    }
    if (!_indicatorBonusAcceptAnyTileForTest && !canClaimIndicatorBonus) {
      AppMsg.show(_hasDrawnFromSourceThisRound
          ? 'Gösterge, ilk taşını çekmeden önce yapılabilir.'
          : !_gameStarted || isFinishOpen
          ? 'Gösterge yalnızca el devam ederken yapılabilir.'
          : 'Devam eden işlemin tamamlanmasını bekle.');
      return false;
    }
    if (!_isMatchingIndicatorTile(tile)) {
      final indicator = indicatorTileComponent?.tile;
      debugPrint(
        'INDICATOR_MISMATCH drop=${tile.tile.id}/${tile.tile.color}/${tile.tile.value} '
        'ind=${indicator?.id}/${indicator?.color}/${indicator?.value} '
        'dropJ=${tile.isJoker}/${tile.isFakeJoker} indJ=${indicator?.isJoker}/${indicator?.isFakeJoker}',
      );
      AppMsg.show('Bırakılan taş gösterge ile eşleşmiyor');
      return false;
    }
    final indicator = indicatorTileComponent;
    if (indicator == null) return false;

    _indicatorBonusInFlight = true;
    final start = tile.position.clone();
    final target = indicator.position.clone();
    try {
      tile.add(
        observeGameEffect(SequenceEffect([
          observeGameEffect(MoveEffect.to(
            target,
            EffectController(duration: 0.18, curve: Curves.easeOut),
          ), activityProbe, 'okey_game.dart:5'),
          observeGameEffect(RotateEffect.by(
            6.28318,
            EffectController(duration: 0.35, curve: Curves.easeInOut),
          ), activityProbe, 'okey_game.dart:6'),
          observeGameEffect(MoveEffect.to(
            start,
            EffectController(duration: 0.2, curve: Curves.easeInOut),
          ), activityProbe, 'okey_game.dart:7'),
        ]), activityProbe, 'okey_game.dart:4'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 760));

      if (_indicatorBonusAcceptAnyTileForTest) {
        _indicatorBonusClaimedThisRound = true;
        onIndicatorBonusAwarded?.call(1);
        return true;
      }

      final reward = await _claimIndicatorBonusFromPot();
      if (reward <= 0) return false;
      _indicatorBonusClaimedThisRound = true;
      onIndicatorBonusAwarded?.call(reward);
      return true;
    } catch (e) {
      debugPrint('INDICATOR BONUS ERROR: $e');
      AppMsg.show('Gösterge işlemi tamamlanamadı. Lütfen tekrar dene.');
      return false;
    } finally {
      _indicatorBonusInFlight = false;
    }
  }

  bool get canClaimIndicatorBonus =>
      _gameStarted && !isFinishOpen &&
      !_hasDrawnFromSourceThisRound && !_indicatorBonusClaimedThisRound &&
      !_indicatorBonusInFlight && !_actionInFlight && !_networkInFlight;

  @visibleForTesting
  void debugIndicatorBonusState({bool drawn = false, bool claimed = false,
      bool playing = true, int turn = 0}) {
    _gameStarted = playing;
    _hasDrawnFromSourceThisRound = drawn;
    _indicatorBonusClaimedThisRound = claimed;
    currentTurn = turn;
  }

  Future<int> _claimIndicatorBonusFromPot() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return 0;
    final client = Supabase.instance.client;
    try {
      final tableRow = await client
          .from('tables')
          .select('pot_amount')
          .eq('id', tableId)
          .maybeSingle();
      final currentPot = (tableRow?['pot_amount'] as int?) ?? _pot;
      final reward = (currentPot * 0.10).floor();
      if (reward <= 0) {
        AppMsg.show('Çanak ödülü için yeterli bakiye yok.');
        return 0;
      }
      final nextPot = currentPot - reward;
      final potUpdated = await client
          .from('tables')
          .update({'pot_amount': nextPot})
          .eq('id', tableId)
          .eq('pot_amount', currentPot)
          .select('id,pot_amount')
          .limit(1);
      if ((potUpdated as List).isEmpty) {
        AppMsg.show('Çanak bilgisi değişti. Göstergeyi tekrar dene.');
        return 0;
      }

      final profileRow = await client
          .from('profiles')
          .select('coins')
          .eq('id', userId)
          .maybeSingle();
      final currentCoins = (profileRow?['coins'] as int?) ?? UserState.userCoin;
      final nextCoins = currentCoins + reward;
      final creditedProfile = await client.from('profiles').update({
        'coins': nextCoins,
      }).eq('id', userId).select('id').limit(1);
      if ((creditedProfile as List).isEmpty) {
        throw StateError('INDICATOR_PROFILE_UPDATE_REJECTED');
      }
      await client.from('wallet_transactions').insert({
        'user_id': userId,
        'amount': reward,
        'reason': 'indicator_bonus',
        'type': 'credit',
        'store': 'system',
        'note': 'indicator_bonus:$tableId',
      });

      _pot = nextPot;
      UserState.userCoin = nextCoins;
      onHudChanged?.call();
      return reward;
    } catch (e) {
      debugPrint('INDICATOR BONUS DB ERROR: $e');
      AppMsg.show('Gösterge ödülü alınamadı. Lütfen tekrar dene.');
      return 0;
    }
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

  Future<void> _subscribeRealtime() async {
    if (!_lifecycleActive) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final generation = ++_tableChannelGeneration;
    final previous = _tableChannel;
    _tableChannel = null;
    final closing = previous != null
        ? _tableRealtimeClient.removeChannel(previous).then<void>((_) {})
        : _tableChannelClosing;
    if (closing != null) await closing;
    if (!_lifecycleActive || generation != _tableChannelGeneration) return;
    final channel = _tableRealtimeClient.channel('table_$tableId');
    _tableChannel = channel;
    bool current() => _lifecycleActive && generation == _tableChannelGeneration &&
        identical(_tableChannel, channel);
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public', table: 'tables',
      filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
        column: 'id', value: tableId),
      callback: (payload) {
        if (!current()) return;
        _handleTableUpdate(payload.newRecord);
      },
    );
    channel.subscribe((status, [error]) {
      if (!current()) return;
      if (status == RealtimeSubscribeStatus.subscribed) {
        _reconnectAttempt = 0;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        if (_gameStarted) {
          // Recover changes missed during reconnect without waiting for a poll.
          unawaited(_pollLiveTableState(fresh: true));
          unawaited(_syncDiscardTopsFromServer());
        }
      }
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.closed) {
        _reconnectTableChannel();
      }
    });
  }

  int _reconnectAttempt = 0;

  void _reconnectTableChannel() {
    if (!_lifecycleActive || _reconnectTimer?.isActive == true || _reconnectAttempt >= 6) return;
    final generation = _tableChannelGeneration;
    final delay = Duration(seconds: ++_reconnectAttempt);
    _reconnectTimer = async.Timer(delay, () {
      _reconnectTimer = null;
      if (!_lifecycleActive || generation != _tableChannelGeneration) return;
      unawaited(_subscribeRealtime());
    });
  }

  void _releaseTableChannel() {
    ++_tableChannelGeneration;
    final channel = _tableChannel;
    _tableChannel = null;
    if (channel != null) {
      _tableChannelClosing = _tableRealtimeClient.removeChannel(channel).then<void>((_) {});
    }
  }

  @override
  void onAttach() {
    super.onAttach();
    if (_lifecycleRemoved) return;
    _lifecycleDetached = false;
    if (isLoaded && _tableChannel == null) unawaited(_subscribeRealtime());
    _scheduleFinishHide();
  }

  @override
  void onDetach() {
    _lifecycleDetached = true;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _finishHideTimer?.cancel();
    _finishHideTimer = null;
    _releaseTableChannel();
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

  final Set<String> _revealedIndicators = {};
  final Set<TileComponent> _indicatorRevealTiles = {};

  void _subscribeIndicatorReveals() {
    if (_stabilityMode) return;
    _indicatorChannel = Supabase.instance.client
        .channel('indicator_reveals:$tableId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public', table: 'table_indicator_events',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
            column: 'table_id', value: tableId),
          callback: (payload) => _receiveIndicatorReveal(payload.newRecord),
        ).subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(_recoverIndicatorReveals());
          }
        });
  }

  Future<void> _recoverIndicatorReveals() async {
    try {
      // Recover a notification lost during subscription/reconnection. Do not
      // replay older celebrations when entering an already-running table.
      final rows = await Supabase.instance.client.from('table_indicator_events')
          .select().eq('table_id', tableId).eq('round_no', _round)
          .gte('created_at', DateTime.now().toUtc()
            .subtract(const Duration(seconds: 5)).toIso8601String())
          .order('created_at').limit(4).timeout(const Duration(seconds: 5));
      for (final row in rows) {
        _receiveIndicatorReveal(row);
      }
    } catch (error) {
      debugPrint('INDICATOR REVEAL RECOVERY: $error');
    }
  }

  bool _receiveIndicatorReveal(Map<String, dynamic> event) {
    final playerId = event['player_id']?.toString();
    final id = event['id']?.toString();
    final indicator = indicatorTileComponent;
    final seat = playerId == null ? null : _seatFromUserId(playerId);
    if (!_lifecycleActive || !_gameStarted || isFinishOpen ||
        event['table_id'] != tableId || event['round_no'] != _round ||
        id == null || seat == null || seat == _resolveMySeatIndex() ||
        playerId == UserState.userId || indicator == null ||
        _revealedIndicators.contains(id)) return false;
    _revealedIndicators.add(id);
    if (_revealedIndicators.length > 120) {
      _revealedIndicators.remove(_revealedIndicators.first);
    }
    final start = _drawAnimationTargetForSeat(seat);
    final tile = TileComponent(
      tile: TileModel(id: 'indicator-reveal:$id', value: indicator.value,
        color: indicator.color),
      position: start.clone(),
    )..isLocked = true
     ..priority = 100;
    _indicatorRevealTiles.add(tile);
    world.add(tile);
    tile.add(SequenceEffect([
      MoveEffect.to(indicator.position.clone(),
        EffectController(duration: .18, curve: Curves.easeOut)),
      RotateEffect.by(6.28318,
        EffectController(duration: .35, curve: Curves.easeInOut)),
      MoveEffect.to(start,
        EffectController(duration: .2, curve: Curves.easeInOut)),
    ], onComplete: () {
      _indicatorRevealTiles.remove(tile);
      tile.removeFromParent();
    }));
    return true;
  }

  @visibleForTesting
  bool debugReceiveIndicatorReveal(Map<String, dynamic> event,
      {required String opponent}) {
    _playerSeatMap[1] = {'user_id': opponent};
    return _receiveIndicatorReveal(event);
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
    if (_initialDealInProgress) return;
    if (_processingQueue) return;

    _processingQueue = true;

    try {
      while (_moveQueue.isNotEmpty && !_initialDealInProgress) {
        final move = _moveQueue.removeAt(0);
        try {
          await _handleMove(move);
        } catch (e) {
          debugPrint('MOVE PRESENTATION ERROR: $e');
          // One malformed visual event must not freeze all subsequent moves.
          unawaited(_syncDiscardTopsFromServer());
        }
      }
    } finally {
      _processingQueue = false;
    }
  }

  Future<void> _handleMove(Map<String, dynamic> move) {
    final probe = activityProbe;
    if (probe == null) return _handleMoveObservedBody(move);
    return probe.observeOperation(() => _handleMoveObservedBody(move));
  }

  Future<void> _handleMoveObservedBody(Map<String, dynamic> move) async {
    final type = move['move_type']?.toString();
    final playerId = move['player_id'];
    final myUserId = UserState.userId;

    // Never replay our own realtime moves locally; local UX already handled.
    if (myUserId != null &&
        playerId != null &&
        playerId.toString() == myUserId) {
      return;
    }

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

    if (type == 'draw_deck') {
      await _animateClosedPileToPlayer(seat);
      return;
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

  void _holdDiscardSeatSync(
    int seat, {
    Duration duration = const Duration(milliseconds: 900),
  }) {
    _discardChanged(seat);
    _discardSyncHoldUntilBySeat[seat] = DateTime.now().add(duration);
  }

  // Other players must only see the back of a tile drawn from the deck.
  Future<void> _animateClosedPileToPlayer(int toSeat) async {
    final pile = closedPileComponent;
    if (pile == null || !pile.isMounted) return;

    final backImage = await images.load('tile_back.png');
    final transient = ThemedTileBack(
      sprite: Sprite(backImage),
      position: pile.position.clone(),
      size: Vector2(RackConfig.tileWidth, RackConfig.tileHeight),
      anchor: Anchor.center,
      priority: 79,
    );
    world.add(transient);
    transient.add(
      observeGameEffect(MoveEffect.to(
        _drawAnimationTargetForSeat(toSeat),
        EffectController(duration: 0.28, curve: Curves.easeOutCubic),
      ), activityProbe, 'okey_game.dart:8'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 320));
    transient.removeFromParent();
  }

  Future<void> _animateDiscardToPlayer({
    required int fromSeat,
    required int toSeat,
    int? preferredRackSlot,
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

    // Hedefi dogrudan rackteki bos slota verelim; merkeze dusup sonra slota atlamasin.
    final end =
        (preferredRackSlot != null &&
            preferredRackSlot >= 0 &&
            preferredRackSlot < slotPositions.length)
        ? slotPositions[preferredRackSlot].clone()
        : _drawAnimationTargetForSeat(toSeat);

    _consumeDiscardTopVisualAfterDraw(fromSeat, expectedTileId: tileModel!.id);

    final transient = TileComponent(
      tile: tileModel!, // 🔥 zorunlu
      position: start,
    )..priority = 79;

    transient.isLocked = true;
    world.add(transient);

    final completer = Completer<void>();

    transient.add(
      observeGameEffect(MoveEffect.to(
        end,
        EffectController(duration: 0.28, curve: Curves.easeOutCubic),
      ), activityProbe, 'okey_game.dart:9'),
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
    _discardChanged(seat);
    _consumedDiscardTileBySeat.remove(seat);
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
      observeGameEffect(MoveEffect.to(
        slot.position.clone(),
        EffectController(duration: 0.28, curve: Curves.easeOutCubic),
      ), activityProbe, 'okey_game.dart:10'),
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
  bool _finishBaselineSeeded = false;
  DateTime _sessionStartedAt = DateTime.now();
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

  String? _finishIdFromTable(Map<String, dynamic> table) {
    final hasFinishData =
        table['last_winner_user_id'] != null &&
        table['last_final_slots'] != null &&
        table['last_finish_tile'] != null;
    if (!hasFinishData) return null;
    final finishAt = table['last_finish_at']?.toString() ?? '';
    if (finishAt.isEmpty) return null;
    final winnerId = table['last_winner_user_id'];
    final slots = List<Map<String, dynamic>>.from(
      table['last_final_slots'] ?? [],
    );
    final finishTile = Map<String, dynamic>.from(
      table['last_finish_tile'] ?? {},
    );
    final finishCore = _buildFinishCoreId(
      winnerId: winnerId,
      slots: slots,
      finishTile: finishTile,
    );
    return '$finishAt|$finishCore';
  }

  void _seedFinishBaselineIfNeeded(Map<String, dynamic> table) {
    if (_finishBaselineSeeded) return;
    final finishId = _finishIdFromTable(table);
    if (finishId != null && finishId.isNotEmpty) {
      _lastHandledFinishId = finishId;
      final sep = finishId.indexOf('|');
      if (sep != -1 && sep + 1 < finishId.length) {
        _lastHandledFinishCore = finishId.substring(sep + 1);
      }
    }
    _finishBaselineSeeded = true;
  }

  bool _maybeShowFinishFromTable(Map<String, dynamic> table) {
    if (!_finishBaselineSeeded) {
      _seedFinishBaselineIfNeeded(table);
      return false;
    }
    final status = table['status']?.toString();
    if (status == 'playing') {
      // tables retains the previous round's finish fields while the next round
      // is playing. Remember that receipt even when its original event was lost.
      final carriedFinish = _finishIdFromTable(table);
      if (carriedFinish != null) {
        _lastHandledFinishId = carriedFinish;
        final separator = carriedFinish.indexOf('|');
        if (separator >= 0) _lastHandledFinishCore = carriedFinish.substring(separator + 1);
      }
      return false;
    }
    final hasFinishData =
        table['last_winner_user_id'] != null &&
        table['last_final_slots'] != null &&
        table['last_finish_tile'] != null;
    if (!hasFinishData) return false;

    final finishAt = table['last_finish_at']?.toString() ?? '';
    if (finishAt.isEmpty) return false;
    final finishAtTime = _parseServerTime(table['last_finish_at']);
    final winnerId = table['last_winner_user_id'];
    final slots = List<Map<String, dynamic>>.from(
      table['last_final_slots'] ?? [],
    );
    final finishTile = Map<String, dynamic>.from(
      table['last_finish_tile'] ?? {},
    );
    final finishCore = _buildFinishCoreId(
      winnerId: winnerId,
      slots: slots,
      finishTile: finishTile,
    );
    final finishId = '$finishAt|$finishCore';
    if (finishAtTime != null &&
        finishAtTime.isBefore(
          _sessionStartedAt.subtract(const Duration(seconds: 1)),
        )) {
      _lastHandledFinishId = finishId;
      _lastHandledFinishCore = finishCore;
      return false;
    }
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
    _finishedRoundGuard = _round;
    _handStateEpoch++;
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

  Future<void> _handleTableUpdate(Map<String, dynamic> table) {
    final probe = activityProbe;
    if (probe == null) return _handleTableUpdateObservedBody(table);
    return probe.observeOperation(() => _handleTableUpdateObservedBody(table));
  }

  Future<void> _handleTableUpdateObservedBody(Map<String, dynamic> table) async {
    activityProbe?.event('tableUpdateCandidate');
    try {
      if (_staleTurnSnapshot(table)) return;
      if (_normalizedRoundFromTable(table) < _round) return;
      final status = table['status'] as String?;
      if (status == null) {
        return;
      }
      _dbg('TABLE_UPDATE', {
        'status': status,
        'round_count': table['round_count'],
        'current_turn': table['current_turn'],
        'game_started': _gameStarted,
      }, key: 'table_update');
      final handledFinish = _maybeShowFinishFromTable(table);
      if (handledFinish) {
        // Finish yakalandığında bu update turunda ek state churn yapma.
        // Aksi halde rakipte kısa süreli tekrar taş dizimi görülebiliyor.
        _cancelStartCountdown();
        _startCalled = false;
        _countdownRunning = false;
        _localCountdownStart = null;
        return;
      }

      if (status == 'playing' && !_gameStarted) {
        if (tileComponentMap.isEmpty) _initialDealInProgress = true;
        _gameStarted = true;
        _enteredPlayingAt = DateTime.now();
        _hideWaitingOverlay();
        if (!_stateSyncInFlight) {
          await _loadInitialState(forceHandSync: true);
        }
        return;
      }

      if (status != 'playing' && _gameStarted) {
        // A delayed event must not clear a live rack. Reconcile from the server
        // and return; only that snapshot may apply the reset.
        if (!_stateSyncInFlight) {
          await _loadInitialState(forceHandSync: false);
        }
        return;
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

        await _ensureGameStartIfReady(knownStatus: status);

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
        await _ensureGameStartIfReady(knownStatus: status);
        return;
      }

      // 🔥 TURN SYNC (sadece playing'de anlamlı)
      final previousTurnKey = _currentTurnKey();
      _applyTurnSnapshot(table);
      if (_currentTurnKey() != previousTurnKey) {
        // A turn event confirms the discard transaction committed. Read its top
        // now, even if the separate move/discard realtime event was lost.
        unawaited(_syncDiscardTopsFromServer());
      }

      if (table['deck'] != null && !_initialized) {
        _syncDeckFromTable(table['deck']);
        _initialized = true;
      }
      await _validateCriticalInvariants('table_update');
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
    world = GameActivityProbe.enabled ? ActivityObservedWorld() : World();
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

  Future<void> _syncDiscardTopsFromServer() {
    final probe = activityProbe;
    if (probe == null) return _syncDiscardTopsFromServerObservedBody();
    return probe.observeOperation(() => _syncDiscardTopsFromServerObservedBody());
  }

  Future<void> _syncDiscardTopsFromServerObservedBody() async {
    if (_initialDealInProgress) return;
    if (_discardSyncInFlight) {
      _discardSyncRequested = true;
      return;
    }
    _discardSyncInFlight = true;
    final syncEpoch = _handStateEpoch;
    final revisionsAtStart = Map<int, int>.from(_discardRevisionBySeat);
    if (!_gameStarted) {
      _clearTableVisualState();
      _discardSyncInFlight = false;
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('table_discard_tops')
          .select('seat_index,tile')
          .eq('table_id', tableId);
      if (!_lifecycleActive || !_gameStarted || syncEpoch != _handStateEpoch) return;

      final topsBySeat = <int, Map<String, dynamic>>{};
      for (final raw in (rows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final seat = row['seat_index'] as int?;
        final tileRaw = row['tile'];
        if (seat == null || tileRaw is! Map<String, dynamic>) continue;
        topsBySeat[seat] = tileRaw;
      }

      // A successful authoritative empty top must eventually clear its visual.
      // Preserve seats changed since this request, previews and animations.
      for (final seat in _discardTopTilesBySeat.keys.toList()) {
        if (topsBySeat.containsKey(seat) ||
            _discardRevision(seat) != (revisionsAtStart[seat] ?? 0) ||
            _discardAnimationInFlightSeats.contains(seat) ||
            _rackInteractionActive) continue;
        final hold = _discardSyncHoldUntilBySeat[seat];
        if (hold != null && hold.isAfter(DateTime.now())) continue;
        final previous = _discardTopTilesBySeat.remove(seat);
        previous?.removeFromParent();
        final slot = _discardSlotsByIndex[_slotIndexForAbsoluteSeat(seat)];
        if (identical(slot?.currentTile, previous)) slot?.currentTile = null;
        _discardStacksBySeat.remove(seat);
      }

      // Render/update current tops.
      final mySeat = _resolveMySeatIndex();
      for (final entry in topsBySeat.entries) {
        final seat = entry.key;
        // The source component is under the pointer until this drag ends.
        // A periodic snapshot must not put it back on the discard pile.
        if (_sourceDrawDragActive &&
            identical(_sourceDrawFromDiscardSlot,
                _discardSlotsByIndex[_slotIndexForAbsoluteSeat(seat)])) continue;
        if (_discardRevision(seat) != (revisionsAtStart[seat] ?? 0)) {
          continue;
        }
        final holdUntil = _discardSyncHoldUntilBySeat[seat];
        if (holdUntil != null && holdUntil.isAfter(DateTime.now())) {
          continue;
        }
        if (_discardAnimationInFlightSeats.contains(seat)) continue;
        final tileModel = _tileModelFromPayload(entry.value);
        if (tileModel == null) continue;
        // A stale top-row must never resurrect a tile already taken.
        if (_consumedDiscardTileBySeat[seat] == tileModel.id) continue;
        _consumedDiscardTileBySeat.remove(seat);
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
        final stack = _discardStacksBySeat.putIfAbsent(
          seat,
          () => <TileModel>[],
        );
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
    } finally {
      _discardSyncInFlight = false;
      if (_discardSyncRequested) {
        _discardSyncRequested = false;
        unawaited(_syncDiscardTopsFromServer());
      }
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
    if (hasDrawnThisTurn || _localDrawCommittedThisTurn()) return false;
    if (_effectiveHandCount() >= 15) return false;
    if (slot.currentTile == null) return false;
    final seat = _absoluteSeatForSlot(slot);
    final expected = _expectedDiscardSeatForCurrentTurn();
    if (seat == null || expected == null) return false;
    return seat == expected;
  }

  Future<void> _serverDraw({required String source, int? fromSeat}) async {
    if (_actionInFlight || _indicatorBonusInFlight) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    _actionInFlight = true;
    final drawEpoch = _handStateEpoch;
    final latency = GameLatencyTrace('draw');
    final drawRound = _round;
    final drawTurn = currentTurn;
    final drawTurnStartedAt = _turnStartedAt;
    _rackDrawArrivalStart = _pendingDrawVisualTile?.position.clone() ??
        (source == 'discard' && fromSeat != null
          ? _discardSlotsByIndex[_slotIndexForAbsoluteSeat(fromSeat)]?.position.clone()
          : closedPileComponent?.position.clone());
    bool currentDraw() => _lifecycleActive &&
        drawEpoch == _handStateEpoch && drawRound == _round &&
        drawTurn == currentTurn && (drawTurnStartedAt == null ||
          drawTurnStartedAt == _turnStartedAt);
    final prepared = source == 'closed' ? _preparedClosedDraw : null;
    _preparedClosedDraw = null;
    final pendingPreview = _pendingDrawVisualTile;
    if (prepared != null && pendingPreview != null) {
      unawaited(prepared.then((model) {
        if (model == null || !currentDraw() || !_actionInFlight ||
            !identical(_pendingDrawVisualTile, pendingPreview)) return;
        _revealPreparedDraw(model, pendingPreview);
        latency.mark('prepared_face_queued');
      }));
    }
    try {
      Future<dynamic> callDraw({int? seat}) async {
        final response = await Supabase.instance.client.rpc(
          'game_draw',
          params: {
            'p_table_id': tableId,
            'p_user_id': userId,
            'p_source': source,
            'p_from_seat': seat,
          },
        );
        latency.mark('rpc_response');
        return response;
      }

      final response = await confirmedDraw(
        mutation: callDraw(seat: fromSeat),
        previousIds: tileComponentMap.keys.toSet(),
        tableId: tableId,
        isCurrent: currentDraw,
        readHand: () async {
          final rows = await Supabase.instance.client.from('table_players')
              .select('hand').eq('table_id', tableId).eq('user_id', userId).limit(1);
          return rows.isNotEmpty && rows.first['hand'] is List
              ? List<dynamic>.from(rows.first['hand'] as List) : null;
        },
      );
      if (!currentDraw()) return;
      latency.mark('confirmation_received');
      if (response is Map && response['ok'] == false) {
        throw StateError('GAME_DRAW_REJECTED');
      }
      // The right closes on this player's first committed draw, not a discard.
      _hasDrawnFromSourceThisRound = true;
      // game_draw already returns the committed hand. Reveal it before any
      // additional network read; the closed-pile preview is not a real joker.
      var committedHand = committedDrawHand(response, tableId);
      if (committedHand != null) {
        _committedHandRevision++;
        _renderMyHand([
          <String, dynamic>{'user_id': userId, 'hand': committedHand},
        ], applyServerDiff: true);
      }
      // Compatibility with older RPC deployments which do not return a hand.
      if (committedHand == null) {
        try {
          final handRows = await Supabase.instance.client
              .from('table_players')
              .select('hand')
              .eq('table_id', tableId)
              .eq('user_id', userId)
              .limit(1);
          if (!currentDraw()) return;
          if (handRows is List && handRows.isNotEmpty) {
            final hand = handRows.first['hand'];
            if (hand is List && hand.length == 15) {
              committedHand = hand;
              _committedHandRevision++;
              _renderMyHand([
                <String, dynamic>{'user_id': userId, 'hand': hand},
              ], applyServerDiff: true);
            }
          }
        } catch (e) {
          debugPrint('FAST DRAW HAND SYNC ERROR: $e');
        }
      }
      _clearPendingDrawVisualTile();
      _hasDrawnFromSourceThisRound = true;
      latency.mark('hand_render_queued');
      _markDrawCommittedForCurrentTurn();
      // A committed hand is already authoritative. Do not keep input locked
      // behind a second full-table/users/discard round trip on the normal path.
      if (committedHand == null) {
        await _loadInitialState(forceHandSync: true);
      }
      _clearPendingDrawVisualTile();
      //_emitTileSfx();
    } catch (e) {
      debugPrint('GAME_DRAW RPC ERROR: $e');
      _pendingPreferredDrawSlot = null;
      if ('$e'.contains('NOT_YOUR_TURN')) {
        await _pollLiveTableState();
      }
      if ('$e'.contains('HAND_ALREADY_15')) {
        _markDrawCommittedForCurrentTurn();
      }
      _clearPendingDrawVisualTile();
      await _loadInitialState(forceHandSync: true);
    } finally {
      _rackDrawArrivalStart = null;
      _actionInFlight = false;
    }
  }

  @visibleForTesting
  static List<dynamic>? committedDrawHand(dynamic response, String tableId) {
    if (response is! Map || response['ok'] != true ||
        response['table_id'] != tableId) {
      return null;
    }
    final hand = response['hand'];
    if (hand is! List || hand.length != 15) return null;
    final ids = <String>{};
    for (final tile in hand) {
      if (tile is! Map || tile['id'] is! String ||
          (tile['id'] as String).isEmpty || !ids.add(tile['id'] as String)) {
        return null;
      }
    }
    return hand;
  }

  List<Map<String, dynamic>> _buildSlotsJson(Map<int, TileComponent> slotMap) {
    _rebuildOccupiedSlots();
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
    if (!finish && tile.isJoker && !tile.isFakeJoker) return false;
    if (_networkInFlight) return false;

    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;

    _networkInFlight = true;
    final latency = GameLatencyTrace('discard');
    tile.hideTileVisual = true;
    var discardConfirmed = false;

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

      discardConfirmed = true;
      latency.mark('rpc_confirmed');
      _committedHandRevision++;
      _removeTileFromRackState(tile);
      if (tile.isMounted) {
        tile.removeFromParent();
      }
      _emitTileSfx();
      _myHandCount = (_myHandCount - 1).clamp(0, 30);
      _clearDrawCommitForCurrentTurn();
      _pendingPreferredDrawSlot = null;
      // Discard success: only removed tile should change in my hand.
      // Keep hand untouched to prevent unintended slot moves.
      // Only the next turn is needed after our confirmed discard; the local
      // hand was updated above. Avoid reloading all players and discard visuals.
      await _pollLiveTableState(fresh: true);
      latency.mark('turn_refreshed');
      return true;
    } catch (e) {
      await _loadInitialState(forceHandSync: true);
      return false;
    } finally {
      _networkInFlight = false;
      if (!discardConfirmed) tile.hideTileVisual = false;
    }
  }

  Future<dynamic> _requestTimeoutMove(String userId) {
    if (userId != Supabase.instance.client.auth.currentUser?.id) {
      return Supabase.instance.client.rpc('game_timeout_move', params: {
        'p_table_id': tableId, 'p_user_id': userId,
      });
    }
      // Only our own rack can supply a physical slot preference.
      final slot = occupiedSlots.length == 15
          ? timeoutDiscardSlot(
              occupiedSlots: occupiedSlots.keys,
              protectedSlots: {
                for (final entry in occupiedSlots.entries)
                  if (entry.value.isJoker && !entry.value.isFakeJoker) entry.key,
              },
              columns: RackConfig.columns,
            )
          : null;
      final preferredTileId = slot == null ? null : occupiedSlots[slot]?.tile.id;
      return Supabase.instance.client.rpc(
        'okeyix_timeout_move_with_tile',
        params: {
          'p_table_id': tableId,
          'p_user_id': userId,
          'p_preferred_tile_id': preferredTileId,
        },
      );

  }

  Future<void> _serverTimeoutMove() async {
    if (_actionInFlight) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _actionInFlight = true;

    try {
      // Timeout discard/skip sonrası bu tur draw state'ini yerelde tutma.
      _clearDrawCommitForCurrentTurn();
      _pendingPreferredDrawSlot = null;

      await _requestTimeoutMove(userId);

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
      final normalizedLast = _normalizeTilePayload(
        Map<String, dynamic>.from(lastTile),
      );
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
      final idx = list.indexWhere(
        (t) => (t['id'] ?? '').toString() == targetId,
      );
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
      for (
        int nonJokerCount = 1;
        nonJokerCount <= colorUnique.length;
        nonJokerCount++
      ) {
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
      for (
        int nonJokerCount = 2;
        nonJokerCount <= sameColor.length;
        nonJokerCount++
      ) {
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
        return {'last_tile': candidateLast, 'slots': slots};
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

  // Source draws accept the continuous rack surface, including the gaps
  // between rows/slots. Keep ordinary rack rearrangement hit testing unchanged.
  @visibleForTesting
  int? sourceDrawDropSlot(Vector2 pos) {
    final nearest = getNearestSlotIndex(pos);
    if (nearest != null) return nearest;
    if (slotPositions.isEmpty) return null;
    var left = slotPositions.first.x;
    var right = left;
    var top = slotPositions.first.y;
    var bottom = top;
    for (final slot in slotPositions) {
      left = math.min(left, slot.x);
      right = math.max(right, slot.x);
      top = math.min(top, slot.y);
      bottom = math.max(bottom, slot.y);
    }
    if (pos.x < left - RackConfig.tileWidth / 2 ||
        pos.x > right + RackConfig.tileWidth / 2 ||
        pos.y < top - RackConfig.tileHeight / 2 ||
        pos.y > bottom + RackConfig.tileHeight / 2) {
      return null;
    }
    int? empty;
    var distance = double.infinity;
    for (var i = 0; i < slotPositions.length; i++) {
      if (isSlotOccupied(i)) continue;
      final candidate = slotPositions[i].distanceToSquared(pos);
      if (candidate < distance) {
        distance = candidate;
        empty = i;
      }
    }
    return empty;
  }

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
    if (!_allowTurnAction()) return;
    final now = DateTime.now();
    if (_lastDrawAttemptAt != null &&
        now.difference(_lastDrawAttemptAt!).inMilliseconds < 250) {
      return;
    }
    _lastDrawAttemptAt = now;
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return;
    }
    if (!_canDrawNow()) return;
    if (closedPile.length <= 1) return;
    _serverDraw(source: 'closed');
  }

  bool drawFromClosedPileByVoice() {
    if (!_allowTurnAction()) return false;
    if (!_canDrawNow()) return false;
    if (closedPile.length <= 1) return false;
    drawFromClosedPile();
    return true;
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
    _cancelHover();
    previewBox.isVisible = false;
  }

  void moveTileSmooth(PositionComponent tile, Vector2 target) {
    if (tile is TileComponent) {
      // One absolute rack motion per tile; queued relative effects can otherwise
      // resume after a preview reset and leave the tile between slot centers.
      tile.moveOnRack(target);
      return;
    }

    // 🔥 sadece mevcut move effect'i kaldır
    tile.children.whereType<MoveEffect>().toList().forEach(
      (e) => e.removeFromParent(),
    );

    tile.add(
      observeGameEffect(MoveEffect.to(
        target,
        EffectController(duration: 0.16, curve: Curves.easeOutBack),
      ), activityProbe, 'okey_game.dart:11'),
    );
  }

  int? _lastPreviewIndex;
  TileComponent? _groupDragAnchor;
  final List<TileComponent> _groupDragTiles = <TileComponent>[];
  final Map<TileComponent, int> _groupDragOriginalSlots =
      <TileComponent, int>{};
  int _groupDragAnchorOffset = 0;

  void _rebuildOccupiedSlots() {
    occupiedSlots.clear();
    for (final tile in tileComponentMap.values) {
      // A queued tile already owns its slot even before its first frame.
      if (tile.isRemoving || tile.isRemoved) continue;
      final idx = tile.currentSlotIndex;
      if (idx == null) continue;
      if (idx < 0 || idx >= slotPositions.length) continue;
      occupiedSlots[idx] = tile;
    }
  }

  bool _slotHasMountedTile(int index, {TileComponent? ignore}) {
    return _mountedTileAtSlot(index, ignore: ignore) != null;
  }

  TileComponent? _mountedTileAtSlot(int index, {TileComponent? ignore}) {
    for (final tile in tileComponentMap.values) {
      if (tile.isRemoving || tile.isRemoved) continue;
      if (ignore != null && identical(tile, ignore)) continue;
      if (tile.currentSlotIndex == index) return tile;
    }
    return null;
  }

  // Repair only invalid or conflicting assignments; never sort a healthy rack.
  // A finishing tile is intentionally detached and sent separately to the RPC.
  bool _repairRackSlotAssignments({TileComponent? exclude}) {
    if (_rackInteractionActive) return false;
    final owners = <int, TileComponent>{};
    final excludedSlot = exclude?.currentSlotIndex;
    bool available(int slot) => !owners.containsKey(slot) && slot != excludedSlot;
    final unplaced = <TileComponent>[];
    for (final tile in tileComponentMap.values) {
      if (identical(tile, exclude) || tile.isRemoving || tile.isRemoved) continue;
      final slot = tile.currentSlotIndex;
      if (slot != null && slot >= 0 && slot < slotPositions.length &&
          available(slot)) {
        owners[slot] = tile;
      } else {
        unplaced.add(tile);
      }
    }
    for (final tile in unplaced) {
      int? destination;
      for (final slot in [_lastKnownSlotByTileId[tile.id], tile.originalSlotIndex]) {
        if (slot != null && slot >= 0 && slot < slotPositions.length &&
            available(slot)) {
          destination = slot;
          break;
        }
      }
      if (destination == null) {
        for (var slot = 0; slot < slotPositions.length; slot++) {
          if (available(slot)) { destination = slot; break; }
        }
      }
      if (destination == null) return false;
      tile.stopRackMotion();
      tile.currentSlotIndex = destination;
      tile.currentTarget = slotPositions[destination].clone();
      tile.position = slotPositions[destination].clone();
      _lastKnownSlotByTileId[tile.id] = destination;
      owners[destination] = tile;
    }
    occupiedSlots..clear()..addAll(owners);
    return true;
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

  void _assignRackSlot(TileComponent tile, int slot) {
    occupiedSlots.removeWhere((_, occupant) => identical(occupant, tile));
    occupiedSlots[slot] = tile;
    tile.currentSlotIndex = slot;
    _lastKnownSlotByTileId[tile.id] = slot;
    moveTileSmooth(tile, slotPositions[slot]);
  }

  void insertIntoRow(int targetIndex, TileComponent tile, {bool playSound = true}) {
    _rebuildOccupiedSlots();
    occupiedSlots.removeWhere((_, occupant) => identical(occupant, tile));
    tile.currentSlotIndex = null;
    if (targetIndex < 0 || targetIndex >= slotPositions.length) {
      _restoreTileToOriginalSlot(tile);
      return;
    }
    final rowStart = targetIndex ~/ RackConfig.columns * RackConfig.columns;
    final rowEnd = math.min(rowStart + RackConfig.columns - 1, slotPositions.length - 1);

    if (!occupiedSlots.containsKey(targetIndex)) {
      _assignRackSlot(tile, targetIndex);
      if (playSound) _emitTileSfx();
      return;
    }

    // Preserve the existing right-first insertion order. A full right block
    // can also move left, regardless of where in the row the drop occurred.
    for (var empty = targetIndex + 1; empty <= rowEnd; empty++) {
      if (occupiedSlots.containsKey(empty)) continue;
      for (var slot = empty; slot > targetIndex; slot--) {
        final moving = occupiedSlots[slot - 1];
        if (moving != null) _assignRackSlot(moving, slot);
      }
      _assignRackSlot(tile, targetIndex);
      if (playSound) _emitTileSfx();
      return;
    }
    for (var empty = targetIndex - 1; empty >= rowStart; empty--) {
      if (occupiedSlots.containsKey(empty)) continue;
      for (var slot = empty; slot < targetIndex; slot++) {
        final moving = occupiedSlots[slot + 1];
        if (moving != null) _assignRackSlot(moving, slot);
      }
      _assignRackSlot(tile, targetIndex);
      if (playSound) _emitTileSfx();
      return;
    }

    // A drawn tile has no original slot. If this row is full, retain an
    // existing tile's original slot or put the new tile in a free rack slot.
    _restoreTileToOriginalSlot(tile);
  }
  bool isGroupDragAnchor(TileComponent tile) =>
      _groupDragAnchor != null && identical(_groupDragAnchor, tile);

  void clearGroupSelectionIfDifferent(TileComponent tile) {
    if (_groupDragAnchor != null && !identical(_groupDragAnchor, tile)) {
      _clearGroupDragVisuals();
    }
  }

  bool tryActivateGroupDrag(TileComponent anchor) {
    _clearGroupDragVisuals();
    _rebuildOccupiedSlots();
    final anchorSlot = anchor.currentSlotIndex ?? anchor.originalSlotIndex;
    if (anchorSlot == null) return false;

    final row = anchorSlot ~/ RackConfig.columns;
    final rowStart = row * RackConfig.columns;
    final rowEnd = rowStart + RackConfig.columns - 1;

    bool hasTileAt(int i) {
      if (i == anchorSlot) return true;
      return _mountedTileAtSlot(i, ignore: anchor) != null;
    }

    int left = anchorSlot;
    while (left - 1 >= rowStart && hasTileAt(left - 1)) {
      left--;
    }
    int right = anchorSlot;
    while (right + 1 <= rowEnd && hasTileAt(right + 1)) {
      right++;
    }

    final tiles = <TileComponent>[];
    for (int i = left; i <= right; i++) {
      final t = i == anchorSlot
          ? anchor
          : _mountedTileAtSlot(i, ignore: anchor);
      if (t != null) tiles.add(t);
    }
    if (tiles.length < 2) return false;

    int slotOf(TileComponent t) =>
        t.currentSlotIndex ?? t.originalSlotIndex ?? -1;

    tiles.sort((a, b) => slotOf(a).compareTo(slotOf(b)));
    _groupDragTiles
      ..clear()
      ..addAll(tiles);
    _groupDragAnchor = anchor;
    _groupDragAnchorOffset = anchorSlot - left;
    for (final t in _groupDragTiles) {
      final slot = t.currentSlotIndex ?? t.originalSlotIndex;
      if (slot != null) {
        _groupDragOriginalSlots[t] = slot;
      }
    }
    return true;
  }

  void startActiveGroupDrag(TileComponent anchor) {
    if (!isGroupDragAnchor(anchor)) return;
    _rebuildOccupiedSlots();
    final anchorSlot = _groupDragOriginalSlots[anchor];
    for (final t in _groupDragTiles) {
      t.stopRackMotion();
      final idx = t.currentSlotIndex;
      if (idx != null) {
        occupiedSlots.remove(idx);
      }
      t.currentSlotIndex = null;
      t.originalSlotIndex = _groupDragOriginalSlots[t];
      t.originalPosition = t.position.clone();
    }

    for (final tile in _groupDragTiles) {
      showTileAboveAvatars(tile);
    }
    // Visual feedback: when group mode activates, lift whole group to anchor level.
    if (anchorSlot != null) {
      final anchorBasePos = slotPositions[anchorSlot];
      for (final t in _groupDragTiles) {
        if (identical(t, anchor)) continue;
        final slot = _groupDragOriginalSlots[t];
        if (slot == null) continue;
        final slotBasePos = slotPositions[slot];
        final dx = slotBasePos.x - anchorBasePos.x;
        t.position = Vector2(anchor.position.x + dx, anchor.position.y);
      }
    }
  }

  void updateActiveGroupDrag(TileComponent anchor, Vector2 delta) {
    if (!isGroupDragAnchor(anchor)) return;
    for (final t in _groupDragTiles) {
      t.position += delta;
    }
    notifyDraggedTileMoved();
  }

  void endActiveGroupDrag(TileComponent anchor) {
    if (!isGroupDragAnchor(anchor)) return;

    final targetIndex = getNearestSlotIndex(anchor.position);
    if (targetIndex == null || _groupDragTiles.isEmpty) {
      _restoreGroupDragToOriginal();
      _clearGroupDragVisuals();
      return;
    }

    final groupSize = _groupDragTiles.length;
    final row = targetIndex ~/ RackConfig.columns;
    final rowStart = row * RackConfig.columns;
    final rowEnd = rowStart + RackConfig.columns - 1;

    final startIndex = targetIndex - _groupDragAnchorOffset;
    final endIndex = startIndex + groupSize - 1;
    if (startIndex < rowStart || endIndex > rowEnd) {
      _restoreGroupDragToOriginal();
      _clearGroupDragVisuals();
      return;
    }

    _rebuildOccupiedSlots();
    for (int i = startIndex; i <= endIndex; i++) {
      if (_mountedTileAtSlot(i) != null || occupiedSlots.containsKey(i)) {
        _restoreGroupDragToOriginal();
        _clearGroupDragVisuals();
        return;
      }
    }

    for (int i = 0; i < _groupDragTiles.length; i++) {
      final tile = _groupDragTiles[i];
      final slot = startIndex + i;
      occupiedSlots[slot] = tile;
      tile.currentSlotIndex = slot;
      tile.originalSlotIndex = slot;
      moveTileSmooth(tile, slotPositions[slot]);
    }
    _clearGroupDragVisuals();
  }

  void _restoreGroupDragToOriginal() {
    for (final t in _groupDragTiles) {
      final slot = _groupDragOriginalSlots[t];
      if (slot == null) continue;
      occupiedSlots[slot] = t;
      t.currentSlotIndex = slot;
      t.originalSlotIndex = slot;
      moveTileSmooth(t, slotPositions[slot]);
    }
  }

  void _clearGroupDragVisuals() {
    for (final tile in _groupDragTiles) {
      hideTileAboveAvatars(tile);
    }
    _groupDragTiles.clear();
    _groupDragOriginalSlots.clear();
    _groupDragAnchor = null;
    _groupDragAnchorOffset = 0;
  }

  void cancelActiveGroupDragSelection() {
    _clearGroupDragVisuals();
  }

  void restoreRackTile(TileComponent tile) {
    _rebuildOccupiedSlots();
    _restoreTileToOriginalSlot(tile);
  }

  void _restoreTileToOriginalSlot(TileComponent tile) {
    tile.stopRackMotion();
    occupiedSlots.removeWhere((_, occupant) => identical(occupant, tile));
    int? destination;
    for (final slot in [tile.originalSlotIndex, tile.currentSlotIndex]) {
      if (slot != null && slot >= 0 && slot < slotPositions.length &&
          !occupiedSlots.containsKey(slot)) {
        destination = slot;
        break;
      }
    }
    destination ??= _findFirstEmptySlot();
    if (destination < 0) return;
    tile.currentSlotIndex = destination;
    occupiedSlots[destination] = tile;
    _lastKnownSlotByTileId[tile.id] = destination;
    moveTileSmooth(tile, slotPositions[destination]);
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
    _lastPreviewIndex = null;
    if (!isTempShiftActive) return;

    for (final entry in occupiedSlots.entries) {
      final tile = entry.value;
      if (tile.isLocked) continue;
      moveTileSmooth(tile, slotPositions[entry.key]);
    }

    isTempShiftActive = false;
    tempShiftIndex = null;
  }

  Future<bool> discardTile(TileComponent tile) async {
    if (tile.isJoker && !tile.isFakeJoker) return false;
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return false;
    }
    if (_actionInFlight) return false;
    if (_effectiveHandCount() != 15) return false;
    final success = await _serverDiscard(tile);
    return success;
  }

  Future<bool> finishWithTile(TileComponent tile) async {
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return false;
    }

    if (_actionInFlight) return false;

    if (_effectiveHandCount() != 15) return false;

    return _tryFinish(tile); // 🔥 BURASI DEĞİŞTİ
  }

  Future<bool> _tryFinish(TileComponent tile) async {
    _actionInFlight = true;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _actionInFlight = false;
      return false;
    }

    final slots = _prepareFinishSlots(tile);
    if (slots == null) {
      _actionInFlight = false;
      return false;
    }
    final lastTilePayload = tile.tile.toJson();

    try {
      final res = await Supabase.instance.client.rpc(
        'game_finish',
        params: {
          'p_table_id': tableId,
          'p_user_id': userId,
          'p_slots': slots,
          'p_last_tile': lastTilePayload,
        },
      );

      if (res != null && res['ok'] == true) {
        // Show finish immediately on client; do not wait for table status roundtrip.
        _finishShown = true;
        _gameStarted = false;
        _finishedRoundGuard = _round;
        _handStateEpoch++;
        _cancelStartCountdown();
        final winAmount = (res['win_amount'] as int?) ?? 0;
        final isOkeyFinish = res['is_okey'] == true;
        final isDoubleFinish = res['is_double'] == true;
        final winnerName = (res['winner_name']?.toString().isNotEmpty ?? false)
            ? res['winner_name'].toString()
            : getPlayerName(userId);
        final slotPayload = List<Map<String, dynamic>>.from(slots);
        final finishTile = Map<String, dynamic>.from(lastTilePayload);
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
        final errCode = res is Map ? (res['error_code']?.toString() ?? '') : '';
        final invalidTileIds = _extractInvalidTileIds(res);

        _highlightInvalidFinishTiles(invalidTileIds, fallback: tile);
        if (errCode == 'INVALID_FINISH') {
          AppMsg.show('Geçersiz bitiş');
        } else {
          AppMsg.show('El geçersiz');
        }
        return false;
      }
    } catch (e) {
      print(e);
      String msg = 'Bitirme başarısız';

      final err = e.toString();

      if (err.contains('INVALID_FINISH')) {
        msg = 'Geçersiz bitiş';
        _highlightInvalidFinishTiles(const [], fallback: tile);
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

  List<String> _extractInvalidTileIds(dynamic rpcRes) {
    if (rpcRes is! Map) return const [];
    final raw = rpcRes['invalid_tile_ids'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  void _highlightInvalidFinishTiles(
    List<String> tileIds, {
    TileComponent? fallback,
  }) {
    if (tileIds.isEmpty) {
      fallback?.playInvalidFinishHighlight();
      return;
    }
    final seen = <String>{};
    for (final id in tileIds) {
      if (!seen.add(id)) continue;
      final tile = tileComponentMap[id];
      if (tile == null || !tile.isMounted) continue;
      tile.playInvalidFinishHighlight();
    }
  }

  void placeDrawnTileIntoRack(TileComponent tile) {
    tile.removeFromParent();
  }

  void drawFromClosedPileDrag(Vector2 startPosition) {
    if (!_allowTurnAction()) return;
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return;
    }
    startSourceDrawDrag(startPosition: startPosition);
  }

  void takeFromDiscard() {
    if (!_allowTurnAction()) return;
    final expectedSeat = _expectedDiscardSeatForCurrentTurn();
    if (expectedSeat == null) return;
    final slotIndex = _slotIndexForAbsoluteSeat(expectedSeat);
    final slot = _discardSlotsByIndex[slotIndex];
    if (slot == null || !_canTakeFromDiscardSlot(slot)) return;
    _serverDraw(source: 'discard', fromSeat: expectedSeat);
  }

  bool takeFromDiscardByVoice() {
    if (!_allowTurnAction()) return false;
    if (!_canDrawNow()) return false;
    final expectedSeat = _expectedDiscardSeatForCurrentTurn();
    if (expectedSeat == null) return false;
    final slotIndex = _slotIndexForAbsoluteSeat(expectedSeat);
    final slot = _discardSlotsByIndex[slotIndex];
    if (slot == null || !_canTakeFromDiscardSlot(slot)) return false;
    takeFromDiscard();
    return true;
  }

  TileComponent? findDiscardCandidateForVoice({
    required TileColor color,
    required int value,
  }) {
    if (occupiedSlots.isEmpty) return null;
    final entries = occupiedSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      final tile = entry.value;
      if (!tile.isMounted) continue;
      if (tile.isJoker || tile.isFakeJoker) continue;
      if (tile.color == color && tile.value == value) {
        return tile;
      }
    }
    return null;
  }

  bool canDiscardByVoice() {
    if (_initialDealInProgress) return false;
    if (!_isMyTurn()) return false;
    if (_actionInFlight || _uiLocked) return false;
    return hasDrawnThisTurn || _effectiveHandCount() == 15;
  }

  Future<bool> discardTileByVoice({
    required TileColor color,
    required int value,
  }) async {
    if (!canDiscardByVoice()) return false;
    final tile = findDiscardCandidateForVoice(color: color, value: value);
    if (tile == null) return false;
    await autoDiscard(tile);
    return true;
  }

  Future<bool> finishGameByVoice() async {
    if (!_isMyTurn()) {
      _pollLiveTableState();
      return false;
    }
    if (_actionInFlight) return false;
    if (_effectiveHandCount() != 15) return false;

    final handEntries = occupiedSlots.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (handEntries.length != 15) return false;

    final hand = handEntries
        .map(
          (e) => <String, dynamic>{
            'id': e.value.tile.id,
            'value': e.value.tile.value,
            'color': tileColorToString(e.value.tile.color),
            'is_joker': e.value.tile.isJoker,
            'is_fake_joker': e.value.tile.isFakeJoker,
          },
        )
        .toList(growable: false);

    final finishPlan = _buildBotFinishPlan(hand);
    if (finishPlan == null) return false;

    final slots = List<Map<String, dynamic>>.from(finishPlan['slots'] as List);
    final lastTile = Map<String, dynamic>.from(finishPlan['last_tile'] as Map);
    if (!_isServerValidSlotsPayload(slots)) return false;

    _actionInFlight = true;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _actionInFlight = false;
      return false;
    }

    try {
      _dbg('FINISH_ATTEMPT', {
        'source': 'voice',
        'user_id': userId,
        'turn': currentTurn,
        'turn_seconds': _turnSeconds,
        'hand_count': _myHandCount,
        'slots': slots,
        'last_tile': lastTile,
      });
      final res = await Supabase.instance.client.rpc(
        'game_finish',
        params: {
          'p_table_id': tableId,
          'p_user_id': userId,
          'p_slots': slots,
          'p_last_tile': lastTile,
        },
      );

      if (res != null && res['ok'] == true) {
        _finishShown = true;
        _gameStarted = false;
        _finishedRoundGuard = _round;
        _handStateEpoch++;
        _cancelStartCountdown();
        final winAmount = (res['win_amount'] as int?) ?? 0;
        final isOkeyFinish = res['is_okey'] == true;
        final isDoubleFinish = res['is_double'] == true;
        final winnerName = (res['winner_name']?.toString().isNotEmpty ?? false)
            ? res['winner_name'].toString()
            : getPlayerName(userId);
        _lastHandledFinishCore = _buildFinishCoreId(
          winnerId: userId,
          slots: slots,
          finishTile: lastTile,
        );
        _lastLocalFinishAt = DateTime.now();
        _clearRenderedHand();
        _clearTableVisualState();
        showFinishFromGame(
          slots,
          lastTile,
          winnerName,
          true,
          false,
          winAmount,
          isOkeyFinish,
          isDoubleFinish,
        );
        return true;
      }
      _dbg('FINISH_REJECTED', {
        'source': 'voice',
        'user_id': userId,
        'error_code': res is Map ? (res['error_code']?.toString() ?? '') : '',
        'invalid_tile_ids': _extractInvalidTileIds(res),
        'slots': slots,
        'last_tile': lastTile,
        'rpc_response': res,
      });
      return false;
    } catch (e) {
      _dbg('FINISH_EXCEPTION', {
        'source': 'voice',
        'user_id': userId,
        'error': '$e',
        'slots': slots,
        'last_tile': lastTile,
      });
      return false;
    } finally {
      _actionInFlight = false;
    }
  }

  void takeFromDiscardDrag(DiscardSlotComponent slot, Vector2 startPosition) {
    startSourceDrawDrag(startPosition: startPosition, fromDiscardSlot: slot);
  }

  void takeFromDiscardTap(DiscardSlotComponent slot) {
    if (!_allowTurnAction()) return;
    final now = DateTime.now();
    if (_lastDrawAttemptAt != null &&
        now.difference(_lastDrawAttemptAt!).inMilliseconds < 250) {
      return;
    }
    _lastDrawAttemptAt = now;
    if (!_canDrawNow()) return;
    if (!_canTakeFromDiscardSlot(slot)) {
      _pollLiveTableState();
      return;
    }
    final fromSeat = _absoluteSeatForSlot(slot);
    if (fromSeat == null) return;

    // Keep drag-selected target slot if it already exists; otherwise fallback.
    if (_pendingPreferredDrawSlot == null) {
      final preferredRackSlot = _findFirstEmptySlot();
      if (preferredRackSlot != -1) {
        _pendingPreferredDrawSlot = preferredRackSlot;
      }
    }
    _holdDiscardSeatSync(fromSeat);
    _consumeDiscardTopVisualAfterDraw(fromSeat);

    _serverDraw(source: 'discard', fromSeat: fromSeat);
  }

  void startSourceDrawDrag({
    required Vector2 startPosition,
    DiscardSlotComponent? fromDiscardSlot,
  }) {
    if (_sourceDrawDragActive) return;
    if (!_allowTurnAction()) return;
    if (_effectiveHandCount() >= 15) return;
    if (_actionInFlight) return;
    if (fromDiscardSlot == null && !_isMyTurn()) {
      _pollLiveTableState();
      return;
    }
    if (fromDiscardSlot == null &&
        (hasDrawnThisTurn || _localDrawCommittedThisTurn())) {
      return;
    }
    if (fromDiscardSlot != null && !_canTakeFromDiscardSlot(fromDiscardSlot)) {
      return;
    }
    _sourceDrawDragActive = true;
    _sourceDrawFromDiscardSlot = fromDiscardSlot;
    _preparedDrawGeneration++;
    _preparedClosedDraw = fromDiscardSlot == null ? _prepareClosedDraw() : null;
    // Preparation is read-only; a drag must never consume a tile.
    // Hide the source tile while its draggable copy is under the finger.
    _dragHiddenDiscardTile = fromDiscardSlot?.currentTile;
    _dragRevealedDiscardTile?.removeFromParent();
    _dragRevealedDiscardTile = null;
    if (fromDiscardSlot != null && _dragHiddenDiscardTile != null) {
      final seat = _absoluteSeatForSlot(fromDiscardSlot);
      final stack = seat == null ? null : _discardStacksBySeat[seat];
      if (stack != null && stack.length >= 2) {
        final underneath = stack[stack.length - 2];
        _dragRevealedDiscardTile =
            TileComponent(
                tile: underneath,
                position: fromDiscardSlot.position.clone(),
              )
              ..priority = 50
              ..isLocked = true;
        world.add(_dragRevealedDiscardTile!);
      } else if (seat != null) {
        // Local stack may be incomplete; recover the underlying discard.
        unawaited(
          _showUnderlyingDiscardDuringDrag(
            seat,
            _dragHiddenDiscardTile!.tile.id,
          ).catchError((Object _) {}),
        );
      }
      // Keep the already loaded face: replacing it with a newly loaded copy
      // can leave the drag overlay temporarily without the selected face.
    }
    _sourceDrawDragPosition = startPosition.clone();
    if (activeDraggedTile != null) hideTileAboveAvatars(activeDraggedTile!);
    activeDraggedTile?.removeFromParent();
    activeDraggedTile = _buildSourceDragTile(
      startPosition: _sourceDrawDragPosition!,
      fromDiscardSlot: fromDiscardSlot,
    );
    if (activeDraggedTile != null) {
      activeDraggedTile!.isLocked = true;
      activeDraggedTile!.priority = 130;
      if (!identical(activeDraggedTile!.parent, world)) {
        world.add(activeDraggedTile!);
      }
      showTileAboveAvatars(activeDraggedTile!);
    }
    updatePreview(_sourceDrawDragPosition!);
  }

  DateTime? _lastNotYourTurnNotice;

  bool _allowTurnAction() {
    if (_initialDealInProgress) return false;
    if (isMyTurnForLocalUser) return true;
    final now = DateTime.now();
    if (_lastNotYourTurnNotice == null ||
        now.difference(_lastNotYourTurnNotice!) >= const Duration(seconds: 2)) {
      _lastNotYourTurnNotice = now;
      AppMsg.show('Oyun sırası sende değil');
    }
    return false;
  }

  void updateSourceDrawDrag(Vector2 localDelta) {
    if (!_sourceDrawDragActive || _sourceDrawDragPosition == null) return;
    final zoom = cameraComponent.viewfinder.zoom;
    _sourceDrawDragPosition = _sourceDrawDragPosition! + (localDelta / zoom);
    if (activeDraggedTile != null) {
      activeDraggedTile!.position = _sourceDrawDragPosition!.clone();
      notifyDraggedTileMoved();
    }
    updatePreview(_sourceDrawDragPosition!);
  }

  Future<void> _showUnderlyingDiscardDuringDrag(int seat, String topId) async {
    final epoch = _handStateEpoch;
    final revision = _discardRevision(seat);
    final rows = await Supabase.instance.client
        .from('table_discards')
        .select('tile')
        .eq('table_id', tableId)
        .eq('seat_index', seat)
        .isFilter('drawn_at', null)
        .order('created_at', ascending: false)
        .limit(8);
    if (!_lifecycleActive || epoch != _handStateEpoch ||
        revision != _discardRevision(seat) || !_sourceDrawDragActive ||
        _dragHiddenDiscardTile?.tile.id != topId ||
        _dragRevealedDiscardTile != null ||
        rows is! List)
      return;
    for (final raw in rows) {
      if (raw is! Map || raw['tile'] is! Map) continue;
      final payload = Map<String, dynamic>.from(raw['tile'] as Map);
      if (payload['id']?.toString() == topId) continue;
      final model = _tileModelFromPayload(payload);
      final slot = _sourceDrawFromDiscardSlot;
      if (model == null || slot == null) return;
      _dragRevealedDiscardTile =
          TileComponent(tile: model, position: slot.position.clone())
            ..priority = 50
            ..isLocked = true;
      world.add(_dragRevealedDiscardTile!);
      return;
    }
  }

  void _restoreDiscardAfterCancelledDrag() {
    _dragRevealedDiscardTile?.removeFromParent();
    _dragRevealedDiscardTile = null;
    final original = _dragHiddenDiscardTile;
    _dragHiddenDiscardTile = null;
    if (original != null) {
      final sourceSlot = _discardSlotsByIndex.values
          .where((slot) => identical(slot.currentTile, original)).firstOrNull;
      if (sourceSlot != null) {
        original.position = sourceSlot.position.clone();
        original.priority = 50;
        original.isLocked = true;
      }
      final epoch = _handStateEpoch;
      final round = _round;
      final sourceWorld = world;
      final sourceTable = tableId;
      final turnKey = _currentTurnKey();
      final id = original.tile.id;
      final seat = _discardTopTilesBySeat.entries
          .where((entry) => identical(entry.value, original))
          .map((entry) => entry.key).firstOrNull;
      if (seat == null) return;
      final revision = _discardRevision(seat);
      // Flame component removals are deferred to the next game tick.
      Future<void>.delayed(const Duration(milliseconds: 40), () {
        if (!_lifecycleActive || !_gameStarted || isFinishOpen ||
            sourceTable != tableId || !identical(world, sourceWorld) ||
            epoch != _handStateEpoch || round != _round ||
            turnKey != _currentTurnKey() || original.isRemoving ||
            revision != _discardRevision(seat) ||
            !identical(_discardTopTilesBySeat[seat], original) ||
            original.tile.id != id || _consumedDiscardTileBySeat[seat] == id ||
            tileComponentMap.containsKey(id) || _sourceDrawDragActive) return;
        if (!original.isMounted) world.add(original);
      });
    }
  }

  void endSourceDrawDrag() {
    if (!_sourceDrawDragActive) {
      if (activeDraggedTile != null) hideTileAboveAvatars(activeDraggedTile!);
      activeDraggedTile?.removeFromParent();
      activeDraggedTile = null;
      clearPreview();
      clearTemporaryShift();
      _restoreDiscardAfterCancelledDrag();
      return;
    }

    final pos = _sourceDrawDragPosition;
    final targetSlot = pos == null ? null : sourceDrawDropSlot(pos);
    final fromDiscardSlot = _sourceDrawFromDiscardSlot;
    _sourceDrawDragActive = false;
    _sourceDrawFromDiscardSlot = null;
    _sourceDrawDragPosition = null;
    final dragged = activeDraggedTile;
    if (dragged != null) hideTileAboveAvatars(dragged);
    activeDraggedTile = null;
    clearPreview();
    clearTemporaryShift();

    // Dropping outside the rack cancels the operation, including the server draw.
    if (targetSlot == null) {
      _preparedDrawGeneration++;
      _preparedClosedDraw = null;
      if (!identical(dragged, _dragHiddenDiscardTile)) {
        dragged?.removeFromParent();
      }
      _pendingPreferredDrawSlot = null;
      _restoreDiscardAfterCancelledDrag();
      return;
    }

    if (fromDiscardSlot != null) {
      if (!_canTakeFromDiscardSlot(fromDiscardSlot)) {
        if (!identical(dragged, _dragHiddenDiscardTile)) {
          dragged?.removeFromParent();
        }
        _pendingPreferredDrawSlot = null;
        _restoreDiscardAfterCancelledDrag();
        return;
      }
      _dragHiddenDiscardTile = null;
      _dragRevealedDiscardTile?.removeFromParent();
      _dragRevealedDiscardTile = null;
      _pendingPreferredDrawSlot = targetSlot;
      if (dragged != null) {
        _showPendingDrawVisualTile(dragged, preferredSlot: targetSlot);
      }
      takeFromDiscardTap(fromDiscardSlot);
    } else {
      if (!_canDrawNow() || closedPile.length <= 1) {
        dragged?.removeFromParent();
        _pendingPreferredDrawSlot = null;
        return;
      }
      _pendingPreferredDrawSlot = targetSlot;
      if (dragged != null) {
        _showPendingDrawVisualTile(dragged, preferredSlot: targetSlot);
      }
      drawFromClosedPile();
    }
  }

  void _showPendingDrawVisualTile(TileComponent tile, {int? preferredSlot}) {
    _clearPendingDrawVisualTile();
    if (tile.id == '__closed_draw_preview__') {
      tile.showAwaitingDrawConfirmation();
    }
    var targetSlot = preferredSlot;
    if (targetSlot == null ||
        targetSlot < 0 ||
        targetSlot >= slotPositions.length) {
      targetSlot = _findFirstEmptySlot();
    }
    if (targetSlot == -1) {
      tile.removeFromParent();
      return;
    }
    tile.isLocked = true;
    tile.priority = 125;
    tile.children.whereType<MoveEffect>().toList().forEach(
      (e) => e.removeFromParent(),
    );
    tile.moveOnRack(slotPositions[targetSlot], allowLocked: true);
    _pendingDrawVisualTile = tile;
  }

  Future<TileModel?> _prepareClosedDraw() async {
    final generation = _preparedDrawGeneration;
    final epoch = _handStateEpoch;
    final round = _round;
    final turnKey = _currentTurnKey();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      final response = await Supabase.instance.client.rpc(
        'okeyix_prepare_closed_draw', params: {'p_table_id': tableId},
      ).timeout(const Duration(seconds: 3));
      if (!_lifecycleActive || epoch != _handStateEpoch || round != _round ||
          turnKey != _currentTurnKey() || generation != _preparedDrawGeneration ||
          response is! Map || response['table_id'] != tableId ||
          response['user_id'] != uid ||
          _normalizedRoundFromTable(Map<String, dynamic>.from(response)) != round ||
          response['tile'] is! Map) return null;
      final stamp = _parseServerTime(response['turn_started_at']);
      if (_lastServerTurnAt != null && stamp != _lastServerTurnAt) return null;
      return _tileModelFromPayload(Map<String, dynamic>.from(response['tile'] as Map));
    } catch (_) {
      // Older servers and failed preparation retain the normal draw path.
      return null;
    }
  }

  void _revealPreparedDraw(TileModel model, TileComponent preview) {
    final start = preview.position.clone();
    preview.hideTileVisual = true;
    preview.removeFromParent();
    final face = TileComponent(tile: model, position: start)
      ..isLocked = true
      ..priority = 125;
    world.add(face);
    _pendingDrawVisualTile = face;
    final slot = _pendingPreferredDrawSlot;
    if (slot != null && slot >= 0 && slot < slotPositions.length) {
      face.moveOnRack(slotPositions[slot], allowLocked: true);
    }
    // This is still a preview, not a member of the authoritative rack maps.
  }

  @visibleForTesting
  Future<void> debugPrepareClosedDraw() async {
    _preparedDrawGeneration++;
    _preparedClosedDraw = _prepareClosedDraw();
    await _preparedClosedDraw;
  }

  @visibleForTesting
  TileComponent? get debugPendingDraw => _pendingDrawVisualTile;

  void _clearPendingDrawVisualTile() {
    _pendingDrawVisualTile?.hideTileVisual = true;
    _pendingDrawVisualTile?.removeFromParent();
    _pendingDrawVisualTile = null;
  }

  @visibleForTesting
  void debugShowPendingDraw(TileComponent tile, {int? preferredSlot}) =>
      _showPendingDrawVisualTile(tile, preferredSlot: preferredSlot);

  @visibleForTesting
  Future<int> debugClaimIndicatorReward() => _claimIndicatorBonusFromPot();

  @visibleForTesting
  void debugSyncVisualHand(List<dynamic> hand, {bool initial = false}) {
    _lastStartDealSfxRound = _round;
    if (initial) {
      _renderHand(hand);
    } else {
      _syncHandIncremental(hand);
    }
  }

  @visibleForTesting
  void debugClearPendingVisual(TileComponent tile) {
    _pendingDrawVisualTile = tile;
    _clearPendingDrawVisualTile();
  }

  @visibleForTesting
  void debugRestoreDiscard(TileComponent tile, {bool invalidate = false}) {
    _gameStarted = true;
    _discardTopTilesBySeat[0] = tile;
    _dragHiddenDiscardTile = tile;
    _restoreDiscardAfterCancelledDrag();
    if (invalidate) _handStateEpoch++;
  }

  @visibleForTesting
  void debugSyncIndicator(List<dynamic> deck) => _syncDeckFromTable(deck);

  @visibleForTesting
  void debugPrepareLatencyState(int count) {
    _gameStarted = true;
    _round = 1;
    _mySeatIndexAbs = 0;
    currentTurn = 0;
    _myHandCount = count;
    _maxPlayers = 2;
  }

  @visibleForTesting
  Future<void> debugValidateRack() => _validateCriticalInvariants('test');

  @visibleForTesting
  void debugApplyOwnHand(List<dynamic> hand, {bool hardReset = false}) {
    _renderMyHand([
      {'user_id': Supabase.instance.client.auth.currentUser!.id, 'hand': hand},
    ], hardReset: hardReset);
  }

  @visibleForTesting
  Future<void> debugDrawCommittedHand({int? preferredSlot, String source = 'deck', int? fromSeat}) {
    _pendingPreferredDrawSlot = preferredSlot;
    return _serverDraw(source: source, fromSeat: fromSeat);
  }

  List<Map<String, dynamic>>? _prepareFinishSlots(TileComponent finishingTile) {
    if (!_repairRackSlotAssignments(exclude: finishingTile)) return null;
    // Keep the last tile separate even if a caller has not detached it yet.
    return _buildSlotsJson(Map<int, TileComponent>.from(occupiedSlots));
  }

  @visibleForTesting
  List<Map<String, dynamic>>? debugFinishSlots(TileComponent finishingTile) =>
      _prepareFinishSlots(finishingTile);

  @visibleForTesting
  bool get debugActionInFlight => _actionInFlight;

  @visibleForTesting
  Future<bool> debugDiscardCommittedTile(TileComponent tile) => _serverDiscard(tile);

  @visibleForTesting
  void debugSeedDiscard(int seat, TileComponent tile,
      {bool slotOnly = false, TileModel? underneath}) {
    final index = _slotIndexForAbsoluteSeat(seat);
    final slot = DiscardSlotComponent(playerIndex: index, position: tile.position.clone());
    _discardSlotsByIndex[index] = slot;
    slot.currentTile = tile;
    if (slotOnly) {
      _discardTopTilesBySeat.remove(seat);
    } else {
      _discardTopTilesBySeat[seat] = tile;
    }
    _discardStacksBySeat[seat] = [if (underneath != null) underneath, tile.tile];
  }

  @visibleForTesting
  DiscardSlotComponent? debugDiscardSlot(int seat) =>
      _discardSlotsByIndex[_slotIndexForAbsoluteSeat(seat)];

  @visibleForTesting
  Future<void> debugAnimateDiscardPickup(int fromSeat, int toSeat, Map<String, dynamic> tile) =>
      _animateDiscardToPlayer(fromSeat: fromSeat, toSeat: toSeat, tileData: tile);

  @visibleForTesting
  TileComponent? debugDiscardTop(int seat) => _discardTopTilesBySeat[seat] ??
      _discardSlotsByIndex[_slotIndexForAbsoluteSeat(seat)]?.currentTile;

  @visibleForTesting
  Future<void> debugSyncDiscardTops() => _syncDiscardTopsFromServer();

  @visibleForTesting
  Future<void> debugPollTurn() => _pollLiveTableState();

  @visibleForTesting
  void debugApplyTurn(Map<String, dynamic> table) => _applyTurnSnapshot(table);

  @visibleForTesting
  DateTime? get debugTurnStartedAt => _turnStartedAt;

  @visibleForTesting
  Future<void> debugLoadHand() => _loadInitialState(forceHandSync: true);

  @visibleForTesting
  Future<void> debugCheckHand() => _checkAuthoritativeHandIntegrity();

  @visibleForTesting
  bool get debugInitialDealInProgress => _initialDealInProgress;

  @visibleForTesting
  Future<void> debugReceiveTable(Map<String, dynamic> table) => _handleTableUpdate(table);

  @visibleForTesting
  void debugHoldDiscard(int seat) => _holdDiscardSeatSync(seat);

  TileComponent? _buildSourceDragTile({
    required Vector2 startPosition,
    DiscardSlotComponent? fromDiscardSlot,
  }) {
    final fromDiscardTile = fromDiscardSlot?.currentTile;

    if (fromDiscardTile != null) {
      fromDiscardTile.position = startPosition.clone();
      return fromDiscardTile;
    }

    if (closedPile.length > 1) {
      // Closed-pile drag is a visual preview only. Never expose the actual
      // top tile before a successful game_draw response. TileComponent renders
      // joker models with tile_back.png, so use a disposable face-down model.
      // The real tile is rendered from server state after the draw commits.
      final hiddenPreview = TileModel(
        id: '__closed_draw_preview__',
        value: 0,
        color: TileColor.red,
        isJoker: true,
        isFakeJoker: false,
      );
      return TileComponent(
        tile: hiddenPreview,
        position: startPosition.clone(),
      );
    }

    return null;
  }

  void _consumeDiscardTopVisualAfterDraw(int fromSeat, {String? expectedTileId}) {
    _discardChanged(fromSeat);
    final fromSlot = _discardSlotsByIndex[_slotIndexForAbsoluteSeat(fromSeat)];
    final mappedTop = _discardTopTilesBySeat[fromSeat];
    final slotTop = fromSlot?.currentTile;
    final consumedId = expectedTileId ?? mappedTop?.tile.id ?? slotTop?.tile.id;
    if (consumedId == null) return;
    _consumedDiscardTileBySeat[fromSeat] = consumedId;

    // Flame removes components on a later lifecycle pass. Suppress the old
    // face synchronously, before the travelling tile is added to the world.
    for (final top in {mappedTop, slotTop}) {
      if (top == null || top.tile.id != consumedId) continue;
      // A local drag carries this same component into the pending rack slot.
      // Remove its source ownership below, keeping its face visible until ack.
      if (identical(top, _pendingDrawVisualTile)) continue;
      top.hideTileVisual = true;
      top.removeFromParent();
    }
    if (mappedTop?.tile.id == consumedId) _discardTopTilesBySeat.remove(fromSeat);
    if (slotTop?.tile.id == consumedId) fromSlot?.currentTile = null;

    final stack = _discardStacksBySeat[fromSeat];
    stack?.removeWhere((model) => model.id == consumedId);
    // An older pickup must never remove a newer discard already displayed.
    if (fromSlot == null || _discardTopTilesBySeat[fromSeat] != null ||
        fromSlot.currentTile != null) return;
    final revealed = _peekDiscardStack(fromSeat);
    if (revealed != null) {
      final tile = TileComponent(tile: revealed, position: fromSlot.position.clone())
        ..priority = 50
        ..isLocked = true;
      world.add(tile);
      _discardTopTilesBySeat[fromSeat] = tile;
      fromSlot.currentTile = tile;
    } else if (stack != null) {
      unawaited(_fetchAndShowPreviousDiscardTop(fromSeat, consumedId));
    }
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

  Future<void> _fetchAndShowPreviousDiscardTop(
    int seat,
    String removedTileId,
  ) async {
    final revisionAtStart = _discardRevision(seat);
    final epoch = _handStateEpoch;
    try {
      final rows = await Supabase.instance.client
          .from('table_discards')
          .select('tile')
          .eq('table_id', tableId)
          .eq('seat_index', seat)
          .isFilter('drawn_at', null)
          .order('created_at', ascending: false)
          .limit(6);
      if (!_lifecycleActive || epoch != _handStateEpoch || rows is! List) return;
      if (_discardRevision(seat) != revisionAtStart) return;

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
      if (_discardRevision(seat) != revisionAtStart) return;
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

      final top = TileComponent(tile: model, position: slot.position.clone())
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
