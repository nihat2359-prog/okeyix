import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Presentation only: providers, redirects and account creation stay in LoginScreen.
class LoginStartScene extends StatefulWidget {
  final Future<void> Function() onApple, onGoogle, onGuest;
  final bool loadingGuest;
  final String? error;
  final Widget legal;
  const LoginStartScene({
    super.key,
    required this.onApple,
    required this.onGoogle,
    required this.onGuest,
    required this.legal,
    this.loadingGuest = false,
    this.error,
  });

  @override
  State<LoginStartScene> createState() => _LoginStartSceneState();
}

class _LoginStartSceneState extends State<LoginStartScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  String? _active;
  String? _failure;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    }
  }

  Future<void> _signIn(
    String provider,
    Future<void> Function() callback,
  ) async {
    if (_active != null || widget.loadingGuest) return;
    setState(() {
      _active = provider;
      _failure = null;
    });
    try {
      await callback();
    } catch (_) {
      if (mounted) {
        setState(() => _failure = 'Bağlantı kurulamadı. Lütfen tekrar dene.');
      }
    } finally {
      if (mounted) setState(() => _active = null);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final logo = _intro.drive(CurveTween(curve: Curves.easeOutCubic));
    final controls = _intro.drive(
      CurveTween(curve: const Interval(.15, 1, curve: Curves.easeOutCubic)),
    );
    final error = _failure ?? widget.error;
    final busy = _active != null || widget.loadingGuest;
    return Scaffold(
      backgroundColor: const Color(0xFF06110F),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/table.png',
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x66081214),
                    Color(0x440A1918),
                    Color(0xE6081218),
                  ],
                  stops: [0, .40, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final compact = bounds.maxHeight < 370;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: bounds.maxWidth < 700 ? 20 : 36,
                    vertical: compact ? 8 : 24,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 6,
                              child: FadeTransition(
                                opacity: logo,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: .94,
                                    end: 1,
                                  ).animate(logo),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Image.asset(
                                            'assets/images/logo/okeyix_log_1000.png',
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                            semanticLabel: 'Okeyix',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'ADİL DAĞITIM · GERÇEK REKABET',
                                          style: TextStyle(
                                            color: Color(0xFFE6D3A4),
                                            fontSize: 11,
                                            letterSpacing: 1.1,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const Expanded(
                                        flex: 6,
                                        child: RepaintBoundary(
                                          child: CustomPaint(
                                            painter: _OpeningTiles(),
                                            child: SizedBox.expand(),
                                          ),
                                        ),
                                      ),
                                      const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'Her el yeni bir hikâye.',
                                          style: TextStyle(
                                            color: Color(0xFFCFD6CC),
                                            fontSize: 11,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: compact ? 24 : 48),
                            Expanded(
                              flex: 5,
                              child: FadeTransition(
                                opacity: controls,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(.04, 0),
                                    end: Offset.zero,
                                  ).animate(controls),
                                  child: LayoutBuilder(
                                    builder: (context, area) => Align(
                                      alignment: Alignment.center,
                                      child: SizedBox(
                                        width: math.min(area.maxWidth, 310),
                                        height: math.min(
                                          area.maxHeight,
                                          error == null ? 210 : 240,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const SizedBox(
                                              height: 22,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  'Sıradaki el senin.',
                                                  style: TextStyle(
                                                    color: Color(0xFFE0D1AE),
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: .4,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Expanded(
                                              child: Column(
                                                children: [
                                                  Expanded(
                                                    child: _StartButton(
                                                      id: 'apple',
                                                      label:
                                                          'Apple ile devam et',
                                                      icon: const Icon(
                                                        Icons.apple,
                                                        size: 23,
                                                        color: Colors.white,
                                                      ),
                                                      loading:
                                                          _active == 'apple',
                                                      enabled: !busy,
                                                      reduced: reduced,
                                                      onPressed: () => _signIn(
                                                        'apple',
                                                        widget.onApple,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Expanded(
                                                    child: _StartButton(
                                                      id: 'google',
                                                      label:
                                                          'Google ile devam et',
                                                      icon: Image.asset(
                                                        'assets/images/google.png',
                                                        width: 20,
                                                        height: 20,
                                                        excludeFromSemantics:
                                                            true,
                                                      ),
                                                      loading:
                                                          _active == 'google',
                                                      enabled: !busy,
                                                      reduced: reduced,
                                                      onPressed: () => _signIn(
                                                        'google',
                                                        widget.onGoogle,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  Expanded(
                                                    flex: 1,
                                                    child: _StartButton(
                                                      id: 'guest',
                                                      label: 'Hızlı Başla',
                                                      icon: const Icon(
                                                        Icons
                                                            .play_arrow_rounded,
                                                        size: 24,
                                                        color: Color(
                                                          0xFF30220D,
                                                        ),
                                                      ),
                                                      loading:
                                                          _active == 'guest' ||
                                                          widget.loadingGuest,
                                                      enabled: !busy,
                                                      reduced: reduced,
                                                      onPressed: () => _signIn(
                                                        'guest',
                                                        widget.onGuest,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            if (error != null)
                                              SizedBox(
                                                height: 30,
                                                child: SingleChildScrollView(
                                                  child: Semantics(
                                                    liveRegion: true,
                                                    child: Text(
                                                      error,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFFFFC9B9,
                                                        ),
                                                        fontSize: 12,
                                                        height: 1.2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height:
                            MediaQuery.textScalerOf(context).scale(12) * 3 + 8,
                        child: Transform.translate(
                          offset: const Offset(0, -4),
                          child: Center(child: widget.legal),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatefulWidget {
  final String id, label;
  final Widget icon;
  final bool loading, enabled, reduced;
  final VoidCallback onPressed;
  const _StartButton({
    required this.id,
    required this.label,
    required this.icon,
    required this.loading,
    required this.enabled,
    required this.reduced,
    required this.onPressed,
  });
  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  bool _pressed = false;
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final guest = widget.id == 'guest';
    final google = widget.id == 'google';
    final foreground = guest || google ? const Color(0xFF252725) : Colors.white;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (_) {
          if (widget.enabled) setState(() => _pressed = true);
        },
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? .98 : 1,
          duration: widget.reduced
              ? Duration.zero
              : const Duration(milliseconds: 100),
          child: CustomPaint(
            painter: _ButtonMount(guest),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(guest ? 12 : 8),
                color: guest
                    ? null
                    : google
                    ? const Color(0xFFF2F2F2)
                    : const Color(0xFF080909),
                gradient: guest
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFE8A7),
                          Color(0xFFDDB555),
                          Color(0xFFB9832E),
                        ],
                      )
                    : null,
                border: Border.all(
                  color: _hover && widget.enabled
                      ? const Color(0xFFFFE5A2)
                      : guest
                      ? const Color(0xFFF2D28B)
                      : const Color(0xFF62675F),
                ),
                boxShadow: [
                  BoxShadow(
                    color: guest
                        ? const Color(0xFF63441D)
                        : const Color(0xFF020706),
                    offset: Offset(0, _pressed ? 1 : 2),
                  ),
                  const BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: TextButton(
                key: ValueKey('login-${widget.id}'),
                onPressed: widget.enabled ? widget.onPressed : null,
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  disabledForegroundColor: foreground.withValues(alpha: .6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: SizedBox.expand(
                  child: Row(
                    children: [
                      widget.loading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: foreground,
                              ),
                            )
                          : widget.icon,
                      const SizedBox(width: 12),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: Text(
                            widget.loading ? 'Bağlanıyor...' : widget.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: guest
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (guest)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF38280D),
                          ),
                        ),
                    ],
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

class _ButtonMount extends CustomPainter {
  final bool primary;
  const _ButtonMount(this.primary);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(1.25);
    final rim = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rim.shift(const Offset(0, 1.5)),
      Paint()..color = const Color(0xAA020605),
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: primary
              ? const [Color(0xFFB69C60), Color(0xFF463C25)]
              : const [Color(0xFF657366), Color(0xFF182820)],
        ).createShader(rect),
    );
    final paint = Paint()
      ..color = primary ? const Color(0xFFEDD49C) : const Color(0xFF98A591);
    for (final x in [rect.left + 5, rect.right - 5]) {
      canvas.drawLine(
        Offset(x, size.height / 2 - 5),
        Offset(x, size.height / 2 + 5),
        paint..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ButtonMount oldDelegate) =>
      oldDelegate.primary != primary;
}

class _OpeningTiles extends CustomPainter {
  const _OpeningTiles();
  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width / 310, size.height / 150);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);
    final shadow = Paint()
      ..color = const Color(0x99020906)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(const Rect.fromLTWH(-130, 42, 260, 23), shadow);
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate([-69.0, 0.0, 70.0][i], [8.0, -9.0, 10.0][i]);
      canvas.rotate([-.19, .035, .22][i]);
      canvas.scale(1.0, .91);
      canvas.skew(-.035, 0);
      const rect = Rect.fromLTWH(-34, -54, 68, 104);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(const Offset(4, 9)),
          const Radius.circular(8),
        ),
        Paint()
          ..color = const Color(0x99020806)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(const Offset(1, 5)),
          const Radius.circular(7),
        ),
        Paint()..color = const Color(0xCC07110B),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(const Offset(0, 6)),
          const Radius.circular(7),
        ),
        Paint()..color = const Color(0xFF9D814C),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(7)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFFEC), Color(0xFFDCCCAA)],
          ).createShader(rect),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x998D794F),
      );
      final color = [
        const Color(0xFFB62D23),
        const Color(0xFF222B26),
        const Color(0xFF25528B),
      ][i];
      final text = TextPainter(
        text: TextSpan(
          text: i == 2 ? '12' : '13',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(-text.width / 2, -31));
      canvas.drawCircle(const Offset(0, 25), 5, Paint()..color = color);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OpeningTiles oldDelegate) => false;
}
