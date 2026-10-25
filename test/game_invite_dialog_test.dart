import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/game_invite_dialog.dart';

void main() {
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    testWidgets('invite dialog $size opens before the slow list and shows compact players', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<List<Map<String, dynamic>>>();
      final sending = Completer<void>();
      var sends = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: GameInviteDialog(
        loadPlayers: () => pending.future,
        avatarBuilder: (_, name) => CircleAvatar(child: Text(name[0])),
        onInvite: (_) { sends++; return sending.future; },
      ))));
      expect(find.text('Uygun oyuncular listeleniyor…'), findsOneWidget);
      expect(find.byKey(const ValueKey('invite-close')), findsOneWidget);
      pending.complete(List.generate(30, (i) => {
        'id': '$i', 'username': 'Oyuncu $i', 'rating': 1200,
        'coins': 1000, 'is_online': i < 20,
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
      expect(tester.takeException(), isNull);
    });
  }
}
