import 'package:flutter/material.dart';

class _LobbyRouteClock extends InheritedWidget {
  final Animation<double> animation;
  const _LobbyRouteClock({required this.animation, required super.child});
  @override
  bool updateShouldNotify(_LobbyRouteClock oldWidget) =>
      animation != oldWidget.animation;
}

class _LobbyCinemaPageRoute extends PageRouteBuilder<void> {
  _LobbyCinemaPageRoute({
    required super.pageBuilder,
    required super.transitionsBuilder,
    required super.transitionDuration,
    required super.reverseTransitionDuration,
  });

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _LobbyRouteClock(
    // ModalRoute.animation temporarily reports completion for offstage layout.
    // The real controller never fakes a completed entrance.
    animation: controller!.view,
    child: super.buildPage(context, animation, secondaryAnimation),
  );
}

/// Both scenes share a clock, including when authentication replaces the home.
PageRouteBuilder<void> lobbyCinemaRoute({
  required Widget login,
  required Widget lobby,
  bool reducedMotion = false,
}) => _LobbyCinemaPageRoute(
  transitionDuration: reducedMotion
      ? Duration.zero
      : const Duration(milliseconds: 550),
  reverseTransitionDuration: reducedMotion
      ? Duration.zero
      : const Duration(milliseconds: 550),
  pageBuilder: (_, _, _) => lobby,
  transitionsBuilder: (context, animation, _, child) {
    final eased = animation.drive(CurveTween(curve: Curves.easeInOutCubic));
    return ColoredBox(
      color: const Color(0xFF050608),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: FadeTransition(
              opacity: eased.drive(Tween(begin: 1.0, end: 0.0)),
              child: ScaleTransition(
                scale: eased.drive(Tween(begin: 1.0, end: .94)),
                // Keep the incoming subtree at the same depth after completion.
                child: animation.status == AnimationStatus.completed
                    ? const SizedBox.shrink()
                    : login,
              ),
            ),
          ),
          IgnorePointer(
            ignoring: animation.value < 1,
            child: FadeTransition(
              opacity: eased,
              child: ScaleTransition(
                scale: eased.drive(Tween(begin: 1.05, end: 1.0)),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  },
);

/// Plays once on mount; ordinary data/selection rebuilds keep the settled state.
class LobbyEntrance extends StatefulWidget {
  final Widget child;
  final Offset from;
  final Duration delay;
  const LobbyEntrance({
    super.key,
    required this.child,
    required this.from,
    this.delay = Duration.zero,
  });
  @override
  State<LobbyEntrance> createState() => _LobbyEntranceState();
}

class _LobbyEntranceState extends State<LobbyEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  bool _started = false;
  Animation<double>? _routeAnimation;

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _started) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _started = true;
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _routeAnimation =
          context
              .dependOnInheritedWidgetOfExactType<_LobbyRouteClock>()
              ?.animation ??
          ModalRoute.of(context)?.animation;
      if (_routeAnimation == null || _routeAnimation!.isCompleted) {
        _onRouteStatus(AnimationStatus.completed);
      } else {
        _routeAnimation!.addStatusListener(_onRouteStatus);
      }
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = _controller.drive(
      CurveTween(
        curve: Interval(
          (widget.delay.inMilliseconds / 350).clamp(0.0, .99),
          1,
          curve: Curves.easeOutCubic,
        ),
      ),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(Tween(begin: widget.from, end: Offset.zero)),
        child: widget.child,
      ),
    );
  }
}
