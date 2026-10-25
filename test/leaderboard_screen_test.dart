// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/screens/leaderboard_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://ranking-fixture.invalid', anonKey: 'fixture',
      debug: false,
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage(),
        autoRefreshToken: false, detectSessionInUri: false),
      httpClient: MockClient((request) async => http.Response(jsonEncode(
        List.generate(15, (i) => {'id': 'player-$i', 'username': 'Oyuncu $i',
          'rating': 5000 - i * 100, 'coins': 100000 - i * 100,
          'total_earned': 10000 - i * 10})), 200,
        headers: {'content-type': 'application/json'}, request: request)),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('ranking $size fits landscape and switches ranking tabs', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(builder: (_, child) => MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(1.3),
          padding: const EdgeInsets.fromLTRB(30, 0, 20, 12)), child: child!),
        home: const LeaderboardScreen()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Oyuncu 0'), findsOneWidget);
      expect(find.text('Oyuncu 3'), findsOneWidget);
      await tester.ensureVisible(find.text('Zenginler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zenginler'));
      await tester.pumpAndSettle();
      expect(find.text('COİN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
