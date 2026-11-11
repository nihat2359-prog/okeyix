import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'pisti_cards.dart';
import 'pisti_chrome.dart';
import 'pisti_layout.dart';
import 'pisti_model.dart';
import '../../services/pisti_service.dart';

enum _Motion { idle, deal, play, capture, thinking, returning }

class _Flight {
  const _Flight(
    this.card,
    this.from,
    this.to,
    this.size,
    this.angle,
    this.opponent,
  );
  final PistiCard card;
  final Rect from, to;
  final Size size;
  final double angle;
  final bool opponent;
}

class PistiDemoScreen extends StatefulWidget {
  const PistiDemoScreen({
    super.key,
    this.initialScenario = PistiScenario.normal,
    this.seed,
    this.online,
    this.turnSeconds,
  });
  final PistiScenario initialScenario;
  final int? seed;
  final PistiController? online;
  final int? turnSeconds;
  @override
  State<PistiDemoScreen> createState() => _PistiDemoScreenState();
}

class _PistiDemoScreenState extends State<PistiDemoScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late PistiGame _game;
  final _sceneKey = GlobalKey();
  final _cardKeys = <int, GlobalKey>{};
  Completer<void>? _animationDone, _resumeGate;
  bool _foreground = true,
      _active = true,
      _busy = true,
      _result = false,
      _initialDeal = true;
  int _generation = 0;
  int? _selected;
  PistiCard? _dragCard;
  Rect? _dragRect;
  _Flight? _flight;
  int? _submittedCard;
  PistiMove? _capture;
  _Motion _motion = _Motion.idle;
  PistiLayout _layout = PistiLayout(const Size(844, 390));
  bool _receiving = false;
  int _serverVersion = -1;
  int _eventSeq = -1;
  bool get _online => widget.online != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          final done = _animationDone;
          _animationDone = null;
          if (done != null && !done.isCompleted) done.complete();
        }
      });
    _restart(widget.initialScenario, initial: true);
    widget.online?.addListener(_serverChanged);
    if (_online) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _serverChanged());
    }
  }

  Future<void> _serverChanged() async {
    final data = widget.online?.snapshot;
    if (!mounted ||
        !_online ||
        data == null ||
        data['game'] == null ||
        _receiving) {
      return;
    }
    final version = (data['room']['version'] as num).toInt();
    if (version <= _serverVersion) return;
    _receiving = true;
    final game = Map<String, dynamic>.from(data['game'] as Map);
    final first = _serverVersion < 0;
    final viewer = data['viewer'] as int;
    final event = game['event'];
    final previousDeal = _game.dealNumber;
    if (_serverVersion >= 0 &&
        version == _serverVersion + 1 &&
        event != null &&
        (event['seq'] as num).toInt() > _eventSeq &&
        _active) {
      final id = event['card'] as int;
      final card = PistiCard(PistiSuit.values[id ~/ 13], id % 13 + 1);
      final seat = event['seat'] == (viewer < 0 ? 0 : viewer)
          ? PistiSeat.player
          : PistiSeat.opponent;
      final index = seat == PistiSeat.player && viewer >= 0
          ? _game.hand(seat).indexWhere((c) => c.id == id)
          : 0;
      if (index >= 0) {
        final alreadyPlaced = seat == PistiSeat.player && id == _submittedCard;
        if (!alreadyPlaced) {
          setState(() {
            _busy = true;
            _selected = null;
            _dragCard = null;
            _dragRect = null;
            _flight = _Flight(
              card,
              _layout.hand(seat, index, _game.hand(seat).length),
              _layout.tableCard(_game.pile.length, _game.pile.length + 1),
              _layout.size,
              0,
              seat == PistiSeat.opponent,
            );
          });
          await _animate(
            _Motion.play,
            seat == PistiSeat.opponent ? 420 : 360,
            _generation,
          );
        }
        if (!mounted) return;
        final captured = event['captured'] as int;
        _game.hand(seat).removeWhere((c) => c.id == id);
        if (captured > 0) {
          final move = PistiMove(
            card: card,
            seat: seat,
            taken: [...List.generate(captured - 1, PistiCard.hidden), card],
            pistiBonus: event['bonus'] as int,
          );
          setState(() {
            _flight = null;
            _game.pile.clear();
          });
          await _collect(move, _generation);
        }
        final sweep = event['sweep'] as int? ?? 0;
        if (sweep > 0 && mounted) {
          final collector = event['sweep_seat'] == (viewer < 0 ? 0 : viewer)
              ? PistiSeat.player
              : PistiSeat.opponent;
          setState(() {
            _flight = null;
            _game.pile.clear();
          });
          await _collect(
            PistiMove(
              card: card,
              seat: collector,
              taken: [...List.generate(sweep - 1, PistiCard.hidden), card],
            ),
            _generation,
          );
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _game = PistiGame.remote(game, viewer);
      _serverVersion = version;
      _eventSeq = (game['event']?['seq'] as num?)?.toInt() ?? -1;
      _flight = null;
      _submittedCard = null;
      _capture = null;
      _selected = null;
      _dragCard = null;
      _dragRect = null;
      _busy = false;
      _initialDeal = false;
      _motion = _Motion.idle;
      _result = false;
    });
    if ((first || previousDeal != _game.dealNumber) && _active) {
      _initialDeal = first;
      await _deal(_generation);
    }
    _receiving = false;
    if (mounted) unawaited(_serverChanged());
  }

  void _restart(PistiScenario scenario, {bool initial = false}) {
    _generation++;
    _controller.stop();
    final oldDone = _animationDone;
    _animationDone = null;
    if (oldDone != null && !oldDone.isCompleted) oldDone.complete();
    void reset() {
      _game = _online && widget.online!.snapshot?['game'] != null
          ? PistiGame.remote(
              Map<String, dynamic>.from(
                widget.online!.snapshot!['game'] as Map,
              ),
              widget.online!.snapshot!['viewer'] as int,
            )
          : PistiGame(
              scenario: scenario,
              random: widget.seed == null ? null : math.Random(widget.seed),
            );
      _motion = _Motion.deal;
      _busy = true;
      _result = false;
      _initialDeal = true;
      _selected = null;
      _dragCard = null;
      _dragRect = null;
      _flight = null;
      _submittedCard = null;
      _capture = null;
      _controller.value = 0;
      _cardKeys.clear();
    }

    if (initial) {
      reset();
    } else {
      setState(reset);
    }
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current(generation) && !_online) unawaited(_deal(generation));
    });
  }

  bool _current(int generation) => mounted && generation == _generation;
  Future<bool> _animate(_Motion kind, int milliseconds, int generation) async {
    if (!_current(generation)) return false;
    if (!_active) {
      _resumeGate ??= Completer<void>();
      await _resumeGate!.future;
      if (!_current(generation)) return false;
    }
    final done = Completer<void>();
    _animationDone = done;
    setState(() {
      _motion = kind;
      _controller.duration = Duration(milliseconds: milliseconds);
    });
    _controller.forward(from: 0);
    await done.future;
    return _current(generation);
  }

  Future<void> _deal(int generation) async {
    if (!await _animate(_Motion.deal, _initialDeal ? 1150 : 850, generation)) {
      return;
    }
    setState(() {
      _motion = _Motion.idle;
      _busy = false;
      _initialDeal = false;
    });
  }

  void _syncActivity() {
    if (!mounted) return;
    final active =
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (_active == active) return;
    setState(() => _active = active);
    if (!active) {
      // A separate completer, rather than the ticker future, keeps the game
      // sequence suspended when stop(canceled:false) completes the ticker.
      _controller.stop(canceled: false);
    } else {
      if (_animationDone != null) _controller.forward();
      final gate = _resumeGate;
      _resumeGate = null;
      if (gate != null && !gate.isCompleted) gate.complete();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncActivity();
  }

  Offset _local(Offset global) =>
      (_sceneKey.currentContext!.findRenderObject()! as RenderBox)
          .globalToLocal(global);
  Rect _actualCardRect(PistiCard card, PistiSeat seat, int index) {
    final box = _cardKeys[card.id]?.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return Rect.fromCenter(
        center: _local(box.localToGlobal(box.size.center(Offset.zero))),
        width: box.size.width,
        height: box.size.height,
      );
    }
    return _layout.hand(
      seat,
      index,
      _game.hand(seat).length,
      selected: _selected == card.id,
    );
  }

  bool get _canPlay =>
      !_busy &&
      _active &&
      !_result &&
      !_game.finished &&
      _game.turn == PistiSeat.player &&
      (!_online ||
          (!widget.online!.busy &&
              widget.online!.error == null &&
              (widget.online!.snapshot?['viewer'] as int? ?? -1) >= 0));
  void _tap(PistiCard card) {
    if (!_canPlay || _dragCard != null) return;
    if (_selected == card.id) {
      unawaited(_play(card, PistiSeat.player));
    } else {
      setState(() => _selected = card.id);
    }
  }

  void _dragStart(PistiCard card) {
    if (!_canPlay || _dragCard != null) return;
    final index = _game
        .hand(PistiSeat.player)
        .indexWhere((c) => c.id == card.id);
    if (index < 0) return;
    final rect = _actualCardRect(card, PistiSeat.player, index);
    setState(() {
      _selected = card.id;
      _dragCard = card;
      _dragRect = rect;
    });
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_dragCard == null || !_canPlay) return;
    setState(() => _dragRect = _dragRect!.shift(details.delta));
  }

  void _dragEnd() {
    final card = _dragCard, rect = _dragRect;
    if (card == null || rect == null || _busy) return;
    if (!_active) {
      unawaited(_returnCard(card, rect));
      return;
    }
    if (_layout.dropZone.inflate(10).contains(rect.center)) {
      unawaited(_play(card, PistiSeat.player, from: rect));
    } else {
      unawaited(_returnCard(card, rect));
    }
  }

  void _dragCancel() {
    final card = _dragCard, rect = _dragRect;
    if (card != null && rect != null && !_busy) {
      unawaited(_returnCard(card, rect));
    }
  }

  Future<void> _returnCard(PistiCard card, Rect from) async {
    final generation = _generation;
    final index = _game
        .hand(PistiSeat.player)
        .indexWhere((c) => c.id == card.id);
    setState(() {
      _busy = true;
      _dragCard = null;
      _dragRect = null;
      _flight = _Flight(
        card,
        from,
        _layout.hand(
          PistiSeat.player,
          index,
          _game.hand(PistiSeat.player).length,
          selected: true,
        ),
        _layout.size,
        0,
        false,
      );
    });
    if (!await _animate(_Motion.returning, 210, generation)) return;
    setState(() {
      _flight = null;
      _busy = false;
      _motion = _Motion.idle;
    });
  }

  Future<void> _play(
    PistiCard card,
    PistiSeat seat, {
    Rect? from,
    bool opponent = false,
  }) async {
    if (_online) {
      if (!_canPlay) return;
      final index = _game.hand(seat).indexWhere((c) => c.id == card.id);
      if (index < 0) return;
      final generation = _generation;
      final origin = from ?? _actualCardRect(card, seat, index);
      setState(() {
        _busy = true;
        _submittedCard = card.id;
        _flight = _Flight(
          card,
          origin,
          _layout.tableCard(_game.pile.length, _game.pile.length + 1),
          _layout.size,
          _layout.handAngle(index, _game.hand(seat).length, seat),
          false,
        );
        _dragCard = null;
        _dragRect = null;
        _selected = null;
      });
      if (!await _animate(_Motion.play, from == null ? 300 : 160, generation)) {
        return;
      }
      if (!_current(generation)) return;
      final room = widget.online!.snapshot!['room'];
      await widget.online!.send('play', {
        'card': card.id,
        'version': room['version'],
        'match_id': room['match_id'],
      });
      if (_current(generation) &&
          _submittedCard == card.id &&
          widget.online!.error != null &&
          !widget.online!.hasPendingCommand) {
        final placed = _flight?.to;
        _submittedCard = null;
        if (placed != null) await _returnCard(card, placed);
      }
      return;
    }
    if ((!opponent && !_canPlay) ||
        !_active ||
        _game.turn != seat ||
        _game.finished) {
      return;
    }
    final generation = _generation;
    final cards = _game.hand(seat);
    final index = cards.indexWhere((c) => c.id == card.id);
    if (index < 0) return;
    final origin = from ?? _actualCardRect(card, seat, index);
    final angle = _layout.handAngle(index, cards.length, seat);
    setState(() {
      _busy = true;
      _dragCard = null;
      _dragRect = null;
      _selected = null;
      _flight = _Flight(
        card,
        origin,
        _layout.tableCard(_game.pile.length, _game.pile.length + 1),
        _layout.size,
        angle,
        opponent,
      );
    });
    if (!await _animate(_Motion.play, opponent ? 420 : 360, generation)) return;
    final move = _game.play(seat, card.id);
    if (move == null) {
      setState(() {
        _flight = null;
        _busy = false;
        _motion = _Motion.idle;
      });
      return;
    }
    setState(() {
      _flight = null;
      _capture = move.taken.isEmpty ? null : move;
    });
    if (move.taken.isNotEmpty && !await _collect(move, generation)) return;
    if (!_current(generation)) return;
    if (_game.hands.values.every((h) => h.isEmpty)) {
      if (_game.deck.isEmpty) {
        final sweep = _game.finish();
        if (sweep != null && !await _collect(sweep, generation)) return;
        if (!_current(generation)) return;
        setState(() {
          _result = true;
          _busy = false;
          _motion = _Motion.idle;
        });
      } else {
        _game.dealNext();
        setState(() {
          _motion = _Motion.deal;
          _controller.value = 0;
        });
        await _deal(generation);
      }
      return;
    }
    if (_game.turn == PistiSeat.opponent) {
      if (!await _animate(_Motion.thinking, 680, generation)) return;
      await _play(
        _game.chooseOpponentCard(),
        PistiSeat.opponent,
        opponent: true,
      );
    } else {
      setState(() {
        _busy = false;
        _motion = _Motion.idle;
      });
    }
  }

  Future<bool> _collect(PistiMove move, int generation) async {
    setState(() => _capture = move);
    if (!await _animate(
      _Motion.capture,
      move.isPisti ? 920 : 490,
      generation,
    )) {
      return false;
    }
    setState(() => _capture = null);
    return true;
  }

  @override
  void dispose() {
    widget.online?.removeListener(_serverChanged);
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    for (final completer in [_animationDone, _resumeGate]) {
      if (completer != null && !completer.isCompleted) completer.complete();
    }
    _controller.dispose();
    super.dispose();
  }

  double _dealProgress(int order) =>
      ((_controller.value - order * .048) / .42).clamp(0.0, 1.0);
  Rect _rescale(Rect rect, Size source, Size target) => Rect.fromLTWH(
    rect.left * target.width / source.width,
    rect.top * target.height / source.height,
    rect.width * target.width / source.width,
    rect.height * target.height / source.height,
  );
  Widget _placed(
    Rect rect,
    Widget child, {
    double angle = 0,
    double opacity = 1,
  }) => Positioned.fromRect(
    rect: rect,
    child: Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.rotate(angle: angle, child: child),
    ),
  );

  List<Widget> _cards(PistiLayout layout) {
    final widgets = <Widget>[];
    final dealing = _motion == _Motion.deal;
    final pile = _game.pile;
    final start = math.max(0, pile.length - 4);
    for (var i = start; i < pile.length; i++) {
      if (dealing && _initialDeal && _dealProgress(i) < 1) continue;
      final tableRect = _motion == _Motion.play && _flight != null
          ? Rect.lerp(
              layout.tableCard(i, pile.length),
              layout.tableCard(i, pile.length + 1),
              Curves.easeInOutCubic.transform(_controller.value),
            )!
          : layout.tableCard(i, pile.length);
      widgets.add(
        _placed(
          tableRect,
          PistiCardView(card: pile[i], faceUp: i == pile.length - 1),
          angle: layout.tableAngle(i),
        ),
      );
    }
    for (final seat in PistiSeat.values) {
      final cards = _game.hand(seat);
      for (var i = 0; i < cards.length; i++) {
        final card = cards[i];
        final order =
            (_initialDeal ? _game.pile.length : 0) + i * 2 + seat.index;
        if (dealing && _dealProgress(order) < 1) continue;
        if (_flight?.card.id == card.id) continue;
        final selected = _selected == card.id;
        final rect = layout.hand(seat, i, cards.length, selected: selected);
        widgets.add(
          AnimatedPositioned.fromRect(
            key: ValueKey('hand-${card.id}'),
            rect: rect,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Transform.rotate(
              angle: layout.handAngle(i, cards.length, seat),
              child: Listener(
                onPointerCancel: (_) {
                  if (_dragCard?.id == card.id) _dragCancel();
                },
                child: GestureDetector(
                  key: ValueKey('pisti-card-${card.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: seat == PistiSeat.player ? () => _tap(card) : null,
                  onPanStart: seat == PistiSeat.player
                      ? (_) => _dragStart(card)
                      : null,
                  onPanUpdate: seat == PistiSeat.player
                      ? (details) {
                          if (_dragCard?.id == card.id) _dragUpdate(details);
                        }
                      : null,
                  onPanEnd: seat == PistiSeat.player
                      ? (_) {
                          if (_dragCard?.id == card.id) _dragEnd();
                        }
                      : null,
                  onPanCancel: seat == PistiSeat.player
                      ? () {
                          if (_dragCard?.id == card.id) _dragCancel();
                        }
                      : null,
                  child: Semantics(
                    button: seat == PistiSeat.player,
                    enabled: _canPlay,
                    selected: selected,
                    label: seat == PistiSeat.player
                        ? '${card.suitName} ${card.label}${selected ? ', seçili, oynamak için tekrar dokun' : ''}'
                        : 'Rakibin kapalı kartı',
                    child: SizedBox(
                      key: _cardKeys.putIfAbsent(card.id, GlobalKey.new),
                      child: Opacity(
                        opacity: _dragCard?.id == card.id ? 0 : 1,
                        child: PistiCardView(
                          card: card,
                          faceUp:
                              seat == PistiSeat.player && card.hiddenId == null,
                          selected: selected,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    if (dealing) {
      final deals =
          <({PistiCard card, Rect to, int order, bool faceUp, double angle})>[];
      if (_initialDeal) {
        for (var i = 0; i < pile.length; i++) {
          deals.add((
            card: pile[i],
            to: layout.tableCard(i, pile.length),
            order: i,
            faceUp: i == pile.length - 1,
            angle: layout.tableAngle(i),
          ));
        }
      }
      for (final seat in PistiSeat.values) {
        final cards = _game.hand(seat);
        for (var i = 0; i < cards.length; i++) {
          deals.add((
            card: cards[i],
            to: layout.hand(seat, i, cards.length),
            order: (_initialDeal ? pile.length : 0) + i * 2 + seat.index,
            faceUp: seat == PistiSeat.player && cards[i].hiddenId == null,
            angle: layout.handAngle(i, cards.length, seat),
          ));
        }
      }
      for (final deal in deals) {
        final raw = _dealProgress(deal.order);
        if (raw <= 0 || raw >= 1) continue;
        final t = Curves.easeInOutCubic.transform(raw);
        final rect = Rect.lerp(
          layout.deck,
          deal.to,
          t,
        )!.shift(Offset(0, -math.sin(math.pi * t) * 14));
        widgets.add(
          _placed(
            rect,
            Transform.scale(
              scaleX: deal.faceUp
                  ? (.15 + .85 * (raw < .5 ? 1 - raw * 2 : raw * 2 - 1))
                  : 1,
              child: PistiCardView(
                card: deal.card,
                faceUp: deal.faceUp && raw > .5,
              ),
            ),
            angle: deal.angle * t,
          ),
        );
      }
    }
    final flight = _flight;
    if (flight != null) {
      final raw = _controller.value;
      final t = Curves.easeInOutCubic.transform(raw);
      final from = _rescale(flight.from, flight.size, layout.size),
          to = _rescale(flight.to, flight.size, layout.size);
      final rect = Rect.lerp(from, to, t)!.shift(
        Offset(
          0,
          -math.sin(math.pi * t) *
              (_motion == _Motion.returning ? 0 : layout.h * .09),
        ),
      );
      widgets.add(
        _placed(
          rect,
          Transform.scale(
            scaleX: flight.opponent ? (.12 + .88 * (2 * raw - 1).abs()) : 1,
            child: PistiCardView(
              key: ValueKey('pisti-flight-${flight.card.id}'),
              card: flight.card,
              faceUp: !flight.opponent || raw > .5,
            ),
          ),
          angle:
              flight.angle * (1 - t) +
              (_motion == _Motion.returning
                      ? 0
                      : layout.tableAngle(_game.pile.length)) *
                  t,
        ),
      );
    }
    final capture = _capture;
    if (capture != null) {
      final raw = _controller.value;
      final t = Curves.easeInCubic.transform(
        ((raw - (capture.isPisti ? .26 : .08)) / (capture.isPisti ? .64 : .84))
            .clamp(0.0, 1.0),
      );
      final cards = capture.taken;
      for (var i = math.max(0, cards.length - 4); i < cards.length; i++) {
        final from = layout.tableCard(i, cards.length),
            to = layout.collected(capture.seat);
        widgets.add(
          _placed(
            Rect.lerp(from, to, t)!,
            PistiCardView(card: cards[i], faceUp: t < .65),
            angle: layout.tableAngle(i) * (1 - t),
            opacity: 1 - ((t - .8) / .2).clamp(0.0, 1.0),
          ),
        );
      }
      if (capture.isPisti) {
        widgets.add(
          Positioned(
            left: layout.center.dx - 110,
            top: layout.center.dy - 59,
            width: 220,
            height: 122,
            child: Center(
              child: PistiMoment(
                progress: raw,
                bonus: capture.pistiBonus,
                player: capture.seat == PistiSeat.player,
              ),
            ),
          ),
        );
      }
    }
    if (_dragCard != null && _dragRect != null) {
      widgets.add(
        _placed(
          _dragRect!,
          IgnorePointer(child: PistiCardView(card: _dragCard, selected: true)),
        ),
      );
    }
    return widgets;
  }

  Widget _tableMarks(PistiLayout layout) => Stack(
    children: [
      Positioned.fromRect(
        rect: layout.dropZone,
        child: AnimatedContainer(
          key: const ValueKey('pisti-drop-zone'),
          duration: const Duration(milliseconds: 130),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: _dragCard == null
                  ? const Color(0x0c8fa5c3)
                  : pistiCoral.withValues(alpha: .5),
            ),
          ),
          child: _game.pile.isEmpty && _capture == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        color: Color(0xff5c7292),
                        size: 22,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _dragCard == null ? 'YENİ BİR HAMLE' : 'KARTI BIRAK',
                        style: const TextStyle(
                          color: Color(0xff7890af),
                          fontSize: 8,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
      ),
      if (_game.deck.isNotEmpty || _motion == _Motion.deal) ...[
        for (var i = 2; i >= 0; i--)
          _placed(
            layout.deck.shift(Offset(-i * 2.5, -i * 2.5)),
            const PistiCardView(faceUp: false),
            angle: -.035,
          ),
        Positioned(
          left: layout.compact ? layout.deck.left - 43 : layout.deck.left - 16,
          top: layout.compact
              ? layout.playerInfo(PistiSeat.opponent).bottom + 4
              : layout.deck.bottom + 12,
          width: layout.compact ? 40 : layout.deck.width + 32,
          child: Column(
            children: [
              Text(
                '${_game.deck.length}',
                style: const TextStyle(
                  color: Color(0xffc4d2e7),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'DESTE',
                style: TextStyle(
                  color: pistiMuted,
                  fontSize: 7,
                  letterSpacing: 1.7,
                ),
              ),
            ],
          ),
        ),
      ],
      if (_game.pile.length > 1)
        Positioned(
          left: layout.center.dx + layout.tableHeight * .46,
          top: layout.center.dy + 19,
          child: Text(
            '${_game.pile.length}',
            style: const TextStyle(
              color: pistiMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      for (final seat in PistiSeat.values) ...[
        if (_game.won[seat]!.isEmpty)
          _placed(
            layout.collected(seat),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xff345b44), width: .8),
              ),
              child: const Icon(
                Icons.layers_outlined,
                size: 15,
                color: Color(0xff526985),
              ),
            ),
          ),
        for (
          var i = 0;
          i < math.min(3, (_game.won[seat]!.length / 4).ceil());
          i++
        )
          _placed(
            layout.collected(seat).shift(Offset(-i * 2.0, -i * 2.0)),
            const PistiCardView(faceUp: false),
            angle: .08,
          ),
        Positioned(
          left: layout.collected(seat).center.dx - 34,
          top: layout.collected(seat).bottom + 8,
          width: 68,
          child: Column(
            children: [
              Text(
                '${_game.won[seat]!.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xffc0cde0),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'ALINAN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: pistiMuted,
                  fontSize: 7,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  String get _hint => _online && widget.online!.busy
      ? 'HAMLE DOĞRULANIYOR'
      : switch (_motion) {
          _Motion.deal => 'KARTLAR DAĞITILIYOR',
          _Motion.thinking => 'RAKİP HAMLESİNİ SEÇİYOR',
          _Motion.capture =>
            _capture?.seat == PistiSeat.player
                ? 'KARTLAR SENİN'
                : 'RAKİP KARTLARI TOPLADI',
          _ =>
            _online && !_canPlay
                ? 'RAKİBİN SIRASI'
                : _selected == null
                ? 'BİR KART SEÇ'
                : 'TEKRAR DOKUN · MASAYA SÜRÜKLE',
        };
  String _scenarioName(PistiScenario s) => switch (s) {
    PistiScenario.normal => 'Normal oyun',
    PistiScenario.capture => 'Kart toplama',
    PistiScenario.pisti => 'Pişti anı',
    PistiScenario.finish => 'El sonu',
  };

  Widget _header(PistiLayout layout) => Stack(
    children: [
      Positioned(
        left: 14,
        top: 10,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (Navigator.canPop(context))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: 'Lobiye dön',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                      color: pistiMuted,
                    ),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'okeyix',
                      style: TextStyle(
                        color: pistiPaper,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.7,
                      ),
                    ),
                    SizedBox(width: 5),
                    Text('●', style: TextStyle(color: pistiCoral, fontSize: 8)),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  _game.scenario == PistiScenario.normal
                      ? 'PİŞTİ  /  ${_game.dealNumber.toString().padLeft(2, '0')}—06'
                      : 'ÖRNEK: ${_scenarioName(_game.scenario).toUpperCase()}',
                  style: TextStyle(
                    color: _game.scenario == PistiScenario.normal
                        ? pistiMuted
                        : pistiCoral,
                    fontSize: _game.scenario == PistiScenario.normal ? 8 : 7,
                    letterSpacing: _game.scenario == PistiScenario.normal
                        ? 1.5
                        : .3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      if (!_online)
        Positioned(
          right: 12,
          top: 10,
          child: PopupMenuButton<PistiScenario>(
            key: const ValueKey('pisti-scenarios'),
            tooltip: 'Demo senaryoları',
            color: const Color(0xff143a28),
            surfaceTintColor: Colors.transparent,
            elevation: 12,
            offset: const Offset(0, 37),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: _restart,
            itemBuilder: (context) => [
              const PopupMenuItem<PistiScenario>(
                enabled: false,
                height: 28,
                child: Text(
                  'GELİŞTİRME DEMOSU',
                  style: TextStyle(
                    color: pistiMuted,
                    fontSize: 8,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              for (final scenario in PistiScenario.values)
                PopupMenuItem(
                  value: scenario,
                  height: 36,
                  child: Text(
                    _scenarioName(scenario),
                    style: const TextStyle(color: pistiPaper, fontSize: 12),
                  ),
                ),
            ],
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0x5530523c),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xff3d6250), width: .7),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 13, color: pistiMuted),
                  SizedBox(width: 6),
                  Text(
                    'DEMO',
                    style: TextStyle(
                      color: pistiMuted,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.expand_more_rounded, size: 13, color: pistiMuted),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode && !_online) return const SizedBox.shrink();
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Montserrat'),
      ),
      child: TickerMode(
        enabled: _active,
        child: Scaffold(
          backgroundColor: const Color(0xff071b13),
          body: Stack(
            children: [
              const Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: PistiSurface()),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _layout = PistiLayout(constraints.biggest);
                    final layout = _layout;
                    return Stack(
                      key: _sceneKey,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(child: _tableMarks(layout)),
                        ),
                        for (final seat in PistiSeat.values)
                          Positioned.fromRect(
                            rect: layout.playerInfo(seat),
                            child: PistiPlayerBadge(
                              online: _online,
                              secondsLeft: _online && _game.turn == seat
                                  ? widget.turnSeconds
                                  : null,
                              isBot:
                                  _online &&
                                  _onlineName(seat).endsWith(' · BOT'),
                              name: _online ? _onlineName(seat) : null,
                              avatarUrl: _online ? _onlineAvatar(seat) : null,
                              seat: seat,
                              score: _game.score(seat),
                              cards: _game.won[seat]!.length,
                              compact: layout.compact,
                              active:
                                  !_result &&
                                  _motion != _Motion.deal &&
                                  _game.turn == seat,
                              thinking: seat == PistiSeat.opponent && _busy,
                            ),
                          ),
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (_, _) => Stack(
                              clipBehavior: Clip.none,
                              children: _cards(layout),
                            ),
                          ),
                        ),
                        if (!_result)
                          Positioned(
                            bottom: 3,
                            left: layout.w * .31,
                            right: layout.w * .24,
                            child: IgnorePointer(
                              child: Text(
                                _hint,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                style: const TextStyle(
                                  color: pistiMuted,
                                  fontSize: 7,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if (_result)
                          Positioned.fill(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 320),
                              builder: (_, value, child) => Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - value) * 8),
                                  child: child,
                                ),
                              ),
                              child: PistiResult(
                                key: const ValueKey('pisti-result'),
                                game: _game,
                                onReplay: () => _restart(PistiScenario.normal),
                              ),
                            ),
                          ),
                        _header(layout),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _onlineName(PistiSeat seat) {
    final data = widget.online!.snapshot;
    if (data == null) return 'Oyuncu';
    final viewer = data['viewer'] as int;
    final index = seat == PistiSeat.player
        ? (viewer < 0 ? 0 : viewer)
        : 1 - (viewer < 0 ? 0 : viewer);
    final player = data['room']['seats'][index];
    return '${player['name']}${player['bot'] == true ? ' · BOT' : ''}';
  }

  String? _onlineAvatar(PistiSeat seat) {
    final data = widget.online!.snapshot;
    if (data == null) return null;
    final viewer = data['viewer'] as int;
    final index = seat == PistiSeat.player
        ? (viewer < 0 ? 0 : viewer)
        : 1 - (viewer < 0 ? 0 : viewer);
    return data['room']['seats'][index]['avatar'] as String?;
  }
}
