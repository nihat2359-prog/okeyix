import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/ready_table_service.dart';

void main() {
  const tableId = '00000000-0000-0000-0000-000000000001';
  SupabaseClient clientFor(Object response, {int status = 200}) =>
      SupabaseClient(
        'https://local-test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/okeyix_ready_table_ids');
          expect(jsonDecode(request.body), {
            'p_table_ids': [tableId],
          });
          return http.Response(
            jsonEncode(response),
            status,
            request: request,
            reasonPhrase: status == 200 ? 'OK' : 'Error',
            headers: {'content-type': 'application/json'},
          );
        }),
      );
  test('only server-returned table IDs bypass stale owner checks', () async {
    final verified = clientFor([tableId]);
    final ordinary = clientFor([]);
    final other = clientFor(['00000000-0000-0000-0000-000000000002']);
    try {
      expect(await ReadyTableService(verified).isManaged(tableId), isTrue);
      expect(await ReadyTableService(ordinary).isManaged(tableId), isFalse);
      expect(await ReadyTableService(other).isManaged(tableId), isFalse);
    } finally {
      await verified.dispose();
      await ordinary.dispose();
      await other.dispose();
    }
  });
  test('missing migration keeps normal owner checks', () async {
    final client = clientFor({
      'code': 'PGRST202',
      'message': 'not installed',
    }, status: 404);
    try {
      expect(await ReadyTableService(client).isManaged(tableId), isFalse);
    } finally {
      await client.dispose();
    }
  });
  test('verification failures never grant a bypass', () async {
    final client = clientFor({
      'code': '42501',
      'message': 'denied',
    }, status: 403);
    try {
      await expectLater(
        ReadyTableService(client).isManaged(tableId),
        throwsA(isA<PostgrestException>()),
      );
    } finally {
      await client.dispose();
    }
  });
}
