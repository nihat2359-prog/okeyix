import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum GameWakeReason {
  pointer,
  effectQueued,
  effectCompleted,
  effectCancelled,
  network,
  lifecycle,
  resize,
  visibility,
  deal,
}

abstract interface class GameActivityProbeHost {
  GameActivityProbe? get activityProbe;
}

/// Opt-in observation only. Quiet samples are NOT proof of an idle engine.
class GameActivityProbe {
  static const enabled =
      !kReleaseMode && bool.fromEnvironment('OKEYIX_ACTIVITY_PROBE');
  final Stopwatch _clock = Stopwatch()..start();
  final int Function()? microseconds;
  GameActivityProbe({this.microseconds});
  int get _now => microseconds?.call() ?? _clock.elapsedMicroseconds;
  final Map<String, int> _events = {};
  final Map<String, int> _micros = {};
  final Set<int> _pointers = {};
  Set<Effect> _effects = {};
  int _last = 0;
  int _nextSample = 0;
  String _state = 'unknown';
  bool? _visible;
  bool _disposed = false;
  final Map<Effect, String> _trackedEffects = {};
  final Map<GameWakeReason, int> _wakeCounts = {};
  int _wakeRevision = 0;
  bool _overflow = false;
  final Set<int> _operations = {};
  int _operationId = 0;

  Future<void> observeOperation(Future<void> Function() action) async {
    final token = beginOperation();
    try {
      await action();
    } finally {
      endOperation(token);
    }
  }

  int? beginOperation() {
    if (_disposed) return null;
    if (_operations.length >= 2048) {
      _overflow = true;
      return null;
    }
    final id = ++_operationId;
    _operations.add(id);
    notifyWake(GameWakeReason.network);
    return id;
  }

  void endOperation(int? id) {
    if (id != null && _operations.remove(id)) {
      notifyWake(GameWakeReason.network);
    }
  }

  void notifyWake(GameWakeReason reason) {
    if (_disposed) return;
    _wakeRevision++;
    _wakeCounts[reason] = (_wakeCounts[reason] ?? 0) + 1;
    _transition('active');
  }

  bool queueEffect(Effect effect, String source) {
    if (_disposed) return false;
    if (_trackedEffects.containsKey(effect)) return false;
    if (_trackedEffects.length >= 2048) {
      _overflow = true;
      return false;
    }
    _trackedEffects[effect] = source;
    notifyWake(GameWakeReason.effectQueued);
    return true;
  }

  void finishEffect(Effect effect, {required bool cancelled}) {
    if (_trackedEffects.remove(effect) == null) return;
    notifyWake(
      cancelled
          ? GameWakeReason.effectCancelled
          : GameWakeReason.effectCompleted,
    );
  }

  void event(String name) {
    if (_disposed) return;
    if (!_events.containsKey(name) && _events.length >= 32) return;
    _events[name] = (_events[name] ?? 0) + 1;
    if (name == 'tableUpdateCandidate' ||
        name == 'handRenderCandidate' ||
        name == 'dealRequested') {
      _transition('active');
      notifyWake(
        name == 'dealRequested' ? GameWakeReason.deal : GameWakeReason.network,
      );
    }
  }

  void _transition(String state) {
    if (_disposed) return;
    final now = _now;
    _micros[_state] = (_micros[_state] ?? 0) + now - _last;
    _last = now;
    _state = state;
  }

  void visibility(bool visible) {
    if (_disposed) return;
    if (_visible == visible) return;
    _visible = visible;
    _pointers.clear();
    event(visible ? 'visible' : 'hidden');
    notifyWake(GameWakeReason.visibility);
    _transition(visible ? 'unknown' : 'hidden');
  }

  void pointer(int id, bool down) {
    if (_disposed) return;
    if (down) {
      _pointers.add(id);
    } else {
      _pointers.remove(id);
    }
    event(down ? 'pointerDown' : 'pointerUpOrCancel');
    notifyWake(GameWakeReason.pointer);
    _transition('active');
  }

  void sample(Component root, {required bool pending, required bool dragging}) {
    if (_disposed) return;
    final now = _now;
    if (now < _nextSample) return;
    _nextSample = now + 100000;
    final effects = <Effect>{};
    var visited = 0;
    var truncated = false;
    for (final component in root.descendants()) {
      if (++visited > 2048) {
        truncated = true;
        break;
      }
      if (component is Effect) effects.add(component);
    }
    for (final effect in effects) {
      if (!_effects.contains(effect)) event('effectFirstObserved');
    }
    for (final effect in _effects) {
      if (!effects.contains(effect)) event('effectNoLongerObserved');
    }
    _effects = effects;
    if (pending) event('pendingLifecycleSample');
    if (pending) notifyWake(GameWakeReason.lifecycle);
    if (effects.any(
      (effect) =>
          !_trackedEffects.containsKey(effect) && !effect.controller.completed,
    )) {
      event('untrackedEffectSample');
    }
    if (dragging) event('dragSample');
    event('samples');
    _transition(
      _visible == false
          ? 'hidden'
          : _visible == null || truncated || _overflow
          ? 'unknown'
          : pending ||
                dragging ||
                _pointers.isNotEmpty ||
                effects.isNotEmpty ||
                _trackedEffects.isNotEmpty ||
                _operations.isNotEmpty
          ? 'active'
          : 'quietUnverified',
    );
  }

  Map<String, Object> snapshot() {
    _transition(_state);
    return {
      'events': Map<String, int>.of(_events),
      'microseconds': Map<String, int>.of(_micros),
      'confirmedIdleMicroseconds': 0,
      'confirmedIdleMeasured': false,
      'wakeRevision': _wakeRevision,
      'wakeCounts': {
        for (final entry in _wakeCounts.entries) entry.key.name: entry.value,
      },
      'openEffects': _trackedEffects.length,
      'openOperations': _operations.length,
      'trackingOverflow': _overflow,
      'coverageComplete': false,
      'classification': 'sampled; quiet is unverified, not permission to pause',
    };
  }

  void dispose() {
    _transition('unknown');
    _disposed = true;
    _clock.stop();
    _effects.clear();
    _trackedEffects.clear();
    _operations.clear();
    _pointers.clear();
  }
}

class GameActivityBoundary extends StatefulWidget {
  final GameActivityProbe? probe;
  final Widget child;
  const GameActivityBoundary({
    super.key,
    required this.probe,
    required this.child,
  });
  @override
  State<GameActivityBoundary> createState() => _GameActivityBoundaryState();
}

class _GameActivityBoundaryState extends State<GameActivityBoundary>
    with WidgetsBindingObserver {
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    if (widget.probe != null) WidgetsBinding.instance.addObserver(this);
  }

  void _visibility() => widget.probe?.visibility(
    _foreground &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _visibility();
  }

  @override
  Widget build(BuildContext context) => widget.probe == null
      ? widget.child
      : Listener(
          onPointerDown: (e) => widget.probe!.pointer(e.pointer, true),
          onPointerUp: (e) => widget.probe!.pointer(e.pointer, false),
          onPointerCancel: (e) => widget.probe!.pointer(e.pointer, false),
          onPointerMove: (e) =>
              widget.probe!.notifyWake(GameWakeReason.pointer),
          child: widget.child,
        );
  @override
  void dispose() {
    if (widget.probe != null) WidgetsBinding.instance.removeObserver(this);
    widget.probe?.visibility(false);
    super.dispose();
  }
}
