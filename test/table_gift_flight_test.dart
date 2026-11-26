import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/table_gift_flight.dart';

void main() {
  test(
    'short incoming and outgoing flights never move back into the sender',
    () {
      for (final endpoints in [
        (const Offset(160, 30), const Offset(160, 80)),
        (const Offset(160, 80), const Offset(160, 30)),
        (const Offset(90, 30), const Offset(190, 110)),
        (const Offset(190, 110), const Offset(90, 30)),
        (const Offset(30, 70), const Offset(230, 70)),
      ]) {
        final (from, to) = endpoints;
        final delta = to - from;
        final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
        var previous = 0.0;
        expect(tableGiftFlightPoint(from, to, 0), from);
        expect(tableGiftFlightPoint(from, to, 1), to);
        for (var frame = 0; frame <= 100; frame++) {
          final travel = tableGiftFlightPoint(from, to, frame / 100) - from;
          final projection =
              (travel.dx * delta.dx + travel.dy * delta.dy) / lengthSquared;
          expect(projection, greaterThanOrEqualTo(previous - 1e-10));
          expect(projection, inInclusiveRange(-1e-10, 1 + 1e-10));
          previous = projection;
        }
      }
    },
  );
}
