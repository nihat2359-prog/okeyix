import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/screens/journey_screen.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _Platform extends WebViewPlatform {
  late _Controller controller;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFF153845));
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  late JavaScriptChannelParams channel;
  final commands = <String>[], assets = <String>[];
  String level = 'turkey';
  void message(String value) =>
      channel.onMessageReceived(JavaScriptMessage(message: value));
  void go(String to) {
    level = to;
    message(
      'state:${jsonEncode({'level': to, 'title': to == 'turkey'
          ? 'Türkiye'
          : to == 'city'
          ? 'İstanbul'
          : 'Kız Kulesi', 'venue': to == 'place' ? 'kiz' : null, 'district': to == 'place' ? 'Üsküdar' : null, 'transitioning': false})}',
    );
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {}
  @override
  Future<void> loadFlutterAsset(String key) async {
    assets.add(key);
    if (key.endsWith('index.html')) go('turkey');
    message('ready');
  }

  @override
  Future<void> runJavaScript(String script) async {
    commands.add(script);
    if (script.contains('.back()')) {
      if (level == 'place') {
        go('city');
      } else if (level == 'city') {
        go('turkey');
      } else {
        message('exit');
      }
    }
  }
}

void main() {
  test('scene messages reject malformed levels and unknown place IDs', () {
    expect(JourneyLocation.parse('state:{broken'), isNull);
    expect(
      JourneyLocation.parse('state:{"level":"wallet","title":"X"}'),
      isNull,
    );
    expect(
      JourneyLocation.parse(
        'state:{"level":"place","title":"X","venue":"other"}',
      ),
      isNull,
    );
    expect(
      JourneyLocation.parse(
        'state:{"level":"place","title":"Kız Kulesi","venue":"kiz","district":"Üsküdar"}',
      )?.venue,
      'kiz',
    );
  });
  for (final size in [const Size(480, 270), const Size(844, 390)]) {
    testWidgets(
      'native bridge back chain, source dialog and demo at $size',
      (tester) async {
        final platform = _Platform();
        WebViewPlatform.instance = platform;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const JourneyScreen(),
                    ),
                  ),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Aç'));
        await tester.pumpAndSettle();
        expect(find.text('Türkiye'), findsOneWidget);
        final controller = platform.controller;
        expect(controller.assets.last, 'assets/journey/index.html');
        await tester.tap(find.text('Natural Earth · DEM · Veri kaynakları'));
        await tester.pumpAndSettle();
        expect(find.text('Yolculuk · Veri kaynakları'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Kapat'));
        await tester.pumpAndSettle();
        controller.go('city');
        controller.go('place');
        await tester.pumpAndSettle();
        expect(find.text('Şampiyon: Henüz belirlenmedi'), findsOneWidget);
        final challenge = find.text('Meydan Oku');
        expect(challenge, findsOneWidget);
        expect(
          tester.getRect(challenge).bottom,
          lessThanOrEqualTo(size.height),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Önceki görünüm'));
        await tester.pumpAndSettle();
        expect(controller.level, 'city');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(controller.level, 'turkey');
        await tester.tap(find.byTooltip('Boğaz Kahvesi demosu'));
        await tester.pumpAndSettle();
        expect(controller.assets.last, 'assets/journey/demo.html');
        controller.message('champion');
        await tester.pumpAndSettle();
        expect(find.text('Meydan Oku'), findsOneWidget);
        await tester.tap(find.byTooltip('Önceki görünüm'));
        await tester.pumpAndSettle();
        expect(controller.assets.last, 'assets/journey/index.html');
        await tester.tap(find.byTooltip('Lobiye dön'));
        await tester.pumpAndSettle();
        expect(find.byType(JourneyScreen), findsNothing);
        expect(
          controller.commands.where((s) => s.contains('.dispose()')).length,
          greaterThanOrEqualTo(3),
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
