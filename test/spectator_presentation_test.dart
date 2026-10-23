import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/spectator_presentation.dart';

void main() {
  test(
    'finish type uses confirmed flags and never invents a normal finish',
    () {
      expect(
        spectatorFinishLabel({
          'is_okey_finish': false,
          'is_double_finish': false,
        }),
        'Normal bitiş',
      );
      expect(
        spectatorFinishLabel({
          'is_okey_finish': true,
          'is_double_finish': false,
        }),
        'Okey atarak bitiş',
      );
      expect(
        spectatorFinishLabel({
          'is_okey_finish': false,
          'is_double_finish': true,
        }),
        'Çiftten bitiş',
      );
      expect(
        spectatorFinishLabel({
          'is_okey_finish': true,
          'is_double_finish': true,
        }),
        'Çiftten, okey atarak bitiş',
      );
      expect(spectatorFinishLabel({}), isNull);
    },
  );
  test('finish winner comes only from a single confirmed snapshot winner', () {
    final winner = {'user_id': 'winner', 'is_winner': true};
    expect(
      spectatorSnapshotWinner({
        'players': {
          'players': [
            winner,
            {'is_winner': false},
          ],
        },
      })?['user_id'],
      'winner',
    );
    expect(
      spectatorSnapshotWinner({
        'players': '{"players":[{"user_id":"w","is_winner":true}]}',
      })?['user_id'],
      'w',
    );
    expect(
      spectatorSnapshotWinner({
        'players': {
          'players': [winner, winner],
        },
      }),
      isNull,
    );
    expect(
      spectatorSnapshotWinner({
        'players': {'players': []},
      }),
      isNull,
    );
    expect(spectatorSnapshotWinner({'players': 'invalid'}), isNull);
  });
  test('turn ring counts down and clamps expired/future timestamps', () {
    final start = DateTime.utc(2026, 10, 21);
    expect(spectatorTurnProgress(start, 20, start), 1);
    expect(
      spectatorTurnProgress(start, 20, start.add(const Duration(seconds: 10))),
      .5,
    );
    expect(
      spectatorTurnProgress(start, 20, start.add(const Duration(seconds: 21))),
      0,
    );
    expect(
      spectatorTurnProgress(
        start,
        20,
        start.subtract(const Duration(seconds: 1)),
      ),
      1,
    );
    expect(spectatorTurnProgress(null, 20, start), 0);
    expect(spectatorTurnProgress(start, 0, start), 0);
  });
  test('viewer is excluded before limiting the other spectator avatars', () {
    final entries = [
      'me',
      'a',
      'b',
      'c',
    ].map((id) => <String, dynamic>{'user_id': id}).toList();
    expect(otherSpectators(entries, 'me').map((e) => e['user_id']), [
      'a',
      'b',
      'c',
    ]);
    expect(otherSpectators([entries.first], 'me'), isEmpty);
    expect(entries.length, 4);
  });
}
