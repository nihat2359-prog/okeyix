import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class JourneyLocation {
  final String level, title;
  final String? venue, district, cityName;
  final bool transitioning;
  const JourneyLocation({
    this.level = 'turkey',
    this.title = 'Türkiye',
    this.venue,
    this.district,
    this.cityName,
    this.transitioning = false,
  });
  static JourneyLocation? parse(String message) {
    if (!message.startsWith('state:')) return null;
    try {
      final data = jsonDecode(message.substring(6));
      if (data is! Map ||
          !['turkey', 'city', 'place'].contains(data['level'])) {
        return null;
      }
      if (data['title'] is! String || (data['title'] as String).length > 60) {
        return null;
      }
      if (data['level'] == 'place' &&
          ![
            'kiz',
            'galata',
            'ortakoy',
            'loti',
            'haydarpasa',
            'hisar',
          ].contains(data['venue'])) {
        return null;
      }
      return JourneyLocation(
        level: data['level'],
        title: data['title'],
        venue: data['venue'] as String?,
        district: data['district'] as String?,
        cityName: data['cityName'] as String?,
        transitioning: data['transitioning'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Offline 3D world; never reads auth, wallet, game or statistics services.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});
  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen>
    with WidgetsBindingObserver {
  static const _gold = Color(0xFFE8CC91);
  WebViewController? _web;
  Timer? _timeout;
  bool _ready = false, _failed = false, _demo = false, _demoPanel = false;
  int _progress = 0;
  JourneyLocation _location = const JourneyLocation();
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _canExit =>
      !_demo && _location.level == 'turkey' && !_location.transitioning;
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
      await web.setBackgroundColor(const Color(0xFF153845));
      await web.addJavaScriptChannel(
        'Journey',
        onMessageReceived: (message) {
          if (!mounted) return;
          final value = message.message,
              location = JourneyLocation.parse(message.message);
          if (value == 'ready') {
            _timeout?.cancel();
            setState(() {
              _ready = true;
              _failed = false;
            });
          } else if (value.startsWith('progress:')) {
            final progress = int.tryParse(value.substring(9));
            if (!_ready &&
                progress != null &&
                progress >= 0 &&
                progress <= 100) {
              setState(() => _progress = progress);
            }
          } else if (value == 'error') {
            _timeout?.cancel();
            setState(() => _failed = true);
          } else if (value == 'exit' && _canExit) {
            Navigator.of(context).pop();
          } else if (value == 'champion' && _demo) {
            setState(() => _demoPanel = true);
          } else if (location != null && !_demo) {
            setState(() => _location = location);
          } else if (value.startsWith('notice:')) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(value.substring(7))));
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
      await _open(false);
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

  Future<void> _open(bool demo) async {
    await _command('window.journey?.dispose()');
    if (!mounted) return;
    setState(() {
      _demo = demo;
      _ready = _failed = _demoPanel = false;
      _progress = 0;
      _location = const JourneyLocation();
    });
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 90), () {
      if (mounted && !_ready) setState(() => _failed = true);
    });
    try {
      await _web?.loadFlutterAsset(
        'assets/journey/${demo ? 'demo' : 'maiden'}.html',
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _back() {
    if (_location.transitioning && !_failed) return;
    if (_demo) {
      unawaited(_open(false));
    } else if (_ready && !_failed) {
      unawaited(_command('window.journey?.back()'));
    } else {
      Navigator.of(context).pop();
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

  void _sources() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xF01D252E),
      title: const Text(
        'Yolculuk · Veri kaynakları',
        style: TextStyle(color: _gold),
      ),
      content: const SingleChildScrollView(
        child: Text(
          'Kız Kulesi: “Maiden’s Tower”, oblo.3d — CC BY 4.0.\n'
          'sketchfab.com/3d-models/maidens-tower-398a52c016914328bf88e273823db6c1\n'
          'sketchfab.com/oblo.3d · creativecommons.org/licenses/by/4.0/\n'
          'Modelde statik parçalar birleştirildi, dokular küçültüldü; düz deniz kaldırıldı. '
          'Uzak kıyı ve tekneler temsili çevre geometrisidir. Three.js: MIT.\n\n'
          'Arşiv harita prototipi kaynakları:\n'
          'Türkiye sınırı: Natural Earth 1:10m (kamu malı).\n'
          'Yükselti: Mapzen Terrarium; USGS / NOAA ve Copernicus EU-DEM kaynakları. Türkiye görünümünde yükseklik 12× abartılır.\n'
          'İl konumları: Open Admin Data, CC BY 4.0; Türkçe adlar düzenlendi. İstanbul giriş noktası şehir merkezine alındı.\n\n'
          'İstanbul kıyısı ölçeğe bağlı sadeleştirilmiştir. Haliç girintisi elle yaklaşık çizilmiştir; ölçüm verisi değildir. '
          'Yapılar özgün, yaklaşık mimari modellerdir; sıradan binalar temsili yerleşim dokusudur.\n\n'
          'naturalearthdata.com · github.com/tilezen/joerd\n'
          'github.com/open-admin-data/turkey-administrative-divisions\n'
          'creativecommons.org/licenses/by/4.0\n'
          'Tam atıflar: assets/journey/SOURCES.md',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat', style: TextStyle(color: _gold)),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canExit || _failed || !_ready,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: Scaffold(
      backgroundColor: const Color(0xFF153845),
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
                      const CircularProgressIndicator(color: _gold),
                    const SizedBox(height: 12),
                    Text(
                      !_supported
                          ? 'Yolculuk 3D dünyasını Android veya iOS uygulamasında açın.'
                          : _failed
                          ? '3D sahne yüklenemedi. Güncel bir sistem WebView ile tekrar deneyin.'
                          : '${_demo ? 'Boğaz Kahvesi' : 'Kız Kulesi'} hazırlanıyor…${_progress > 0 ? ' %$_progress' : ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _gold),
                    ),
                    if (_supported && _failed)
                      TextButton(
                        onPressed: () => _open(_demo),
                        child: const Text(
                          'Tekrar dene',
                          style: TextStyle(color: _gold),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _glass(
                    IconButton(
                      tooltip: _canExit ? 'Lobiye dön' : 'Önceki görünüm',
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back_rounded, color: _gold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _glass(
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'OKEYIX  /  YOLCULUK',
                                style: TextStyle(
                                  color: _gold,
                                  fontSize: 9,
                                  letterSpacing: 1.6,
                                ),
                              ),
                              Text(
                                _demo ? 'Boğaz Kahvesi' : 'Kız Kulesi',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!_demo && _location.level == 'turkey') ...[
                    _glass(
                      IconButton(
                        tooltip: 'Boğaz Kahvesi demosu',
                        onPressed: _ready && !_location.transitioning
                            ? () => _open(true)
                            : null,
                        icon: const Icon(
                          Icons.local_cafe_outlined,
                          color: _gold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _glass(
                    IconButton(
                      tooltip: 'Kamerayı sıfırla',
                      onPressed: () => _command('window.journey?.reset()'),
                      icon: const Icon(Icons.explore_outlined, color: _gold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 6,
            child: SafeArea(
              top: false,
              child: TextButton.icon(
                onPressed: _sources,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE3DBC9),
                  backgroundColor: const Color(0xAA152A30),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 9),
                ),
                icon: const Icon(Icons.info_outline, size: 13),
                label: const Text('3D varlıklar · Kaynaklar'),
              ),
            ),
          ),
          if ((_location.level == 'place' &&
                  !_location.transitioning &&
                  _ready) ||
              _demoPanel)
            Positioned(
              right: 12,
              bottom: 10,
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .47,
                  ),
                  child: _glass(
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _demo ? 'Boğaz Kahvesi' : _location.title,
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${_demo ? 'İstanbul' : _location.cityName ?? 'Şehir'} · ${_demo ? 'Keşif demosu' : _location.district}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Şampiyon: Henüz belirlenmedi',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                          const Text(
                            'Bot koruması · Prototip gösterimi',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 6),
                          FilledButton(
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Bu bir görsel prototip. Gerçek meydan okuma henüz açılmadı.',
                                    ),
                                  ),
                                ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
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
    ),
  );
  Widget _glass(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xD51A252A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0x668F794D)),
    ),
    child: child,
  );
}
