import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/services/quality_conversion_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> events;
  late QualityConversionService service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = [];
    service = QualityConversionService(logEvent: (name) async => events.add(name));
  });
  Future<Map<String, dynamic>> state() async => jsonDecode(
    (await SharedPreferences.getInstance()).getString(QualityConversionService.storageKey)!) as Map<String, dynamic>;

  test('first and third completed hands emit their events once', () async {
    await service.recordCompletedRound(tableId: 'table', round: 1);
    expect(events, ['first_match_completed']);
    await service.recordCompletedRound(tableId: 'table', round: 2);
    expect(events, ['first_match_completed']);
    await service.recordCompletedRound(tableId: 'table', round: 3);
    await service.recordCompletedRound(tableId: 'table', round: 4);
    expect(events, ['first_match_completed', 'engaged_player']);
    expect((await state())['completed_rounds'], 4);
  });

  test('overlapping realtime and local receipts count once', () async {
    await Future.wait(List.generate(10, (_) => service.recordCompletedRound(tableId: 'table', round: 1)));
    expect(events, ['first_match_completed']);
    expect((await state())['completed_rounds'], 1);
  });

  test('restart and account changes on the same device preserve one-time flags', () async {
    await service.recordCompletedRound(tableId: 'a', round: 1);
    await service.recordCompletedRound(tableId: 'b', round: 1);
    final restarted = QualityConversionService(logEvent: (name) async => events.add(name));
    await restarted.recordCompletedRound(tableId: 'a', round: 1);
    await restarted.recordCompletedRound(tableId: 'b', round: 2);
    final anotherAccount = QualityConversionService(logEvent: (name) async => events.add(name));
    await anotherAccount.recordCompletedRound(tableId: 'c', round: 1);
    expect(events, ['first_match_completed', 'engaged_player']);
    expect((await state())['completed_rounds'], 4);
  });

  test('high server round number counts one hand without retroactive conversions', () async {
    await service.recordCompletedRound(tableId: 'table', round: 20);
    await service.recordCompletedRound(tableId: 'table', round: 19);
    expect((await state())['completed_rounds'], 1);
    expect(events, ['first_match_completed']);
  });

  test('failed SDK submission retries without recounting the receipt', () async {
    var fail = true;
    service = QualityConversionService(logEvent: (name) async {
      if (fail) throw StateError('SDK unavailable');
      events.add(name);
    });
    await service.recordCompletedRound(tableId: 'table', round: 1);
    expect(events, isEmpty);
    fail = false;
    await service.recordCompletedRound(tableId: 'table', round: 1);
    await service.recordCompletedRound(tableId: 'table', round: 1);
    expect(events, ['first_match_completed']);
    expect((await state())['completed_rounds'], 1);
  });

  test('invalid receipts and storage failures never emit or interrupt gameplay', () async {
    await service.recordCompletedRound(tableId: '', round: 1);
    await service.recordCompletedRound(tableId: 'table', round: 0);
    service = QualityConversionService(preferences: () async => throw StateError('storage offline'),
      logEvent: (name) async => events.add(name));
    await service.recordCompletedRound(tableId: 'table', round: 1);
    expect(events, isEmpty);
  });
}
