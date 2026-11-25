import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/lobby/campaign_dialog.dart';

void main() {
  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(844, 390),
    const Size(932, 430),
  ]) {
    for (final title in [null, 'Okeyix yenilendi! ' * 12]) {
      testWidgets('campaign fits landscape $size, title: ${title != null}', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                size: size,
                padding: const EdgeInsets.fromLTRB(44, 0, 44, 21),
                textScaler: TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => CampaignDialog(imageUrl: '', title: title),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final panel = tester.getRect(
          find.byKey(const ValueKey('campaign-panel')),
        );
        expect(panel.left, greaterThanOrEqualTo(44));
        expect(panel.right, lessThanOrEqualTo(size.width - 44));
        expect(panel.top, greaterThanOrEqualTo(0));
        expect(panel.bottom, lessThanOrEqualTo(size.height - 21));
        final art = tester.getRect(find.byKey(const ValueKey('campaign-art')));
        final action = tester.getRect(find.text('TAMAM'));
        expect(art.right, lessThan(action.left));
        expect(action.bottom, lessThanOrEqualTo(panel.bottom));
        await tester.tap(
          title == null ? find.text('TAMAM') : find.byTooltip('Kapat'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CampaignDialog), findsNothing);
      });
    }
  }
}
