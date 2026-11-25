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
    final error = _failure ?? widget.error;
    final busy = _active != null || widget.loadingGuest;
    final fade = _intro.drive(CurveTween(curve: Curves.easeOutCubic));
    return Scaffold(
      backgroundColor: const Color(0xFF081B15),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_lounge.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final short = bounds.maxHeight < 330;
                final gap = short ? 10.0 : 14.0;
                final buttonHeight = (bounds.maxHeight * .13).clamp(44.0, 54.0);
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: bounds.maxWidth * .035,
                    vertical: short ? 8 : 18,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Align(
                          alignment: const Alignment(.25, -.64),
                          child: FractionallySizedBox(
                            widthFactor: .77,
                            child: FadeTransition(
                              opacity: fade,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/images/logo/okeyix_logo.png',
                                    height: bounds.maxHeight * .20,
                                    fit: BoxFit.contain,
                                    semanticLabel: 'Okeyix',
                                  ),
                                  const SizedBox(height: 5),
                                  const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Adil Dağıtım · Gerçek Rekabet',
                                      style: TextStyle(
                                        color: Color(0xFFE7CFA4),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: .5,
                                        shadows: [
                                          Shadow(
                                            blurRadius: 6,
                                            color: Colors.black,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        margin: EdgeInsets.symmetric(
                          vertical: bounds.maxHeight * .06,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x00D9C399),
                              Color(0x88D9C399),
                              Color(0x00D9C399),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: bounds.maxWidth * .035,
                          ),
                          child: FadeTransition(
                            opacity: fade,
                            child: Center(
                              child: SizedBox(
                                width: math.min(bounds.maxWidth, 310),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final id in [
                                      'apple',
                                      'google',
                                      'guest',
                                    ]) ...[
                                      if (id != 'apple') SizedBox(height: gap),
                                      SizedBox(
                                        height: buttonHeight,
                                        child: _StartButton(
                                          id: id,
                                          label: switch (id) {
                                            'apple' => 'Apple ile gir',
                                            'google' => 'Google ile gir',
                                            _ => 'Misafir olarak devam et',
                                          },
                                          loading:
                                              _active == id ||
                                              (id == 'guest' &&
                                                  widget.loadingGuest),
                                          enabled: !busy,
                                          onPressed: () =>
                                              _signIn(id, switch (id) {
                                                'apple' => widget.onApple,
                                                'google' => widget.onGoogle,
                                                _ => widget.onGuest,
                                              }),
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: gap),
                                    SizedBox(
                                      height: 30,
                                      child: Center(child: widget.legal),
                                    ),
                                    if (error != null) ...[
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        height: short ? 30 : 40,
                                        child: SingleChildScrollView(
                                          child: Semantics(
                                            liveRegion: true,
                                            child: Text(
                                              error,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Color(0xFFFFC9B9),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
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
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  final String id, label;
  final bool loading, enabled;
  final VoidCallback onPressed;
  const _StartButton({
    required this.id,
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final guest = id == 'guest';
    final foreground = guest
        ? const Color(0xFFEAD7B3)
        : const Color(0xFF211B13);
    final radius = BorderRadius.circular(22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: guest
              ? const [Color(0xBB293A2C), Color(0xBB0E2019)]
              : const [Color(0xFFF6E5C5), Color(0xFFD8BC91)],
        ),
        border: Border.all(
          color: guest ? const Color(0xFFB7A583) : const Color(0xFFE4CDA6),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextButton(
        key: ValueKey('login-$id'),
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          disabledForegroundColor: foreground.withValues(alpha: .65),
          shape: RoundedRectangleBorder(borderRadius: radius),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 10),
              ] else if (!guest) ...[
                if (id == 'apple')
                  Icon(Icons.apple, size: 27, color: foreground)
                else
                  Image.asset(
                    'assets/images/google.png',
                    width: 23,
                    height: 23,
                    excludeFromSemantics: true,
                  ),
                const SizedBox(width: 14),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: guest ? 13 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
