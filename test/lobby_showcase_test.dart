import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/core/lobby_table_presentation.dart';
import 'package:okeyix/services/ready_table_service.dart';
import 'package:okeyix/ui/lobby/lobby_table_listing_card.dart';

Map<String, dynamic> row(String id, {bool fake = false, bool human = false,
  String status = 'waiting', int seats = 1}) => {
  'id': id, 'is_fake': fake, 'status': status, 'max_players': 2,
  'entry_coin': 1000, 'spectators_enabled': false,
  '_players': List.generate(seats, (i) => {
    'seat_index': i, 'user_id': '$id-$i', 'username': i == 0 ? 'Emre K.' : 'Selin Y.',
    'is_bot': !human,
  }),
};

void main() {
  test('joinable seats precede real games and then displays', () {
    final rows = [row('playing', human: true, status: 'playing', seats: 2),
      row('showcase', fake: true, status: 'playing', seats: 2),
      row('ready'), row('human', human: true)];
    rows.sort(compareLobbyTables);
    expect(rows.map((r) => r['id']), ['human', 'ready', 'playing', 'showcase']);
  });

  for (final realCount in [0, 1, 3, 8, 10]) {
    test('fills $realCount real tables to eight without dropping games', () {
      final real = List.generate(realCount, (i) => row('real-$i',
        status: i == 0 ? 'waiting' : 'playing', seats: i == 0 ? 1 : 2));
      final result = completeLobbyTables(realTables: real,
        league: {'id': 'standard', 'min_coin': 1000}, botPlayers: [], random: Random(1));
      expect(result.length, max(8, realCount));
      expect(result.where((t) => t['is_fake'] != true).length, realCount);
      expect(real.length, realCount);
      final fake = result.where((t) => t['is_fake'] == true).toList();
      for (final table in fake) {
        expect(table['status'], 'playing');
        expect(table['max_players'], 2);
        expect((table['_players'] as List).length, 2);
        expect((table['_players'] as List).map((p) => p['user_id']).toSet().length, 2);
      }
      if (realCount > 0) expect(result.first['id'], 'real-0');
    });
  }

  test('fresh shuffles use database bot names and avatars with no stale displays', () {
    final pool = List.generate(30, (i) => {'id': 'bot-$i', 'username': 'Bot name $i',
      'avatar_url': 'avatar-$i.png'});
    List<Map<String, dynamic>> compose(int seed, String league) => completeLobbyTables(
      realTables: [row('open'), row('stale', fake: true)],
      league: {'id': league}, botPlayers: pool, random: Random(seed));
    final first = compose(1,'standard'), refreshed = compose(2,'standard'), other = compose(3,'bronze');
    expect(first.length, 8);
    expect(first.any((t) => t['id'] == 'stale'), isFalse);
    final players = first.where((t) => t['is_fake'] == true)
      .expand((t) => t['_players'] as List).toList();
    expect(players.map((p) => p['user_id']).toSet().length, 14);
    expect(players.every((p) => p['username'].startsWith('Bot name ') &&
      p['avatar_url'].startsWith('avatar-')), isTrue);
    expect(jsonEncode(first), isNot(jsonEncode(refreshed)));
    expect(other.last['id'], startsWith('showcase:bronze:'));
    expect(pool.first.containsKey('seat_index'), isFalse);
  });

  test('bot pool uses a cached GET without a showcase RPC dependency', () async {
    var reads = 0;
    final client = SupabaseClient('https://local.invalid', 'test',
      httpClient: MockClient((request) async {
        reads++;
        expect(request.method, 'GET');
        expect(request.url.path, '/rest/v1/users');
        expect(request.url.queryParameters['is_bot'], 'eq.true');
        expect(request.url.queryParameters['select'], 'id,username,avatar_url');
        return http.Response(jsonEncode([{'id': 'bot', 'username': 'Emre K.', 'avatar_url': 'avatar.png'}]),
          200, request: request, reasonPhrase: 'OK',
          headers: {'content-type': 'application/json'});
      }));
    addTearDown(client.dispose);
    final service = ReadyTableService(client);
    expect((await service.botPlayers()).single['id'], 'bot');
    expect((await service.botPlayers()).single['username'], 'Emre K.');
    expect(reads, 1);
  });

  test('showcase outage cannot hide the real table list', () async {
    final client = SupabaseClient('https://local.invalid', 'test',
      httpClient: MockClient((request) async => http.Response(
        '{"code":"PGRST202","message":"not installed"}',404,
        request: request, reasonPhrase: 'Not Found',
        headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    final pool = await ReadyTableService(client).botPlayers();
    expect(pool, isEmpty);
    expect(completeLobbyTables(realTables: [row('open')],league: {'id': 'standard'},
      botPlayers: pool).length, 8);
  });

  for (final size in [const Size(568,320), const Size(844,390)]) {
    for (final scale in [1.0,2.0]) {
      testWidgets('display card blocks gameplay at $size scale $scale', (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var profiles = 0, watches = 0;
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
          builder: (context) => Center(child: SizedBox(width: 280,height: 125,
            child: MediaQuery(data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale)),child: LobbyTableListingCard(
              table: row('display',fake: true,status: 'playing',seats: 2),number: 2,
              blockedUserIds: const {},canSpectateAll: true,
              onJoin: (_) => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(showcaseTableMessage))),
              onSpectate: (_) => watches++,onUserTap: (_) => profiles++,
            )),
          )),
        ))));
        await tester.pumpAndSettle();
        expect(find.text('2/2 Oynanıyor'), findsOneWidget);
        expect(find.text('İZLE'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('showcase-display')));
        await tester.pump();
        expect(find.text(showcaseTableMessage), findsOneWidget);
        expect(profiles,0);
        expect(watches,0);
        expect(tester.takeException(),isNull);
      });
    }
  }
}
