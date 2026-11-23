import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/services/app_review_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  final today = DateTime.utc(2026, 11, 23);
  Map<String, Object> eligible() => {
    'review_first_visit': today.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
    'review_games': 3,
  };
  test('new players and early exits do not trigger a review', () async {
    SharedPreferences.setMockInitialValues({});
    var requests = 0;
    final service = AppReviewService(now: () => today, available: () async => true,
      request: () async { requests++; }, version: () async => '1.0');
    await service.recordVisit();
    await service.recordCompletedGame('table:round1');
    await service.recordCompletedGame('table:round1');
    await service.maybeRequest(canPresent: () => true);
    expect(requests, 0);
    expect((await SharedPreferences.getInstance()).getInt('review_games'), 1);
  });
  test('eligible request is limited even if the platform shows nothing', () async {
    SharedPreferences.setMockInitialValues(eligible());
    var requests = 0;
    final service = AppReviewService(now: () => today, available: () async => true,
      request: () async { requests++; }, version: () async => '1.0');
    await service.maybeRequest(canPresent: () => true);
    await service.maybeRequest(canPresent: () => true);
    expect(requests, 1);
  });
  test('active dialog prevents a request without consuming cooldown', () async {
    SharedPreferences.setMockInitialValues(eligible());
    final ready = Completer<bool>();
    var idle = true;
    var requests = 0;
    final service = AppReviewService(now: () => today, available: () => ready.future,
      request: () async { requests++; }, version: () async => '1.0');
    final task = service.maybeRequest(canPresent: () => idle);
    idle = false;
    ready.complete(true);
    await task;
    expect(requests, 0);
    expect((await SharedPreferences.getInstance()).getInt('review_last_request'), isNull);
  });
  test('new version still respects 120-day cooldown', () async {
    SharedPreferences.setMockInitialValues({...eligible(),
      'review_last_request': today.subtract(const Duration(days: 119)).millisecondsSinceEpoch,
      'review_version': '1.0'});
    var requests = 0;
    var date = today;
    final service = AppReviewService(now: () => date, available: () async => true,
      request: () async { requests++; }, version: () async => '2.0');
    await service.maybeRequest(canPresent: () => true);
    expect(requests, 0);
    date = today.add(const Duration(days: 2));
    await service.maybeRequest(canPresent: () => true);
    expect(requests, 1);
  });
  test('store failure does not escape into gameplay', () async {
    SharedPreferences.setMockInitialValues(eligible());
    final service = AppReviewService(now: () => today,
      available: () async => throw StateError('store unavailable'),
      version: () async => '1.0');
    await expectLater(service.maybeRequest(canPresent: () => true), completes);
  });
}
