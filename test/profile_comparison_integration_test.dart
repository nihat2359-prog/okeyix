// The HTTP transport is already shipped by supabase_flutter; this fake never
// connects to a server and adds no production dependency.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/main.dart' show navigatorKey;
import 'package:okeyix/services/profile_service.dart';

const viewer = '00000000-0000-4000-8000-000000009801';
const opponent = '00000000-0000-4000-8000-000000009802';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? comparedTarget;
  Completer<void>? profileGate;
  Map<String, dynamic> player(String id) => {
    'id': id,
    'username': id == viewer ? 'Me' : 'Opponent',
    'avatar_url': null,
    'league': 'Fixture',
    'wins': 0,
    'losses': 0,
    'normal_wins': 0,
    'okey_wins': 0,
    'double_wins': 0,
    'okey_double_wins': 0,
  };
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"none"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': viewer, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.fixture';
    await Supabase.initialize(
      url: 'https://comparison-fixture.invalid',
      anonKey: 'fixture-only',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      httpClient: MockClient((request) async {
        Object result;
        if (request.url.path.contains('/auth/')) {
          result = {
            'access_token': token,
            'refresh_token': 'fixture',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': viewer,
              'aud': 'authenticated',
              'created_at': '2026-10-20T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            },
          };
        } else if (request.url.path.endsWith(
          '/rpc/okeyix_profile_statistics',
        )) {
          result = {
            ...player(viewer),
            'career_wins': 0,
            'career_losses': 0,
            'previous_wins': 0,
          };
        } else if (request.url.path.endsWith('/rpc/okeyix_compare_player')) {
          comparedTarget =
              (jsonDecode(request.body) as Map)['p_opponent_id'] as String;
          result = {
            'scope': 'head_to_head',
            'left_player': player(viewer),
            'right_player': player(comparedTarget!),
            'left_wins': 0,
            'right_wins': 0,
            'as_of': '2026-10-20T00:00:00Z',
          };
        } else {
          if (profileGate != null) await profileGate!.future;
          result = {
            'username': 'Fixture',
            'avatar_url': null,
            'coins': 100,
            'rating': 1200,
            'wins': 0,
            'losses': 0,
          };
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'fixture',
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
  });

  testWidgets('profile opens before identity requests complete', (tester) async {
    await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey,
      home: const Scaffold()));
    late Future<void> modal;
    await tester.runAsync(() async {
      profileGate = Completer<void>();
      modal = ProfileService.showUserCard({'id': opponent, 'username': 'Immediate'});
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(profileGate!.isCompleted, isFalse);
    expect(find.text('Immediate'), findsOneWidget);
    expect(find.byTooltip('Kapat'), findsOneWidget);
    await tester.runAsync(() async {
      profileGate!.complete();
      await Future<void>.delayed(Duration.zero);
    });
    profileGate = null;
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => modal);
    expect(tester.takeException(), isNull);
  });

  for (final self in [true, false]) {
    testWidgets(
      self
          ? 'own profile never offers comparison'
          : 'other profile navigates with authenticated viewer and exact opponent',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
        );
        late Future<void> modal;
        await tester.runAsync(() async {
          modal = ProfileService.showUserCard({
            'id': self ? viewer : opponent,
            'username': 'Fixture',
          });
          unawaited(modal);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        if (self) {
          expect(find.text('Karşılaştır'), findsNothing);
          expect(find.text('Düzenle'), findsOneWidget);
          await tester.tap(find.byTooltip('Kapat'));
        } else {
          expect(find.text('Karşılaştır'), findsOneWidget);
          expect(find.text('Ekle'), findsOneWidget);
          await tester.tap(find.text('Karşılaştır'));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
          expect(comparedTarget, opponent);
          expect(find.text('Henüz birbirinize karşı tamamlanmış el yok'), findsOneWidget);
          await tester.tap(find.byTooltip('Kapat'));
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() => modal);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
