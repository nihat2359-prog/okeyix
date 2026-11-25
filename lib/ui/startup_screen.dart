import 'package:flutter/material.dart';

typedef StartupProgress = void Function(double progress, String message);

/// Keeps the app's authenticated services unmounted until startup succeeds.
class StartupHost extends StatefulWidget {
  final Future<void> Function(BuildContext context, StartupProgress report)
  initialize;
  final WidgetBuilder ready;

  const StartupHost({super.key, required this.initialize, required this.ready});

  @override
  State<StartupHost> createState() => _StartupHostState();
}

class _StartupHostState extends State<StartupHost> {
  double _progress = 0;
  String _message = 'Oyun masası hazırlanıyor…';
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    setState(() {
      _failed = false;
      _progress = 0;
      _message = 'Oyun masası hazırlanıyor…';
    });
    try {
      await widget.initialize(context, (progress, message) {
        if (!mounted) return;
        setState(() {
          _progress = progress.clamp(_progress, 1.0);
          _message = message;
        });
      });
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.ready(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Montserrat'),
      home: StartupScreen(
        progress: _progress,
        message: _message,
        onRetry: _failed ? _start : null,
      ),
    );
  }
}

class StartupScreen extends StatelessWidget {
  final double progress;
  final String message;
  final VoidCallback? onRetry;

  const StartupScreen({
    super.key,
    required this.progress,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: const Color(0xFF100E0B),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_lounge.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x0008110D), Color(0xCC08110D)],
                stops: [.35, 1],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final compact = bounds.maxHeight < 330;
                return Row(
                  children: [
                    const Spacer(flex: 5),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          bounds.maxWidth * .055,
                          12,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Image.asset(
                                'assets/images/logo/okeyix_logo.png',
                                height: bounds.maxHeight * .25,
                                fit: BoxFit.contain,
                                semanticLabel: 'Okeyix',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'Adil Dağıtım · Gerçek Rekabet',
                                style: TextStyle(
                                  color: Color(0xFFE7CFA4),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: .5,
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 24 : 38),
                            Semantics(
                              label: 'Yükleme ilerlemesi',
                              value: '%${(value * 100).round()}',
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0, end: value),
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 300),
                                builder: (context, animated, _) => Container(
                                  height: 10,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCC081A13),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0xAAAE9060),
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x66000000),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: animated,
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Color(0xFFA97834),
                                                Color(0xFFE6C47F),
                                                Color(0xFFFFE9B6),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    onRetry == null
                                        ? message
                                        : 'Bağlantı kurulamadı.',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFE7D9BC),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '%${(value * 100).round()}',
                                  style: const TextStyle(
                                    color: Color(0xFFE7C68B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (onRetry != null) ...[
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: onRetry,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFF3DFB8),
                                  minimumSize: const Size(140, 44),
                                  side: const BorderSide(
                                    color: Color(0xFFAE9060),
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                child: const Text('Tekrar dene'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
