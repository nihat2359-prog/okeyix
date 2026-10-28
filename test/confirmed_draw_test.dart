import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/confirmed_draw.dart';

void main() {
  final oldIds = {for (var i = 0; i < 14; i++) 'tile-$i'};
  final committed = [
    for (var i = 0; i < 15; i++) {'id': 'tile-$i'},
  ];
  test(
    'server hand reveals a committed draw while HTTP response is delayed',
    () async {
      final rpc = Completer<dynamic>();
      var reads = 0;
      final response = await confirmedDraw(
        mutation: rpc.future,
        previousIds: oldIds,
        tableId: 'table',
        isCurrent: () => true,
        retryAfter: Duration.zero,
        readHand: () async {
          reads++;
          return committed;
        },
      );
      expect(response['hand'], committed);
      expect(reads, 1);
      // A late transport error must neither undo the confirmed hand nor escape.
      rpc.completeError(StateError('late transport failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('a fast mutation starts no extra reads', () async {
    var reads = 0;
    final response = await confirmedDraw(
      mutation: Future.value({'ok': true}),
      previousIds: oldIds,
      tableId: 'table',
      isCurrent: () => true,
      readHand: () async {
        reads++;
        return committed;
      },
    );
    expect(response['ok'], isTrue);
    expect(reads, 0);
  });
  test(
    'failed reads and unrelated hands cannot confirm the mutation',
    () async {
      final rpc = Completer<dynamic>();
      var reads = 0;
      final result = confirmedDraw(
        mutation: rpc.future,
        previousIds: oldIds,
        tableId: 'table',
        isCurrent: () => true,
        retryAfter: Duration.zero,
        readHand: () async {
          reads++;
          if (reads == 1) throw StateError('read unavailable');
          if (reads == 2) return committed.take(14).toList();
          if (reads == 3) return List.filled(15, {'id': 'duplicate'});
          if (reads == 4) {
            return [
              for (var i = 0; i < 15; i++) {'id': 'other-$i'},
            ];
          }
          rpc.complete({'ok': false});
          return committed;
        },
      );
      expect((await result)['ok'], isFalse);
      expect(reads, 5);
    },
  );
  test('round or turn change rejects an in-flight confirmation read', () async {
    final rpc = Completer<dynamic>();
    final read = Completer<List<dynamic>?>();
    final reading = Completer<void>();
    var current = true;
    final result = confirmedDraw(
      mutation: rpc.future,
      previousIds: oldIds,
      tableId: 'table',
      isCurrent: () => current,
      retryAfter: Duration.zero,
      readHand: () {
        reading.complete();
        return read.future;
      },
    );
    await reading.future;
    current = false;
    read.complete(committed);
    await Future<void>.delayed(Duration.zero);
    rpc.complete({'ok': false});
    expect((await result)['ok'], isFalse);
  });
}
