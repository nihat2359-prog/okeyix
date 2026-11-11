import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/pisti_service.dart';

void main() {
  test(
    'own active-room query sends a JSON array and restores the membership',
    () async {
      const id = '00000000-0000-0000-0000-000000000001';
      String part(Map<String, dynamic> value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final token =
          '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.signature';
      var queried = false;
      final client = SupabaseClient(
        'https://pisti.invalid',
        'local-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          Object response;
          if (request.url.path == '/auth/v1/token') {
            response = {
              'access_token': token,
              'refresh_token': 'local-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': id,
                'aud': 'authenticated',
                'email': 'test@pisti.invalid',
                'created_at': '2026-10-31T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            };
          } else if (request.url.path.endsWith('/okeyix_pisti_settings')) {
            response = {'enabled': true};
          } else if (request.url.path.endsWith('/okeyix_pisti_rooms')) {
            expect(request.url.queryParameters['seats'], 'cs.[{"id":"$id"}]');
            expect(
              request.url.queryParameters['status'],
              'in.("waiting","playing")',
            );
            queried = true;
            response = [
              {'id': 'active-break'},
            ];
          } else {
            expect(request.url.path, endsWith('/okeyix_pisti_invites'));
            response = [];
          }
          return http.Response(
            jsonEncode(response),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await client.auth.signInWithPassword(
        email: 'test@pisti.invalid',
        password: 'local-password',
      );
      final result = await PistiService(client: client).lobby();
      expect(queried, isTrue);
      expect(result['active_room_id'], 'active-break');
      expect(result.containsKey('rooms'), isFalse);
      await client.dispose();
    },
  );
}
