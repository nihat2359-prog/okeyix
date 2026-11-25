// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/lobby_data_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LobbyDataCache.initialize();
    prefs = await SharedPreferences.getInstance();
  });
  setUp(() async => prefs.clear());

  test('profile survives storage and is isolated by account', () async {
    await LobbyDataCache.saveProfile(
      'alice',
      {'id': 'alice', 'username': 'Alice'},
      {'coins': 72400, 'rating': 7800},
    );
    expect(LobbyDataCache.profile('alice')!['profile']['coins'], 72400);
    expect(LobbyDataCache.profile('alice')!['profile']['rating'], 7800);
    expect(LobbyDataCache.profile('alice')!['row']['username'], 'Alice');
    expect(LobbyDataCache.profile('bob'), isNull);
    expect(
      jsonDecode(prefs.getString('lobby.profile.v1.alice')!)['row']['id'],
      'alice',
    );
  });

  test('corrupt cache falls back without inventing profile values', () async {
    await prefs.setString('lobby.profile.v1.alice', '{broken');
    await prefs.setString('lobby.leagues.v1', '{}');
    expect(LobbyDataCache.profile('alice'), isNull);
    expect(LobbyDataCache.leagues, isEmpty);
  });

  test(
    'parallel reads release entry after 1.2 seconds and cache late results',
    () async {
      final gate = Completer<void>();
      final calls = <String>[];
      final client = SupabaseClient(
        'https://lobby-cache.invalid',
        'fixture',
        httpClient: MockClient((request) async {
          final table = request.url.pathSegments.last;
          calls.add(table);
          await gate.future;
          final data = switch (table) {
            'users' => [
              {'id': 'alice', 'username': 'Alice'},
            ],
            'profiles' => [
              {'coins': 72400, 'rating': 7800},
            ],
            _ => List.generate(5, (i) => {'id': 'l$i', 'display_order': i}),
          };
          return http.Response(
            jsonEncode(data),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final clock = Stopwatch()..start();
      final prepared = LobbyDataCache.prepare(client, 'alice');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls.toSet(), {'users', 'profiles', 'leagues'});
      // Lobby reads join these requests instead of sending duplicates.
      final profile = LobbyDataCache.refreshProfile(client, 'alice');
      final leagues = LobbyDataCache.refreshLeagues(client);
      await prepared;
      expect(clock.elapsedMilliseconds, inInclusiveRange(1150, 1800));
      expect(gate.isCompleted, isFalse);
      expect(calls.length, 3);
      gate.complete();
      await Future.wait<dynamic>([profile, leagues]);
      expect(LobbyDataCache.profile('alice')!['profile']['coins'], 72400);
      expect(LobbyDataCache.leagues.length, 5);
      await client.dispose();
    },
  );

  test('failed refresh keeps the last profile and leagues', () async {
    await LobbyDataCache.saveProfile(
      'alice',
      {'id': 'alice', 'username': 'Alice'},
      {'coins': 72400, 'rating': 7800},
    );
    await prefs.setString('lobby.leagues.v1', '[{"id":"cached"}]');
    final client = SupabaseClient(
      'https://lobby-cache.invalid',
      'fixture',
      httpClient: MockClient((_) async => http.Response('{}', 400)),
    );
    await LobbyDataCache.prepare(client, 'alice');
    expect(LobbyDataCache.profile('alice')!['profile']['coins'], 72400);
    expect(LobbyDataCache.leagues.single['id'], 'cached');
    await client.dispose();
  });
}
