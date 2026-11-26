import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/avatar_preset.dart';
import 'package:okeyix/ui/avatar_selection_screen.dart';

void main() {
  for (final size in [const Size(480, 270), const Size(640, 360)]) {
    testWidgets('new funny avatars can be selected in landscape $size', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final presets = avatarPresets.where((p) => p.id.contains('_komik_')).toList();
      expect(presets.length, 6);
      expect(presets.where((p) => p.gender == 'female').length, 3);
      expect(presets.where((p) => p.gender == 'male').length, 3);
      expect(avatarPresets.first.id, 'kadin_01');
      expect(avatarPresetByRef('erkek_01').imageUrl, 'assets/images/avatars/avatar8.png');
      for (final preset in presets) {
        String? result;
        expect(preset.isPremium, isFalse);
        expect(preset.unlockCost, 0);
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<String>(MaterialPageRoute(
                builder: (_) => AvatarSelectionScreen(
                  ownedPremiumAvatarRefs: <String>{}, userCoins: 0,
                ),
              ));
            },
            child: const Text('choose'),
          ),
        ))));
        await tester.tap(find.text('choose'));
        await tester.pumpAndSettle();
        final image = find.byWidgetPredicate((widget) => widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == preset.imageUrl);
        expect(image, findsOneWidget);
        await tester.ensureVisible(image);
        await tester.pumpAndSettle();
        await tester.tap(find.ancestor(of: image, matching: find.byType(InkWell)).first);
        await tester.pumpAndSettle();
        expect(result, preset.imageUrl);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
