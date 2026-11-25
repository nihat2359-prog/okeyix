import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Short paint-only cycles separated by idle time; stops off-route/background.
class _AmbientCycle extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext, Animation<double>, Widget) builder;
  const _AmbientCycle({required this.child, required this.builder});
  @override
  State<_AmbientCycle> createState() => _AmbientCycleState();
}

class _AmbientCycleState extends State<_AmbientCycle>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _phase = AnimationController(vsync: this,
    duration: const Duration(milliseconds: 1800));
  Timer? _repeat;
  bool _foreground = true, _running = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _sync(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }
  void _sync() {
    final active = _foreground && TickerMode.valuesOf(context).enabled &&
      !MediaQuery.disableAnimationsOf(context);
    if (_running == active) return;
    _running = active;
    _repeat?.cancel();
    if (active) {
      _phase.forward(from: 0);
      _repeat = Timer.periodic(const Duration(milliseconds: 3500), (_) => _phase.forward(from: 0));
    } else {
      _phase.stop();
      _phase.value = 0;
    }
  }
  @override
  void dispose() {
    _repeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _phase.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.builder(context, _phase,
    RepaintBoundary(child: widget.child));
}

class LobbyQuickPlayMotion extends StatelessWidget {
  final Widget child;
  final bool enabled;
  const LobbyQuickPlayMotion({super.key, required this.child, required this.enabled});
  @override
  Widget build(BuildContext context) => !enabled ? child : _AmbientCycle(child: child,
    builder: (context, phase, content) => ScaleTransition(
      scale: TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.025)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
        TweenSequenceItem(tween: Tween(begin: 1.025, end: 1.0)
          .chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
      ]).animate(phase),
      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: Stack(children: [
        content,
        Positioned.fill(child: IgnorePointer(child: RepaintBoundary(
          child: CustomPaint(painter: _SweepPainter(phase))))),
      ])),
    ));
}

class _SweepPainter extends CustomPainter {
  final Animation<double> phase;
  _SweepPainter(this.phase) : super(repaint: phase);
  @override
  void paint(Canvas canvas, Size size) {
    final t = (phase.value / .65).clamp(0.0, 1.0);
    if (t == 0 || t == 1) return;
    final x = -size.width * .5 + size.width * 2 * t;
    final rect = Rect.fromLTWH(x, -size.height, size.width * .35, size.height * 3);
    canvas.save();
    canvas.skew(-.35, 0);
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [
      Colors.transparent, const Color(0xFFFFE9B3).withValues(alpha: .16 * math.sin(math.pi * t)),
      Colors.transparent,
    ]).createShader(rect));
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant _SweepPainter oldDelegate) => oldDelegate.phase != phase;
}

class LobbyLiveIndicator extends StatelessWidget {
  final List<Map<String, dynamic>> tables;
  const LobbyLiveIndicator({super.key, required this.tables});
  @override
  Widget build(BuildContext context) {
    final players = tables.fold<int>(0, (sum, table) => sum +
      ((table['_players'] as List?)?.length ?? 0));
    return SizedBox(height: 20, child: Align(alignment: Alignment.centerLeft,
      child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
        _AmbientCycle(child: Container(width: 6, height: 6,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF7ED79B))),
          builder: (_, phase, child) => FadeTransition(opacity: TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: .5, end: 1.0), weight: 50),
            TweenSequenceItem(tween: Tween(begin: 1.0, end: .5), weight: 50),
          ]).animate(phase.drive(CurveTween(curve: Curves.easeInOut))), child: child)),
        const SizedBox(width: 6),
        Text('Şu an $players oyuncu masalarda', key: const ValueKey('lobby-live-count'),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE1EADD), height: 1.2)),
      ])),
    ));
  }
}

class LobbyTableEntrance extends StatelessWidget {
  final int index;
  final Widget child;
  const LobbyTableEntrance({super.key, required this.index, required this.child});
  @override
  Widget build(BuildContext context) {
    final delay = index.clamp(0, 7) * 40;
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay),
      curve: Interval(delay / (320 + delay), 1, curve: Curves.easeOutCubic),
      child: RepaintBoundary(child: child),
      builder: (_, value, child) => Opacity(opacity: value,
        child: Transform.translate(offset: Offset(0, 8 * (1 - value)), child: child)));
  }
}

class LobbyOpenSeatGlow extends StatelessWidget {
  final bool enabled;
  final Widget child;
  const LobbyOpenSeatGlow({super.key, required this.enabled, required this.child});
  @override
  Widget build(BuildContext context) => !enabled ? child : _AmbientCycle(child: child,
    builder: (_, phase, content) => CustomPaint(
      foregroundPainter: _SeatGlowPainter(phase, enabled), child: content));
}

class _SeatGlowPainter extends CustomPainter {
  final Animation<double> phase;
  final bool enabled;
  _SeatGlowPainter(this.phase, this.enabled) : super(repaint: phase);
  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size,
      const Radius.circular(18)).deflate(2), Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 1
      ..color = const Color(0xFFE6CC91).withValues(alpha: .12 + .23 * math.sin(math.pi * phase.value)));
  }
  @override
  bool shouldRepaint(covariant _SeatGlowPainter oldDelegate) =>
    oldDelegate.phase != phase || oldDelegate.enabled != enabled;
}
