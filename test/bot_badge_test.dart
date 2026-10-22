import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/models/player_model.dart';
import 'package:okeyix/ui/avatar_card.dart';
import 'package:okeyix/ui/bot_badge.dart';
import 'package:okeyix/ui/spectator_table_scores.dart';

void main() {
  for (final bot in [false, true]) {
    testWidgets('game card labels only server-marked bots: $bot', (tester) async {
      final player = PlayerModel(id: 'player', name: 'Uzun Oyuncu Adı',
        avatarPath: '', coins: 10000, isBot: bot);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
        child: AvatarCard(player: player, position: AvatarPosition.top,
          progress: .5, showRating: false, showRatingProgress: false),
      ))));
      expect(find.byType(BotBadge), bot ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('spectator card labels only bots: $bot', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
        child: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: SpectatorPlayerCard(username: 'Uzun oyuncu ismi', coins: 10000,
            avatar: const CircleAvatar(), active: true, progress: .5, isBot: bot)),
      ))));
      expect(find.byType(BotBadge), bot ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
