import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/screens/journey_screen.dart';
import 'package:okeyix/ui/lobby/lobby_bottom_dock.dart';

void main() {
  for (final size in [const Size(480, 270), const Size(844, 390)]) {
    testWidgets(
      'Journey dock opens and returns at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                bottomNavigationBar: LobbyBottomDock(
                  left: const Text('Lobi'),
                  center: LobbyDockCreate(onTap: () {}),
                  right: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final label in [
                        'Yolculuk',
                        'Davet',
                        'Sıralama',
                        'Sosyal',
                        'Mesajlar',
                      ])
                        LobbyDockAction(
                          label: label,
                          icon: Icons.explore_outlined,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const JourneyScreen(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Yolculuk'));
        await tester.pumpAndSettle();
        expect(find.byType(JourneyScreen), findsOneWidget);
        expect(find.text('Türkiye'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Lobiye dön'));
        await tester.pumpAndSettle();
        expect(find.byType(JourneyScreen), findsNothing);
        expect(find.text('Lobi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }
}
