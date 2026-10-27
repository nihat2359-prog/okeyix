// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/game/okey_game.dart';
import 'package:okeyix/services/user_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const uid = '00000000-0000-4000-8000-000000000001';
  final calls = <String>[];
  var coins = 10000;
  var pot = 1000;
  var rejectUpdate = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token = '${base64Url.encode(utf8.encode('{"alg":"none"}'))}.'
      '${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.test';
    await Supabase.initialize(url: 'https://fixture.invalid', anonKey: 'test', debug: false,
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage(),
        autoRefreshToken: false, detectSessionInUri: false),
      httpClient: MockClient((request) async {
        Object? data;
        var status = 200;
        final route = request.url.path.split('/').last;
        if (request.url.path.contains('/auth/')) {
          data = {'access_token': token, 'refresh_token': 'test', 'expires_in': 3600,
            'token_type': 'bearer', 'user': {'id': uid, 'aud': 'authenticated',
              'created_at': '2026-10-27T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}}};
        } else {
          calls.add('${request.method} $route');
          if (route == 'profiles' && request.method == 'POST') {
            status = 400;
            data = {'code': '23502', 'message': 'null value in column username violates not-null constraint'};
          } else if (route == 'tables') {
            if (request.method == 'PATCH') pot = (jsonDecode(request.body) as Map)['pot_amount'] as int;
            data = request.method == 'PATCH' ? [{'id': 'table', 'pot_amount': pot}] : {'pot_amount': pot};
          } else if (route == 'profiles') {
            if (request.method == 'PATCH') {
              final body = jsonDecode(request.body) as Map;
              expect(body.keys, ['coins']);
              expect(request.url.queryParameters['id'], 'eq.$uid');
              if (!rejectUpdate) coins = body['coins'] as int;
              data = rejectUpdate ? [] : [{'id': uid}];
            } else { data = {'coins': coins}; }
          } else if (route == 'wallet_transactions') {
            data = null;
          } else { throw StateError('Unexpected route: $route'); }
        }
        return http.Response(jsonEncode(data), status, request: request,
          headers: {'content-type': 'application/json'});
      }));
    await Supabase.instance.client.auth.signInWithPassword(email: 'test@example.invalid', password: 'test');
  });
  setUp(() { calls.clear(); coins = 10000; pot = 1000; rejectUpdate = false; UserState.userCoin = coins; });
  tearDownAll(() => Supabase.instance.dispose());
  test('indicator credit patches existing profile without inserting a nameless row', () async {
    final game = OkeyGame(tableId: 'table', isCreator: false);
    expect(await game.debugClaimIndicatorReward(), 100);
    expect(coins, 10100);
    expect(pot, 900);
    expect(UserState.userCoin, 10100);
    expect(calls, contains('PATCH profiles'));
    expect(calls, isNot(contains('POST profiles')));
    expect(calls, contains('POST wallet_transactions'));
  });
  test('a denied profile update never reports success or adds a wallet receipt', () async {
    rejectUpdate = true;
    final game = OkeyGame(tableId: 'table', isCreator: false);
    expect(await game.debugClaimIndicatorReward(), 0);
    expect(coins, 10000);
    expect(UserState.userCoin, 10000);
    expect(calls, isNot(contains('POST wallet_transactions')));
  });
}
