import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/game_invite_dialog.dart';

void main() {
  test('last seen handles missing, invalid and recent timestamps', () {
    final now = DateTime.utc(2026, 10, 27, 12);
    expect(inviteLastSeenLabel(null, now: now), 'Son görülme: bilinmiyor');
    expect(inviteLastSeenLabel('bad', now: now), 'Son görülme: bilinmiyor');
    expect(inviteLastSeenLabel(now.toIso8601String(), now: now), 'Son görülme: az önce');
    expect(inviteLastSeenLabel(now.subtract(const Duration(minutes: 7)), now: now), 'Son görülme: 7 dk önce');
    expect(inviteLastSeenLabel(now.subtract(const Duration(hours: 3)), now: now), 'Son görülme: 3 sa önce');
    expect(inviteLastSeenLabel(now.subtract(const Duration(days: 2)), now: now), 'Son görülme: 2 gün önce');
  });
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    for (final scale in [1.0, 2.0]) {
    testWidgets('invite dialog $size text $scale opens before the slow list and shows compact players', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<List<Map<String, dynamic>>>();
      final sending = Completer<void>();
      var sends = 0;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(body: GameInviteDialog(
        loadPlayers: () => pending.future,
        avatarBuilder: (_, name) => CircleAvatar(child: Text(name[0])),
        onInvite: (_) { sends++; return sending.future; },
      ))));
      expect(find.text('Uygun oyuncular listeleniyor…'), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-close')), findsOneWidget);
      pending.complete(List.generate(30, (i) => {
        'id': '$i', 'username': 'Oyuncu $i', 'rating': 1200,
        'coins': 1000, 'is_online': i < 20,
        'last_seen_at': i == 20 ? DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String() : null,
      }));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('invite-player-3')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('invite-player-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('invite-player-0')));
      expect(sends, 1);
      sending.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Çevrimdışı (10)'));
      await tester.pumpAndSettle();
      expect(find.text('Son görülme: bilinmiyor'), findsWidgets);
      expect(find.text('Son görülme: 3 sa önce'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    }
  }
}
