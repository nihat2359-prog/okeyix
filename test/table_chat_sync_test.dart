import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/table_chat_sync.dart';

Map<String, dynamic> message(String id, {String role = 'player'}) => {
  'id': id, 'sender_id': '$role-user', 'role': role,
  'content': 'Merhaba', 'created_at': '2026-10-25T12:00:00Z',
};

void main() {
  test('saved player messages recover while the spectator screen stays open', () async {
    final delivered = <Map<String, dynamic>>[];
    final sync = TableChatSync(
      loadRecent: () async => [message('new'), message('old')],
      onMessage: delivered.add,
    );
    sync.seed([message('old')]);
    await sync.refresh();
    expect(delivered.map((m) => m['id']), ['new']);
    expect(delivered.single['role'], 'player');
    sync.receive(message('new'));
    await sync.refresh();
    expect(delivered.length, 1);
  });

  test('live notification during recovery does not replay its bubble', () async {
    final response = Completer<List<Map<String, dynamic>>>();
    final delivered = <Map<String, dynamic>>[];
    var reads = 0;
    final sync = TableChatSync(loadRecent: () {
      reads++;
      return response.future;
    }, onMessage: delivered.add);
    final first = sync.refresh();
    final second = sync.refresh();
    sync.receive(message('live'));
    expect(delivered.length, 1);
    response.complete([message('live'), message('missed', role: 'spectator')]);
    await Future.wait([first, second]);
    expect(reads, 1);
    expect(delivered.map((m) => m['id']), ['live', 'missed']);
  });

  test('recovery can retry after failure and never delivers after disposal', () async {
    var fail = true;
    final delivered = <Map<String, dynamic>>[];
    final sync = TableChatSync(loadRecent: () async {
      if (fail) throw StateError('offline');
      return [message('restored')];
    }, onMessage: delivered.add);
    await expectLater(sync.refresh(), throwsStateError);
    fail = false;
    await sync.refresh();
    expect(delivered.length, 1);
    sync.dispose();
    sync.receive(message('late'));
    await sync.refresh();
    expect(delivered.length, 1);
  });

  test('initial history and pending responses do not replay old messages', () async {
    final response = Completer<List<Map<String, dynamic>>>();
    final delivered = <Map<String, dynamic>>[];
    final sync = TableChatSync(loadRecent: () => response.future,
      onMessage: delivered.add);
    sync.seed([message('history')]);
    expect(delivered, isEmpty);
    expect(sync.latestMessageAt, DateTime.utc(2026, 10, 25, 12));
    final pending = sync.refresh();
    sync.dispose();
    response.complete([message('late')]);
    await pending;
    expect(delivered, isEmpty);
  });

  test('newer live message cannot advance the recovery cursor past a missed one', () async {
    final delivered = <Map<String, dynamic>>[];
    final sync = TableChatSync(loadRecent: () async => [
      {...message('missed'), 'created_at': '2026-10-25T12:01:00Z'},
    ], onMessage: delivered.add);
    sync.seed([message('old')]);
    sync.receive({...message('live'), 'created_at': '2026-10-25T12:02:00Z'});
    expect(sync.latestMessageAt, DateTime.utc(2026, 10, 25, 12));
    await sync.refresh();
    expect(delivered.map((m) => m['id']), ['live', 'missed']);
    expect(sync.latestMessageAt, DateTime.utc(2026, 10, 25, 12, 1));
  });
}
