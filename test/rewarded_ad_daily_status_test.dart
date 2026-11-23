import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/rewarded_ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('server credit suppresses offer, next server day allows it again', () async {
    SharedPreferences.setMockInitialValues({});
    var day = '2026-11-23';
    var available = false;
    final client = SupabaseClient('https://example.supabase.co', 'test',
      httpClient: MockClient((request) async => http.Response(jsonEncode({
        'available': available, 'day_key': day, 'amount': 15000,
      }), 200, request: request, headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    final service = RewardedAdService(client);
    expect((await service.status())['available'], false);
    expect((await RewardedAdService(client).status())['available'], false);
    day = '2026-11-24';
    available = true;
    expect((await service.status())['available'], true);
  });
  test('completed video suppresses delayed SSV only for its server day', () async {
    // The transport stub has no session; production uses the authenticated uid.
    SharedPreferences.setMockInitialValues({'ad_video_completed_null': '2026-11-23'});
    var day = '2026-11-23';
    final client = SupabaseClient('https://example.supabase.co', 'test',
      httpClient: MockClient((request) async => http.Response(jsonEncode({
        'available': true, 'day_key': day, 'amount': 15000,
      }), 200, request: request, headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    expect((await RewardedAdService(client).status())['available'], false);
    day = '2026-11-24';
    expect((await RewardedAdService(client).status())['available'], true);
  });
  test('closing offer does not consume eligibility across lobby visits', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SupabaseClient('https://example.supabase.co', 'test',
      httpClient: MockClient((request) async => http.Response(jsonEncode({
        'available': true, 'day_key': '2026-11-23', 'amount': 15000,
      }), 200, request: request, headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    final service = RewardedAdService(client);
    expect((await service.status())['available'], true);
    expect((await service.status())['available'], true);
  });
}
