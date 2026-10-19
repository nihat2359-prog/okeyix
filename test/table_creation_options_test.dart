import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/table_creation_options.dart';

void main() {
  test('Champions supports six distinct stakes from 3M through 10M', () {
    final stakes = buildTableStakes(3000000, 10000000);
    expect(stakes.length, greaterThanOrEqualTo(6));
    expect(stakes.first, 3000000);
    expect(stakes.last, 10000000);
    for (final entry in stakes) {
      final payload = tableCreationPayload(
        league: {'id': 'elite', 'min_coin': 3000000, 'max_coin': 10000000},
        userId: 'user',
        entry: entry,
        turnSeconds: 20,
        spectatorsEnabled: true,
        chatEnabled: true,
      );
      expect(payload['entry_coin'], entry);
    }
  });
  test(
    'five illustrative league ranges have at least six unique valid stakes',
    () {
      for (final range in [
        [100, 1000],
        [1000, 10000],
        [10000, 100000],
        [100000, 1000000],
        [1000000, 10000000],
      ]) {
        final stakes = buildTableStakes(range[0], range[1]);
        expect(stakes.length, greaterThanOrEqualTo(6));
        expect(stakes.toSet().length, stakes.length);
        expect(stakes.first, range[0]);
        expect(stakes.last, range[1]);
        expect(stakes.every((n) => n >= range[0] && n <= range[1]), isTrue);
        expect(stakes.map(formatTableStake).toSet().length, stakes.length);
      }
      expect(buildTableStakes(1000, 10000), [
        1000,
        2000,
        4000,
        6000,
        8000,
        10000,
      ]);
    },
  );

  test(
    'narrow, fixed and invalid ranges never fabricate out-of-range stakes',
    () {
      expect(buildTableStakes(100, 105), [100, 101, 102, 103, 104, 105]);
      expect(buildTableStakes(100, 102), [100, 101, 102]);
      expect(buildTableStakes(100, 100), [100]);
      expect(() => buildTableStakes(100, 99), throwsArgumentError);
      expect(() => buildTableStakes(0, 100), throwsArgumentError);
      expect(formatTableStake(1001), '1.001K');
      expect(formatTableStake(1000001), '1.000001M');
    },
  );

  test('each selection becomes the exact database insert payload', () {
    for (var tier = 0; tier < 5; tier++) {
      final minimum = [100, 1000, 10000, 100000, 1000000][tier];
      final league = <String, dynamic>{
        'id': 'league-$tier',
        'min_coin': minimum,
        'max_coin': minimum * 10,
        'min_rounds': 3,
      };
      for (final entry in buildTableStakes(minimum, minimum * 10)) {
        for (final speed in [15, 20]) {
          for (final spectator in [false, true]) {
            for (final chat in [false, true]) {
              final payload = tableCreationPayload(
                league: league,
                userId: 'user',
                entry: entry,
                turnSeconds: speed,
                spectatorsEnabled: spectator,
                chatEnabled: chat,
              );
              expect(payload, {
                'league_id': 'league-$tier',
                'max_players': 2,
                'entry_coin': entry,
                'min_rounds': 3,
                'status': 'waiting',
                'created_by': 'user',
                'turn_seconds': speed,
                'spectators_enabled': spectator,
                'chat_enabled': chat,
              });
            }
          }
        }
      }
    }
  });

  test('invalid draft cannot produce a database payload', () {
    Map<String, dynamic> payload(int entry, int speed) => tableCreationPayload(
      league: {'id': 'l0', 'min_coin': 100, 'max_coin': 1000},
      userId: 'user',
      entry: entry,
      turnSeconds: speed,
      spectatorsEnabled: true,
      chatEnabled: true,
    );
    expect(() => payload(99, 20), throwsArgumentError);
    expect(() => payload(1001, 20), throwsArgumentError);
    expect(() => payload(101, 20), throwsArgumentError);
    expect(() => payload(100, 30), throwsArgumentError);
  });
}
