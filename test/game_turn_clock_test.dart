import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/game_turn_clock.dart';

void main() {
  final start = DateTime.utc(2026, 10, 28, 12);
  test(
    'same-seat new turn refreshes immediately, including sub-three-second differences',
    () {
      final clock = GameTurnClock();
      clock.apply(
        nextSeat: 0,
        nextStatus: 'playing',
        serverStartedAt: start,
        nextRound: 1,
        fallbackNow: start,
      );
      final next = start.add(const Duration(seconds: 2));
      clock.apply(
        nextSeat: 0,
        nextStatus: 'playing',
        serverStartedAt: next,
        nextRound: 1,
        fallbackNow: next,
      );
      expect(clock.startedAt, next);
    },
  );
  test('older reads cannot rewind a newer realtime turn', () {
    final clock = GameTurnClock();
    final next = start.add(const Duration(seconds: 20));
    clock.apply(
      nextSeat: 1,
      nextStatus: 'playing',
      serverStartedAt: next,
      nextRound: 1,
      fallbackNow: next,
    );
    expect(
      clock.apply(
        nextSeat: 0,
        nextStatus: 'playing',
        serverStartedAt: start,
        nextRound: 1,
        fallbackNow: next,
      ),
      isFalse,
    );
    expect(clock.seat, 1);
    expect(clock.startedAt, next);
  });
  test(
    'repeated snapshots and missing timestamps do not restart the timer',
    () {
      final clock = GameTurnClock();
      clock.apply(
        nextSeat: 0,
        nextStatus: 'playing',
        serverStartedAt: start,
        nextRound: 1,
        fallbackNow: start,
      );
      clock.apply(
        nextSeat: 0,
        nextStatus: 'playing',
        serverStartedAt: null,
        nextRound: 1,
        fallbackNow: start.add(const Duration(seconds: 20)),
      );
      expect(clock.startedAt, start);
    },
  );
  test(
    'new round accepts its clock and rejects delayed previous-round events',
    () {
      final clock = GameTurnClock();
      clock.apply(
        nextSeat: 0,
        nextStatus: 'playing',
        serverStartedAt: start,
        nextRound: 1,
        fallbackNow: start,
      );
      final next = start.add(const Duration(seconds: 30));
      clock.apply(
        nextSeat: 1,
        nextStatus: 'playing',
        serverStartedAt: next,
        nextRound: 2,
        fallbackNow: next,
      );
      expect(
        clock.apply(
          nextSeat: 0,
          nextStatus: 'waiting',
          serverStartedAt: start,
          nextRound: 1,
          fallbackNow: next,
        ),
        isFalse,
      );
      expect(clock.status, 'playing');
      expect(clock.round, 2);
    },
  );
  test(
    'finish status stops the current clock without inventing a next turn',
    () {
      final clock = GameTurnClock();
      clock.apply(
        nextSeat: 1,
        nextStatus: 'playing',
        serverStartedAt: start,
        nextRound: 1,
        fallbackNow: start,
      );
      clock.apply(
        nextSeat: 1,
        nextStatus: 'waiting',
        serverStartedAt: start,
        nextRound: 1,
        fallbackNow: start.add(const Duration(seconds: 10)),
      );
      expect(clock.status, 'waiting');
      expect(clock.startedAt, start);
      expect(clock.seat, 1);
    },
  );
}
