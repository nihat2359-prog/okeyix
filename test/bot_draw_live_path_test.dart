import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/engine/models/tile.dart';
import 'package:okeyix/game/bot/bot_engine.dart';
import 'package:okeyix/game/bot/bot_observation.dart';
import 'bot_engine_test.dart' show stones, base;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    'run',
    'set',
    'real',
    'fake',
    'finish',
    'useless',
    'rpc_reject',
    'timeout',
    'top_error',
    'production_runner',
    'deadline_fallback',
  ]) {
    test('real OkeyGame -> observation -> runner -> RPC: $scenario', () async {
      final original = stones(
        scenario == 'finish'
            ? 'M1 M2 M3 M4 S5 S6 S7 S8 Y9 Y10 Y11 K6 K8 Y2'
            : scenario == 'set'
            ? '$base K9 M9 Y2 S5 Y13'
            : '$base K6 K8 Y2 S5 Y10',
      );
      var hand = original.map((s) => s.toPayload()).toList();
      final top = <String, dynamic>{'id': 'top', 'color': 'red', 'number': 7};
      if (scenario == 'set') top.addAll({'color': 'black', 'number': 9});
      if (scenario == 'real') {
        top.addAll({'color': 'blue', 'number': 13, 'is_joker': true});
      }
      if (scenario == 'fake') top.addAll({'number': 0, 'is_fake_joker': true});
      if (scenario == 'useless') top.addAll({'color': 'blue', 'number': 1});
      final calls = <String>[];
      final sources = <String>[];
      BotObservation? observed;
      BotDecision? evaluated;
      final started = DateTime.utc(2026, 10, 21).toLocal();
      final client = SupabaseClient(
        'https://offline.invalid',
        'test',
        httpClient: MockClient((request) async {
          final route = request.url.path.split('/').last;
          calls.add('${request.method}:$route');
          Object result;
          if (route == 'table_players') {
            result = [
              {'hand': hand, 'is_double_mode': false},
            ];
          } else if (route == 'table_discards') {
            if (request.url.queryParameters['limit'] == '1') {
              expect(request.url.queryParameters['seat_index'], 'eq.1');
              expect(request.url.queryParameters['drawn_at'], 'is.null');
              if (scenario == 'top_error') {
                return http.Response(
                  jsonEncode({'code': '42501', 'message': 'denied'}),
                  403,
                  request: request,
                  headers: {'content-type': 'application/json'},
                );
              }
              result = [
                {'tile': top},
              ];
            } else {
              result = [];
            }
          } else if (route == 'tables') {
            result = [
              {
                'status': 'playing',
                'current_turn': 0,
                'round_count': 1,
                'turn_started_at': started.toUtc().toIso8601String(),
              },
            ];
          } else if (route == 'game_draw') {
            final body = jsonDecode(request.body) as Map;
            final source = body['p_source'] as String;
            sources.add(source);
            if (source == 'discard') {
              expect(body['p_from_seat'], 1);
              if (scenario == 'rpc_reject') {
                return http.Response(
                  jsonEncode({'code': 'P0001', 'message': 'draw rejected'}),
                  400,
                  request: request,
                  headers: {'content-type': 'application/json'},
                );
              }
              hand.add(top);
            } else {
              hand.add({'id': 'closed', 'color': 'black', 'number': 1});
            }
            result = {'ok': true};
          } else if (route == 'game_discard_fast') {
            final body = jsonDecode(request.body) as Map;
            expect(hand.any((t) => t['id'] == body['p_tile']['id']), true);
            result = {'ok': true};
          } else if (route == 'game_finish') {
            expect(scenario, 'finish');
            result = {'ok': true};
          } else {
            fail('Unexpected route $route');
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
        botDecisionWorker: scenario == 'production_runner'
            ? null
            : (o) {
                observed = o;
                if (scenario == 'timeout') {
                  return Completer<BotDecision>().future;
                }
                evaluated = scenario == 'deadline_fallback'
                    ? botDeadlineDrawComparison(o)
                    : BotEngine(
                        maxNodes: 1000000,
                        timeBudget: const Duration(seconds: 3),
                      ).decide(o);
                return Future.value(evaluated);
              },
      );
      game.closedPile.add(
        TileModel(
          id: 'indicator',
          value: scenario == 'fake' ? 6 : 12,
          color: scenario == 'fake' ? TileColor.red : TileColor.blue,
        ),
      );
      for (var i = 0; i < 30; i++) {
        game.closedPile.add(
          TileModel(id: 'unseen:$i', value: 1, color: TileColor.yellow),
        );
      }
      await game.debugRunBotTurn(seat: 0, startedAt: started);
      if (scenario != 'production_runner') {
        expect(observed!.hand.length, 14);
        expect(observed!.hand.map((s) => s.id), original.map((s) => s.id));
        expect(observed!.deckRemaining, 30);
        expect(observed!.hand.any((s) => s.id.startsWith('unseen')), false);
        if (scenario == 'top_error') {
          expect(observed!.topDiscard, isNull);
        } else {
          expect(observed!.topDiscard!.id, 'top');
        }
        if (scenario == 'fake') {
          expect(observed!.topDiscard!.number, 7);
          expect(observed!.topDiscard!.fake, true);
          expect(observed!.topDiscard!.wild, false);
        }
        if (scenario == 'real') expect(observed!.topDiscard!.wild, true);
      }
      if (['useless', 'timeout', 'top_error'].contains(scenario)) {
        expect(sources, ['closed']);
      } else if (scenario == 'rpc_reject') {
        expect(sources, ['discard', 'closed']);
      } else {
        if (scenario != 'production_runner') {
          expect(
            evaluated!.limited,
            scenario == 'deadline_fallback',
            reason: '${evaluated!.draw?.toJson()}',
          );
        }
        expect(sources, ['discard'], reason: '${evaluated?.draw?.toJson()}');
      }
      expect(
        calls,
        contains(
          scenario == 'finish' ? 'POST:game_finish' : 'POST:game_discard_fast',
        ),
      );
      await client.dispose();
    });
  }
}
