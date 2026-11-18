import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/quick_play_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lost response and route recreation retain the same request UUID',
    () async {
      SharedPreferences.setMockInitialValues({});
      final requests = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/okeyix_quick_play_v2');
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (requests.length == 1) throw TimeoutException('response lost');
          return http.Response(
            jsonEncode({'state': 'cancelled'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final first = SupabaseQuickPlayBackend(client);
      await expectLater(
        first.command('start'),
        throwsA(isA<TimeoutException>()),
      );
      final recreated = SupabaseQuickPlayBackend(client);
      await recreated.command('cancel');
      expect(requests[0]['p_request_id'], requests[1]['p_request_id']);
      expect(requests[1]['p_action'], 'cancel');
      await client.dispose();
    },
  );
}
