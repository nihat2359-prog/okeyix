import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/game/okey_game.dart';
import 'bot_engine_test.dart' show stones;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final behavior in [
    'ok',
    'false',
    'exception',
    'committed_exception',
    'stale_hand',
    'pairs',
    'pairs_missing',
    'pairs_response_lost',
    'draw_gap',
    'draw_response_lost',
    'draw_stale_turn',
  ]) {
    test('actual OkeyGame bot adapter: $behavior', () async {
      var hand = stones(
        behavior.startsWith('pairs')
            ? 'K2 K2 M4 M4 S6 S6 Y8 Y8 K10 K10 M12 M12 Y1 Y1 S3'
            : behavior.startsWith('draw')
            ? 'M1 M2 M3 M4 S5 S6 S7 S8 Y9 Y10 Y11 K6 K8 Y2'
            : 'K1 K2 K3 K4 M5 M6 M7 M8 S9 S10 S11 Y5 Y6 Y7 J',
      ).map((s) => s.toPayload()).toList();
      final calls = <String>[];
      var playing = true, pairs = false;
      var handReads = 0;
      final started = DateTime.utc(2026, 10, 21);
      final client = SupabaseClient(
        'https://offline.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          final route = request.url.path.split('/').last;
          calls.add('${request.method}:$route');
          Object result;
          switch (route) {
            case 'table_players':
              handReads++;
              if (behavior == 'stale_hand' && handReads > 1) {
                hand = [...hand]..[0] = {...hand[0], 'id': 'changed'};
              }
              result = [
                {'hand': hand, 'is_double_mode': pairs},
              ];
            case 'table_discards':
              if (request.url.queryParameters['limit'] == '1') {
                expect(request.url.queryParameters['drawn_at'], 'is.null');
                expect(request.url.queryParameters['seat_index'], 'eq.1');
                result = [
                  {
                    'tile': {'id': 'top', 'color': 'red', 'number': 7},
                  },
                ];
                break;
              }
              expect(
                request.url.queryParameters['select'],
                'id,seat_index,tile,drawn_at,drawn_by_user_id,created_at',
              );
              result = [];
            case 'tables':
              result = [
                {
                  'status': playing ? 'playing' : 'waiting',
                  'current_turn': 0,
                  'turn_started_at':
                      (behavior == 'draw_stale_turn'
                              ? started.add(const Duration(seconds: 20))
                              : started)
                          .toIso8601String(),
                  'round_count': 1,
                },
              ];
            case 'okeyix_bot_confirm_pairs':
              if (behavior == 'pairs_missing') {
                return http.Response(
                  jsonEncode({
                    'code': 'PGRST202',
                    'message': 'Missing endpoint',
                  }),
                  404,
                  request: request,
                  headers: {'content-type': 'application/json'},
                );
              }
              pairs = true;
              if (behavior == 'pairs_response_lost') {
                throw StateError('declaration response lost');
              }
              result = {'ok': true};
            case 'table_discard_tops':
              result = [
                {
                  'tile': {'id': 'top', 'color': 'red', 'number': 7},
                },
              ];
            case 'game_draw':
              final payload = jsonDecode(request.body) as Map;
              expect(payload['p_source'], 'discard');
              hand.add({'id': 'top', 'color': 'red', 'number': 7});
              if (behavior == 'draw_response_lost') {
                throw StateError('draw response lost');
              }
              result = {'ok': true};
            case 'game_finish':
              final payload = jsonDecode(request.body) as Map;
              expect((payload['p_slots'] as List).length, 26);
              expect(payload['p_user_id'], 'bot');
              if (behavior == 'committed_exception') playing = false;
              if (behavior.contains('exception')) {
                throw StateError('simulated response loss');
              }
              result = {'ok': behavior != 'false'};
            case 'game_discard_fast':
              final payload = jsonDecode(request.body) as Map;
              expect(hand.any((s) => s['id'] == payload['p_tile']['id']), true);
              expect(playing, true);
              result = {'ok': true};
            default:
              fail('Unexpected network request: $route');
          }
          return http.Response(
            jsonEncode(result),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final game = OkeyGame(
        tableId: 'table',
        isCreator: false,
        botClient: client,
      );
      await game.debugRunBotTurn(seat: 0, startedAt: started);
      if (behavior == 'stale_hand' || behavior == 'draw_stale_turn') {
        expect(calls, isNot(contains('POST:game_finish')));
        expect(calls, isNot(contains('POST:game_discard_fast')));
      } else {
        expect(
          calls.where((c) => c == 'POST:game_finish').length,
          behavior == 'pairs_missing' ? 0 : 1,
        );
        expect(
          calls.where((c) => c == 'POST:game_discard_fast').length,
          ['false', 'exception', 'pairs_missing'].contains(behavior) ? 1 : 0,
        );
      }
      if (behavior.startsWith('pairs')) {
        expect(calls, contains('POST:okeyix_bot_confirm_pairs'));
      }
      if (behavior.startsWith('draw')) {
        expect(
          calls.where((c) => c == 'POST:game_draw').length,
          behavior == 'draw_stale_turn' ? 0 : 1,
        );
      }
      await client.dispose();
    });
  }
}
