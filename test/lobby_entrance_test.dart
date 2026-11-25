import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/lobby_entrance.dart';

class _MountProbe extends StatefulWidget {
  final VoidCallback onMount;
  const _MountProbe({required this.onMount});
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const LobbyEntrance(
    key: ValueKey('after-route'),
    from: Offset(-.07, 0),
    child: Text('League'),
  );
}

void main() {
  testWidgets(
    'lobby mounts once and content enters after the scene is visible',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      var mounts = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('Login')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.pushReplacement(
        lobbyCinemaRoute(
          login: const Text('Outgoing login'),
          lobby: Scaffold(body: _MountProbe(onMount: () => mounts++)),
        ),
      );
      await tester.pump();
      await tester.pump();
      final entrance = find.byKey(const ValueKey('after-route'));
      FadeTransition fade() => tester.widget<FadeTransition>(
        find
            .descendant(of: entrance, matching: find.byType(FadeTransition))
            .first,
      );
      final firstElement = tester.element(entrance);
      await tester.pump(const Duration(milliseconds: 350));
      expect(fade().opacity.value, 0);
      for (var i = 0; i < 13; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(mounts, 1);
      expect(tester.element(entrance), same(firstElement));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(fade().opacity.value, greaterThan(0));
      expect(fade().opacity.value, lessThan(1));
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(fade().opacity.value, 1);
      expect(mounts, 1);
      expect(find.text('Outgoing login'), findsNothing);
    },
  );
  testWidgets('cinematic route crossfades both scenes over 550ms', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('Login')),
      ),
    );
    await tester.pumpAndSettle();
    final route = lobbyCinemaRoute(
      login: const ColoredBox(key: ValueKey('outgoing'), color: Colors.green),
      lobby: const Scaffold(key: ValueKey('incoming'), body: Text('Lobby')),
    );
    nav.currentState!.pushReplacement(route);
    await tester.pump();
    await tester.pump();
    double scale(String key) => tester
        .widget<ScaleTransition>(
          find
              .ancestor(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(ScaleTransition),
              )
              .first,
        )
        .scale
        .value;
    double opacity(String key) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(route.transitionDuration, const Duration(milliseconds: 550));
    expect(scale('outgoing'), 1);
    expect(scale('incoming'), 1.05);
    await tester.pump(const Duration(milliseconds: 275));
    final midpoint = Curves.easeInOutCubic.transform(.5);
    expect(scale('outgoing'), closeTo(1 - .06 * midpoint, .0001));
    expect(scale('incoming'), closeTo(1.05 - .05 * midpoint, .0001));
    expect(opacity('outgoing'), closeTo(1 - midpoint, .0001));
    expect(opacity('incoming'), closeTo(midpoint, .0001));
    await tester.pumpAndSettle();
    expect(route.animation!.value, 1);
    expect(find.byKey(const ValueKey('incoming')), findsOneWidget);
    expect(find.byKey(const ValueKey('outgoing')), findsNothing);
  });

  for (final size in [
    const Size(568, 320),
    const Size(640, 360),
    const Size(852, 393),
  ]) {
    testWidgets('stagger and directional entrances settle at 350ms at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Widget scene() => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      Expanded(
                        child: LobbyEntrance(
                          key: ValueKey('entry-$i'),
                          from: const Offset(-.07, 0),
                          delay: Duration(milliseconds: i * 40),
                          child: ColoredBox(
                            color: Colors.green,
                            child: Center(child: Text('$i')),
                          ),
                        ),
                      ),
                    const Expanded(
                      child: LobbyEntrance(
                        key: ValueKey('quick'),
                        from: Offset(.07, 0),
                        child: ColoredBox(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                height: 52,
                child: LobbyEntrance(
                  key: ValueKey('dock'),
                  from: Offset(0, .22),
                  child: ColoredBox(color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(scene());
      await tester.pump();
      FadeTransition fade(String key) => tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      await tester.pump(const Duration(milliseconds: 39));
      expect(fade('entry-0').opacity.value, greaterThan(0));
      expect(fade('entry-1').opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 81));
      expect(fade('entry-2').opacity.value, greaterThan(0));
      expect(fade('entry-4').opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 230));
      for (final key in ['entry-0', 'entry-4', 'quick', 'dock']) {
        expect(fade(key).opacity.value, 1);
        final slide = tester.widget<SlideTransition>(
          find
              .descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(SlideTransition),
              )
              .first,
        );
        expect(slide.position.value, Offset.zero);
      }
      // A normal parent/data rebuild does not replay the entrance.
      await tester.pumpWidget(scene());
      expect(fade('entry-4').opacity.value, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion makes the entrance immediate', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: LobbyEntrance(
            from: Offset(-.07, 0),
            delay: Duration(milliseconds: 160),
            child: Text('Ready'),
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<FadeTransition>(find.byType(FadeTransition).first)
          .opacity
          .value,
      1,
    );
    expect(
      tester
          .widget<SlideTransition>(find.byType(SlideTransition).first)
          .position
          .value,
      Offset.zero,
    );
  });
}
