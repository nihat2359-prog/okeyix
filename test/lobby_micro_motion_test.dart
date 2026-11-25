import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_micro_motion.dart';

void main() {
  testWidgets('button breath repeats at 3500ms without rebuilding its content', (tester) async {
    var builds = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LobbyQuickPlayMotion(
      enabled: true, child: Builder(builder: (_) {
        builds++;
        return const SizedBox(width: 260, height: 55);
      }),
    ))));
    double scale() => tester.widget<ScaleTransition>(find.descendant(
      of: find.byType(LobbyQuickPlayMotion), matching: find.byType(ScaleTransition))).scale.value;
    expect(scale(), 1);
    await tester.pump(const Duration(milliseconds: 900));
    expect(scale(), closeTo(1.025, .0001));
    await tester.pump(const Duration(milliseconds: 900));
    expect(scale(), 1);
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 900));
    expect(scale(), closeTo(1.025, .0001));
    expect(builds, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('live counter includes displayed real and showcase seats', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LobbyLiveIndicator(
      tables: [
        {'_players': [{'user_id': 'human'}]},
        {'is_fake': true, '_players': [{'user_id': 'a'}, {'user_id': 'b'}]},
      ],
    ))));
    expect(find.text('Şu an 3 oyuncu masalarda'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('later cards wait before fading and sliding into place', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LobbyTableEntrance(
      index: 3, child: SizedBox(width: 200, height: 100),
    ))));
    double opacity() => tester.widget<Opacity>(find.byType(Opacity)).opacity;
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(), greaterThan(0));
    expect(opacity(), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });

  testWidgets('reduced motion leaves the lobby without active animation frames', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Scaffold(body: LobbyQuickPlayMotion(enabled: true,
        child: SizedBox(width: 200, height: 55))),
    )));
    await tester.pump(const Duration(seconds: 4));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.widget<ScaleTransition>(find.descendant(
      of: find.byType(LobbyQuickPlayMotion), matching: find.byType(ScaleTransition))).scale.value, 1);
    expect(tester.takeException(), isNull);
  });
}
