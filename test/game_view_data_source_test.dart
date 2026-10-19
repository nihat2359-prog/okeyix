import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/game_view_data_source.dart';

class Harness {
  final String tableId;
  Harness({this.tableId = 't'});
  DateTime clock = DateTime.utc(2026, 10, 19);
  String? user = 'a';
  ViewRow state = {'id': 't', 'current_turn': 0};
  ViewRows members = [
    {'user_id': 'a', 'seat_index': 0},
    {'user_id': 'b', 'seat_index': 1},
  ];
  final counts = <String, int>{};
  Future<ViewRow?> Function()? delayedTable;
  late final GameViewDataSource data = GameViewDataSource(
    tableId: tableId,
    currentUser: () => user,
    now: () => clock,
    fetchTable: () async {
      hit('table');
      return delayedTable != null ? await delayedTable!() : Map.of(state);
    },
    fetchPlayers: () async {
      hit('players');
      return members.map((e) => ViewRow.of(e)).toList();
    },
    fetchUsers: (ids) async {
      hit('users');
      return [
        for (final id in ids)
          {'id': id, 'username': 'name-$id', 'avatar_url': '$id.png'},
      ];
    },
    fetchProfiles: (ids) async {
      hit('profiles');
      return [
        for (final id in ids) {'id': id, 'coins': 2500},
      ];
    },
    fetchLeague: (id) async {
      hit('league');
      return [
        {'turn_seconds': 15},
      ];
    },
  );
  void hit(String name) => counts[name] = (counts[name] ?? 0) + 1;
  void advance() => clock = clock.add(const Duration(seconds: 2));
  Future<void> screen() async {
    await data.table();
    final players = await data.players();
    await data.users(players.map((e) => e['user_id'] as String).toList());
  }

  Future<void> avatars() async {
    await data.table();
    await data.league('l');
    final players = await data.players();
    final ids = players.map((e) => e['user_id'] as String).toList();
    await data.profiles(ids);
    await data.users(ids);
  }
}

