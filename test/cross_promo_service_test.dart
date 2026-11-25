import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/cross_promo_service.dart';

const game = CrossPromoGame(
  id: 'okix',
  name: 'Okix',
  description: 'Bulmaca',
  iosBundle: 'com.okeyix.okix',
  iosAppId: '6838298677',
  androidPackage: 'test.okix',
);
String iosResult({String bundle = 'com.okeyix.okix'}) => jsonEncode({
  'resultCount': 1,
  'results': [
    {
      'bundleId': bundle,
      'kind': 'software',
      'trackId': 6838298677,
      'artworkUrl512': 'https://images.example.com/okix.png',
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unconfigured IDs never make HTTP requests', () async {
    final service = CrossPromoService(
      platform: PromoStore.android,
      catalog: [const CrossPromoGame(id: 'a', name: 'a', description: '')],
      client: MockClient((_) async => throw StateError('must not request')),
    );
    expect(await service.publishedGames(), isEmpty);
  });
  test('iOS exact bundle match and single in-flight session cache', () async {
    var calls = 0;
    final service = CrossPromoService(
      platform: PromoStore.ios,
      catalog: [game],
      client: MockClient((request) async {
        calls++;
        expect(request.url.queryParameters['bundleId'], game.iosBundle);
        return http.Response(iosResult(), 200);
      }),
    );
    final result = await Future.wait([
      service.publishedGames(),
      service.publishedGames(),
    ]);
    expect(calls, 1);
    expect(result.first.single.iosAppId, '6838298677');
    expect(
      result.first.single.artworkUrl,
      'https://images.example.com/okix.png',
    );
    await service.publishedGames();
    expect(calls, 1);
  });
  for (final response in [
    http.Response('{"results":[]}', 200),
    http.Response(iosResult(bundle: 'wrong.app'), 200),
    http.Response('', 404),
    http.Response('invalid', 200),
  ]) {
    test(
      'unavailable or ambiguous iOS response fails closed ${response.body}',
      () async {
        final service = CrossPromoService(
          platform: PromoStore.ios,
          catalog: [game],
          client: MockClient((_) async => response),
        );
        expect(await service.publishedGames(), isEmpty);
      },
    );
  }
  test('Android rejects 200 error and private listing pages', () async {
    final service = CrossPromoService(
      platform: PromoStore.android,
      catalog: [game],
      client: MockClient(
        (_) async => http.Response('<html>Join the test</html>', 200),
      ),
    );
    expect(await service.publishedGames(), isEmpty);
  });
  test('Android requires exact public app structured data', () async {
    final service = CrossPromoService(
      platform: PromoStore.android,
      catalog: [game],
      client: MockClient(
        (_) async => http.Response(
          '<script type="application/ld+json">${jsonEncode({
            '@type': 'SoftwareApplication',
            'name': 'Okix',
            'url': 'https://play.google.com/store/apps/details?id=test.okix',
            'offers': {'price': '0'},
          })}</script>',
          200,
        ),
      ),
    );
    expect((await service.publishedGames()).single.id, 'okix');
  });
  test('network failure hides games', () async {
    final service = CrossPromoService(
      platform: PromoStore.ios,
      catalog: [game],
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(await service.publishedGames(), isEmpty);
  });

  Future<SupabaseClient> backend(
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test',
      httpClient: MockClient((request) async {
        final response = await handler(request);
        return http.Response(
          response.body,
          response.statusCode,
          request: request,
          headers: response.headers,
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test',
        'refresh_token': 'test',
        'token_type': 'bearer',
        'user': {
          'id': 'user-a',
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-11-24T00:00:00Z',
        },
      }),
    );
    return client;
  }

  CrossPromoService service(Future<bool> Function(Uri) open) =>
      CrossPromoService(
        platform: PromoStore.ios,
        catalog: [game],
        openStore: open,
        client: MockClient((_) async => http.Response(iosResult(), 200)),
      );

  test(
    'successful store open credits once and caches by user and game',
    () async {
      var credits = 0;
      final client = await backend((request) async {
        expect(jsonDecode(request.body), {
          'p_game_id': 'okix',
          'p_store': 'ios',
        });
        credits++;
        return http.Response(
          '{"credited":true,"amount":5000}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final promo = service((url) async {
        expect(url.host, 'apps.apple.com');
        return true;
      });
      expect(await promo.openAndReward(game, client), 5000);
      expect(await promo.openAndReward(game, client), 0);
      expect(credits, 1);
      expect(await promo.claimed('user-a', game), isTrue);
      expect(await promo.claimed('user-b', game), isFalse);
    },
  );
  test('store failure never calls wallet', () async {
    final client = await backend(
      (_) async => throw StateError('must not credit'),
    );
    final promo = service((_) async => false);
    await expectLater(promo.openAndReward(game, client), throwsStateError);
    expect(await promo.claimed('user-a', game), isFalse);
  });
  test(
    'failed RPC does not consume reward and concurrent taps do not duplicate',
    () async {
      final pending = Completer<bool>();
      var credits = 0;
      final client = await backend((_) async {
        credits++;
        return http.Response('{"message":"offline"}', 503);
      });
      final promo = service((_) => pending.future);
      final first = promo.openAndReward(game, client);
      await Future<void>.delayed(Duration.zero);
      final second = promo.openAndReward(game, client);
      pending.complete(true);
      await expectLater(first, throwsA(isA<PostgrestException>()));
      expect(await second, 0);
      expect(credits, 1);
      expect(await promo.claimed('user-a', game), isFalse);
    },
  );
}
