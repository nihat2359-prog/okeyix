import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Isolated, offline visual prototype. No auth, wallet or game services.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});
  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen>
    with WidgetsBindingObserver {
  WebViewController? _web;
  Timer? _timeout;
  bool _ready = false, _failed = false, _champion = false;
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_supported) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final web = WebViewController();
      _web = web;
      await web.setJavaScriptMode(JavaScriptMode.unrestricted);
      await web.setBackgroundColor(const Color(0xFF152B35));
      await web.addJavaScriptChannel(
        'Journey',
        onMessageReceived: (message) {
          if (!mounted) return;
          if (message.message == 'ready') {
            _timeout?.cancel();
            setState(() {
              _ready = true;
              _failed = false;
            });
          } else if (message.message == 'champion') {
            setState(() => _champion = true);
          } else if (message.message == 'error') {
            _timeout?.cancel();
            setState(() => _failed = true);
          }
        },
      );
      await web.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              request.url.startsWith('file:') || request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => _failed = true);
            }
          },
        ),
      );
      if (!mounted) return;
      setState(() {});
      _timeout = Timer(const Duration(seconds: 25), () {
        if (mounted && !_ready) setState(() => _failed = true);
      });
      await web.loadFlutterAsset('assets/journey/index.html');
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _command(String command) async {
    if (!_ready) return;
    try {
      await _web?.runJavaScript(command);
    } catch (_) {
      /* route closing */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      _command('window.journey?.pause(${state != AppLifecycleState.resumed})'),
    );
  }

  @override
  void dispose() {
    _timeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_command('window.journey?.dispose()'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF152B35),
    body: Stack(
      children: [
        if (_web != null && !_failed)
          Positioned.fill(child: WebViewWidget(controller: _web!)),
        if (!_supported || _failed || !_ready)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_supported && !_failed)
                    const CircularProgressIndicator(color: Color(0xFFE8CC91)),
                  const SizedBox(height: 12),
                  Text(
                    !_supported
                        ? 'Yolculuk 3D prototipini Android veya iOS uygulamasında açın.'
                        : _failed
                        ? '3D sahne yüklenemedi. Güncel bir sistem WebView ile tekrar deneyin.'
                        : 'Boğaz Kahvesi hazırlanıyor…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFF0D9A7)),
                  ),
                ],
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _glass(
                  IconButton(
                    tooltip: 'Lobiye dön',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Color(0xFFE8CC91),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _glass(
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OKEYIX  /  YOLCULUK',
                              style: TextStyle(
                                color: Color(0xFFE8CC91),
                                fontSize: 10,
                                letterSpacing: 2,
                              ),
                            ),
                            Text(
                              'Boğaz Kahvesi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _glass(
                  IconButton(
                    tooltip: 'Kamerayı sıfırla',
                    onPressed: () => _command('window.journey?.reset()'),
                    icon: const Icon(
                      Icons.explore_outlined,
                      color: Color(0xFFE8CC91),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_ready && !_champion)
          Positioned(
            bottom: 12,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: SafeArea(
                top: false,
                child: Text(
                  'Keşfetmek için sürükle · Yakınlaşmak için iki parmak · Kafeye veya ustaya dokun',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
              ),
            ),
          ),
        if (_champion)
          Positioned(
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width - 32,
                ),
                child: _glass(
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'BOĞAZ KAHVESİ',
                              style: TextStyle(
                                color: Color(0xFFE8CC91),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 24),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Kapat',
                              onPressed: () =>
                                  setState(() => _champion = false),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'Şampiyon: Okey Ustası',
                          style: TextStyle(color: Colors.white, fontSize: 17),
                        ),
                        const Text(
                          'Bot tarafından korunuyor',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Bu bir keşif prototipi. Meydan okuma henüz açılmadı.',
                                  ),
                                ),
                              ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE8CC91),
                            foregroundColor: const Color(0xFF152B35),
                          ),
                          child: const Text('Meydan Oku'),
                        ),
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

  Widget _glass(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xD51A252A),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0x668F794D)),
    ),
    child: child,
  );
}
