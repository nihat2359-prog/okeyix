import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/models/player_model.dart';
import 'package:okeyix/ui/avatar_card.dart';
import 'package:okeyix/ui/periodic_ui_builder.dart';
import 'package:okeyix/ui/ambient/sky_planes_overlay.dart';

class CountedAvatar extends AvatarCard {
  final VoidCallback built;
  const CountedAvatar({
    super.key,
    required super.player,
    required super.progress,
    required super.progressReader,
    required super.animateProgress,
    required this.built,
  }) : super(position: AvatarPosition.top);
  @override
  Widget build(BuildContext context) {
    built();
    return super.build(context);
  }
}

void main() {
  testWidgets('turn switch moves visual clock to the active seat', (
    tester,
  ) async {
    var active = 0;
    final reads = [0, 0];
    late StateSetter changeTurn;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) {
              changeTurn = set;
              return Row(
                children: [
                  for (var seat = 0; seat < 2; seat++)
                    AvatarCard(
                      key: ValueKey(seat),
                      player: PlayerModel(
                        id: '$seat',
                        name: 'Oyuncu $seat',
                        avatarPath: 'assets/images/avatars/avatar1.png',
                        coins: 2500,
                        isActive: active == seat,
                      ),
                      position: AvatarPosition.top,
                      progress: 1,
                      progressReader: () {
                        reads[seat]++;
                        return .8;
                      },
                      animateProgress: true,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    var previous = List<int>.of(reads);
    await tester.pump(const Duration(milliseconds: 33));
    expect(reads[0], previous[0] + 1);
    expect(reads[1], previous[1]);
    changeTurn(() => active = 1);
    await tester.pump();
    previous = List<int>.of(reads);
    await tester.pump(const Duration(milliseconds: 33));
    expect(reads[0], previous[0]);
    expect(reads[1], previous[1] + 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('33ms ring ticks do not rebuild avatar card or parent', (
    tester,
  ) async {
    var rootBuilds = 0;
    var avatarBuilds = 0;
    var reads = 0;
    var remaining = 1.0;
    final player = PlayerModel(
      id: 'a',
      name: 'Deniz',
      avatarPath: 'assets/images/avatars/avatar1.png',
      coins: 2500,
      isActive: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              rootBuilds++;
              return CountedAvatar(
                player: player,
                progress: remaining,
                progressReader: () {
                  reads++;
                  return remaining;
                },
                animateProgress: true,
                built: () => avatarBuilds++,
              );
            },
          ),
        ),
      ),
    );
    final initialReads = reads;
    for (var i = 0; i < 30; i++) {
      remaining -= .02;
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(rootBuilds, 1);
    expect(avatarBuilds, 1);
    expect(reads - initialReads, 30);
    final ring = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .firstWhere(
          (w) => w.painter.runtimeType.toString() == '_CircleTimerPainter',
        );
    expect((ring.painter as dynamic).progress, closeTo(.4, .001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'visual timer stops with TickerMode and resumes with fresh value',
    (tester) async {
      var reads = 0;
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return TickerMode(
                enabled: enabled,
                child: PeriodicUiBuilder(
                  interval: const Duration(milliseconds: 33),
                  builder: (_) {
                    reads++;
                    return const Text('ring');
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 33));
      update(() => enabled = false);
      await tester.pump();
      final paused = reads;
      await tester.pump(const Duration(seconds: 1));
      expect(reads, paused);
      update(() => enabled = true);
      await tester.pump();
      final resumed = reads;
      await tester.pump(const Duration(milliseconds: 33));
      expect(reads, resumed + 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'visual timer stops in background and can be disabled for inactive seat',
    (tester) async {
      var reads = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      Future<void> mount(bool active) => tester.pumpWidget(
        MaterialApp(
          home: PeriodicUiBuilder(
            interval: const Duration(milliseconds: 33),
            enabled: active,
            builder: (_) {
              reads++;
              return const SizedBox();
            },
          ),
        ),
      );
      await mount(true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = reads;
      await tester.pump(const Duration(seconds: 1));
      expect(reads, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final resumed = reads;
      await tester.pump(const Duration(milliseconds: 33));
      expect(reads, resumed + 1);
      await mount(false);
      final disabled = reads;
      await tester.pump(const Duration(seconds: 1));
      expect(reads, disabled);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('covered route stops visual timer and popping resumes it', (
    tester,
  ) async {
    var reads = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: Scaffold(
          body: PeriodicUiBuilder(
            interval: const Duration(milliseconds: 33),
            builder: (_) {
              reads++;
              return const Text('game');
            },
          ),
        ),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('menu')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final hidden = reads;
    await tester.pump(const Duration(seconds: 1));
    expect(reads, hidden);
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final resumed = reads;
    await tester.pump(const Duration(milliseconds: 33));
    expect(reads, resumed + 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('ambient ticker stops on background and resumes without errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkyPlanesOverlay(planeCount: 2))),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final before = tester.getTopLeft(
      find.byIcon(Icons.airplanemode_active_rounded).first,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.getTopLeft(find.byIcon(Icons.airplanemode_active_rounded).first),
      before,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
