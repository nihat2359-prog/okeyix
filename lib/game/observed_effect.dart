import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'game_activity_probe.dart';

mixin ActivityLifecycleObservation on Component {
  @override
  void onChildrenChanged(Component child, ChildrenChangeType type) {
    super.onChildrenChanged(child, type);
    if (GameActivityProbe.enabled) {
      activityProbeFor(this)?.notifyWake(GameWakeReason.lifecycle);
    }
  }
}

class ActivityObservedWorld extends World with ActivityLifecycleObservation {}

GameActivityProbe? activityProbeFor(Component component) {
  if (!GameActivityProbe.enabled) return null;
  final game = component.findGame();
  return game is GameActivityProbeHost
      ? (game as GameActivityProbeHost).activityProbe
      : null;
}

/// Returns the SAME effect: targets, controllers, type checks and timing stay intact.
/// Queued effects block quiet classification even before their first frame.
T observeGameEffect<T extends Effect>(
  T effect,
  GameActivityProbe? probe,
  String source,
) {
  if (!GameActivityProbe.enabled || probe == null) return effect;
  return attachEffectObservation(effect, probe, source);
}

/// Separated for deterministic tests without compile-time flags.
T attachEffectObservation<T extends Effect>(
  T effect,
  GameActivityProbe probe,
  String source,
) {
  if (!probe.queueEffect(effect, source)) return effect;
  final original = effect.onComplete;
  effect.onComplete = () {
    try {
      original?.call();
    } finally {
      probe.finishEffect(effect, cancelled: false);
    }
  };
  effect.add(_EffectRemovalObservation(effect, probe));
  return effect;
}

class _EffectRemovalObservation extends Component {
  final Effect effect;
  final GameActivityProbe probe;
  _EffectRemovalObservation(this.effect, this.probe);
  @override
  void onMount() {
    super.onMount();
    probe.event('effectMounted');
  }

  @override
  void onRemove() {
    // Only the original completion callback proves completion.
    probe.finishEffect(effect, cancelled: true);
    super.onRemove();
  }
}
