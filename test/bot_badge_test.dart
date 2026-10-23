import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/models/player_model.dart';
import 'package:okeyix/ui/avatar_card.dart';
import 'package:okeyix/ui/bot_badge.dart';
import 'package:okeyix/ui/spectator_table_scores.dart';

void main() {
  for (final size in [const Size(480, 270), const Size(568, 320), const Size(844, 390)]) {
  testWidgets('horizontal seats have equal sizes and gifts clear both names at $size', (tester) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final keys = [GlobalKey(), GlobalKey()];
    const names = ['Ali', 'Very long player display name'];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 2; i++)
          AvatarCard(key: keys[i],
            player: PlayerModel(id: '$i', name: names[i], avatarPath: '', coins: 10000),
            position: i == 0 ? AvatarPosition.top : AvatarPosition.bottom,
            progress: .5, giftOriginKey: GlobalKey(), showRating: false),
      ]),
    ))));
    expect(tester.getSize(find.byKey(keys[0])), tester.getSize(find.byKey(keys[1])));
    expect(tester.getSize(find.byKey(keys[0])).width,
      closeTo((size.width * .30).clamp(196.0, 224.0), .01));
    for (var i = 0; i < 2; i++) {
      final card = tester.getRect(find.byKey(keys[i]));
      final gift = Rect.fromCenter(center: Offset(card.right - 16, card.top + 14),
        width: 48, height: 48);
      expect(gift.overlaps(tester.getRect(find.text(names[i]))), isFalse);
    }
    expect(tester.takeException(), isNull);
  });
  }
  testWidgets('bot badge overlays the avatar and gifts no longer reserve a spacer', (tester) async {
    final origin = GlobalKey();
    const name = 'Çok uzun oyuncu kullanıcı adı';
    Future<void> show(bool bot) => tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: AvatarCard(player: PlayerModel(id: 'p', name: name, avatarPath: '',
        coins: 10000, isBot: bot), position: AvatarPosition.top, progress: .5,
        giftOriginKey: origin, showRating: false, showRatingProgress: false),
    ))));
    await show(false);
    final humanSize = tester.getSize(find.byType(AvatarCard));
    final nameWidth = tester.getSize(find.text(name)).width;
    expect(nameWidth, greaterThan(80));
    await show(true);
    expect(tester.getSize(find.byType(AvatarCard)), humanSize);
    expect(tester.getSize(find.text(name)).width, nameWidth);
    final badge = tester.getRect(find.byType(BotBadge));
    final avatar = tester.getRect(find.byKey(origin));
    expect(avatar.contains(badge.topLeft), isTrue);
    expect(avatar.contains(badge.bottomRight), isTrue);
    expect(badge.center.dy, greaterThan(avatar.center.dy));
    expect(tester.takeException(), isNull);
  });
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
