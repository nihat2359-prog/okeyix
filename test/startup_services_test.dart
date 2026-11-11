import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/analytics_service.dart';
import 'package:okeyix/services/device_registration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'optional analytics does not access an uninitialized Firebase app',
    () async {
      await AnalyticsService.instance.logLogin(method: 'test');
      await AnalyticsService.instance.logSignUp(method: 'test');
      await AnalyticsService.instance.logCoinPurchase(
        productId: 'test',
        coins: 1,
        platform: 'test',
      );
      await AnalyticsService.instance.logEvent(name: 'pisti_table_open');
    },
  );
  test(
    'parallel startup registration coalesces and a later push token is preserved',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({
        'stable_install_id_v2': 'fixture-install',
      });
      PackageInfo.setMockInitialValues(
        appName: 'Okeyix',
        packageName: 'com.okeyix.game',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      const uid = '00000000-0000-0000-0000-000000000001';
      String part(Object o) =>
          base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
      final token =
          '${part({'alg': 'none'})}.${part({'sub': uid, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
      final started = Completer<void>(), release = Completer<void>();
      final requests = <Map<String, dynamic>>[];
      var active = 0, peak = 0;
      await Supabase.initialize(
        url: 'https://startup.invalid',
        anonKey: 'fixture',
        debug: false,
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
          autoRefreshToken: false,
          detectSessionInUri: false,
        ),
        httpClient: MockClient((request) async {
          Object body;
          if (request.url.path.contains('/auth/')) {
            body = {
              'access_token': token,
              'refresh_token': 'fixture',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': uid,
                'aud': 'authenticated',
                'created_at': '2026-10-31T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            };
          } else {
            expect(request.url.path, '/functions/v1/register_device');
            active++;
            if (active > peak) peak = active;
            requests.add(Map<String, dynamic>.from(jsonDecode(request.body)));
            if (requests.length == 1) {
              started.complete();
              await release.future;
            }
            active--;
            body = {'success': true};
          }
          return http.Response(
            jsonEncode(body),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: 'fixture@startup.invalid',
          password: 'fixture',
        );
        final first = DeviceRegistrationService.registerCurrentDevice(
          lookupPushToken: false,
        );
        final duplicate = DeviceRegistrationService.registerCurrentDevice(
          lookupPushToken: false,
        );
        await started.future;
        final updated = DeviceRegistrationService.registerCurrentDevice(
          pushTokenOverride: 'fixture-push',
          lookupPushToken: false,
        );
        expect(requests, hasLength(1));
        release.complete();
        await Future.wait([first, duplicate, updated]);
        expect(peak, 1);
        expect(requests, hasLength(2));
        expect(requests.last['push_token'], 'fixture-push');
        expect(requests.map((r) => r['device_id']).toSet(), {
          'fixture-install',
        });
      } finally {
        await Supabase.instance.dispose();
      }
    },
  );
}
