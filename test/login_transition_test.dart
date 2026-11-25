import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/screens/login_screen.dart';
import 'package:okeyix/ui/login_start_scene.dart';
import 'package:okeyix/ui/lobby/lobby_entrance.dart';

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

void main() {
  testWidgets('auth-owned login never pushes a duplicate lobby route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'age_verified': true});
    const uid = '00000000-0000-4000-8000-000000000001';
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'none'})}.${part({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
    await Supabase.initialize(
      url: 'https://login-fixture.invalid',
      anonKey: 'fixture',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'fixture',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': uid,
              'aud': 'authenticated',
              'created_at': '2026-11-25T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final client = Supabase.instance.client;
    final routes = _Routes();
    await tester.binding.setSurfaceSize(const Size(844, 390));
    try {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: StreamBuilder<AuthState>(
            stream: client.auth.onAuthStateChange,
            builder: (_, snapshot) => snapshot.data?.session == null
                ? const LoginScreen(authManagedExternally: true)
                : const Scaffold(body: Text('Authenticated home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(
          () => client.auth.signInWithPassword(
            email: 'fixture@login.invalid',
            password: 'fixture',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Authenticated home'), findsOneWidget);
        expect(routes.pushes, 1);
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      await Supabase.instance.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets(
    'preparation and outgoing scene stay visible without replaying intro',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final nav = GlobalKey<NavigatorState>();
      Widget stillLogin() => LoginStartScene(
        animateIntro: false,
        onApple: () async {},
        onGoogle: () async {},
        onGuest: () async {},
        legal: const SizedBox(),
      );
      await tester.pumpWidget(
        MaterialApp(navigatorKey: nav, home: stillLogin()),
      );
      void expectSettledIntro() {
        final fades = tester.widgetList<FadeTransition>(
          find.descendant(
            of: find.byType(LoginStartScene),
            matching: find.byType(FadeTransition),
          ),
        );
        expect(fades, isNotEmpty);
        for (final fade in fades) {
          expect(fade.opacity.value, 1);
        }
      }

      expectSettledIntro();
      await tester.pump(const Duration(milliseconds: 100));
      expectSettledIntro();
      nav.currentState!.pushReplacement(
        lobbyCinemaRoute(
          login: stillLogin(),
          lobby: const Scaffold(body: Text('Lobby')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expectSettledIntro();
      await tester.pump(const Duration(milliseconds: 150));
      expectSettledIntro();
      await tester.pumpAndSettle();
      expect(find.byType(LoginStartScene), findsNothing);
      expect(find.text('Lobby'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
