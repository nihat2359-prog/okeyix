import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/overlay/app_overlay.dart';

void main() {
  testWidgets('updates navigator content across app builder rebuilds', (
    tester,
  ) async {
    final overlayKey = GlobalKey<OverlayState>();
    final navigatorKey = GlobalKey<NavigatorState>();
    late StateSetter rebuild;
    var revision = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return MaterialApp(
            navigatorKey: navigatorKey,
            builder: (context, child) => AppOverlay(
              overlayKey: overlayKey,
              child: Theme(
                data: ThemeData(
                  primaryColor: revision == 0 ? Colors.red : Colors.blue,
                ),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Text(
                  Theme.of(context).primaryColor == Colors.blue
                      ? 'updated'
                      : 'initial',
                ),
              ),
            ),
          );
        },
      ),
    );
    final effect = OverlayEntry(
      builder: (_) => const Positioned(top: 0, left: 0, child: Text('effect')),
    );
    overlayKey.currentState!.insert(effect);
    rebuild(() => revision++);
    await tester.pumpAndSettle();
    expect(find.text('updated'), findsOneWidget);
    expect(find.text('effect'), findsOneWidget);
    expect(tester.takeException(), isNull);
    effect.remove();
    effect.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