void main() {
  test('separate table lifetimes never reuse each other caches', () async {
    final first = Harness(tableId: 'first');
    final second = Harness(tableId: 'second');
    first.state['id'] = 'first';
    second.state['id'] = 'second';
    expect((await first.data.table())!['id'], 'first');
    first.data.dispose();
    expect((await second.data.table())!['id'], 'second');
    expect(second.counts['table'], 1);
    second.data.dispose();
  });
  test(
    'two UI consumers share 30 polling cycles: 92 reads instead of 240',
    () async {
      final h = Harness();
      for (var i = 0; i < 30; i++) {
        await Future.wait([h.screen(), h.avatars()]);
        h.advance();
      }
      expect(h.counts, {
        'table': 30,
        'players': 30,
        'league': 1,
        'users': 1,
        'profiles': 30,
      });
      expect(h.counts.values.reduce((a, b) => a + b), 92);
      h.data.dispose();
    },
  );
  test(
    'a missed event or disconnected Realtime is recovered by unchanged polling',
    () async {
      final h = Harness();
      expect((await h.data.table())!['current_turn'], 0);
      h.state['current_turn'] = 1; // no Realtime notification
      h.members.removeLast();
      h.advance();
      expect((await h.data.table())!['current_turn'], 1);
      expect(await h.data.players(), hasLength(1));
      h.members.add({'user_id': 'c', 'seat_index': 1});
      h.data.invalidateAll(); // reconnect/resume hook
      expect((await h.data.players()).last['user_id'], 'c');
      h.data.dispose();
    },
  );
  test(
    'duplicate Realtime events invalidate once and consumers coalesce',
    () async {
      final h = Harness();
      await h.data.table();
      h.state['current_turn'] = 1;
      h.data.tableChanged('commit-1');
      final a = h.data.table();
      h.data.tableChanged('commit-1');
      final b = h.data.table();
      final results = await Future.wait([a, b]);
      expect(results.every((r) => r!['current_turn'] == 1), isTrue);
      expect(h.counts['table'], 2);
      h.data.dispose();
    },
  );
  test(
    'event during a read discards stale response and reconciles serially',
    () async {
      final h = Harness();
      final first = Completer<ViewRow?>();
      var requests = 0;
      h.delayedTable = () async {
        requests++;
        return requests == 1 ? first.future : {'current_turn': 1};
      };
      final pending = h.data.table();
      h.data.tableChanged('new-turn');
      first.complete({'current_turn': 0});
      expect((await pending)!['current_turn'], 1);
      expect(requests, 2);
      h.data.dispose();
    },
  );
  test(
    'membership changes clear name/avatar cache and retain correct user IDs',
    () async {
      final h = Harness();
      await h.data.players();
      expect((await h.data.users(['a', 'b'])).last['avatar_url'], 'b.png');
      h.members[1] = {'user_id': 'c', 'seat_index': 1};
      h.data.playersChanged('join-c');
      final members = await h.data.players();
      final users = await h.data.users(
        members.map((e) => e['user_id'] as String).toList(),
      );
      expect(users.map((e) => e['id']), ['a', 'c']);
      expect(users.last['avatar_url'], 'c.png');
      expect(h.data.matchesMembers(['a', 'b']), isFalse);
      expect(h.data.matchesMembers(['a', 'c']), isTrue);
      expect(h.counts['users'], 2);
      h.data.dispose();
    },
  );
  test('catalog TTLs expire; coins are not cached for 60 seconds', () async {
    final h = Harness();
    await h.data.users(['a']);
    await h.data.profiles(['a']);
    await h.data.league('l');
    h.advance();
    await h.data.users(['a']);
    await h.data.profiles(['a']);
    await h.data.league('l');
    expect(h.counts, {'users': 1, 'profiles': 2, 'league': 1});
    h.clock = h.clock.add(const Duration(minutes: 6));
    await h.data.users(['a']);
    await h.data.league('l');
    expect(h.counts['users'], 2);
    expect(h.counts['league'], 2);
    h.data.dispose();
  });
  test(
    'session change invalidates catalogs and rejects old in-flight reads',
    () async {
      final h = Harness();
      await h.data.users(['a']);
      final reply = Completer<ViewRow?>();
      h.delayedTable = () => reply.future;
      final pending = h.data.table();
      h.user = 'new-session';
      final rejected = expectLater(pending, throwsStateError);
      reply.complete({'current_turn': 0});
      await rejected;
      await h.data.users(['a']);
      expect(h.counts['users'], 2);
      h.data.dispose();
    },
  );
  test(
    'disposed screen rejects response and starts no further reads',
    () async {
      final h = Harness();
      final reply = Completer<ViewRow?>();
      h.delayedTable = () => reply.future;
      final pending = h.data.table();
      final rejected = expectLater(pending, throwsStateError);
      h.data.dispose();
      reply.complete({'current_turn': 0});
      await rejected;
      await expectLater(h.data.table(), throwsStateError);
      expect(h.counts['table'], 1);
    },
  );
  test('failed fetch is not cached and retry recovers', () async {
    final h = Harness();
    h.delayedTable = () async => throw StateError('network');
    await expectLater(h.data.table(), throwsStateError);
    h.delayedTable = null;
    expect(await h.data.table(), isNotNull);
    expect(h.counts['table'], 2);
    h.data.dispose();
  });
  test(
    'refresh pipeline never overlaps and runs one trailing reconciliation',
    () async {
      final queue = CoalescedViewRefresh();
      final finish = Completer<void>();
      var calls = 0;
      var active = 0;
      Future<void> action() async {
        calls++;
        active++;
        expect(active, 1);
        if (calls == 1) await finish.future;
        active--;
      }

      final first = queue.run(action);
      final second = queue.run(action);
      final third = queue.run(action);
      finish.complete();
      await Future.wait([first, second, third]);
      expect(calls, 2);
      queue.dispose();
      await queue.run(action);
      expect(calls, 2);
    },
  );
  test('public projection excludes deck and private hands', () {
    expect(GameViewDataSource.tableColumns.split(','), isNot(contains('deck')));
    expect(GameViewDataSource.tableColumns.split(','), isNot(contains('hand')));
  });
}
