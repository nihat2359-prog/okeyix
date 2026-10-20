import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/models/profile_statistics.dart';
import 'package:okeyix/ui/player_profile_card.dart';

const stats = ProfileStatistics(
  wins: 4,
  losses: 2,
  normalWins: 1,
  okeyWins: 2,
  doubleWins: 2,
  okeyDoubleWins: 1,
  careerWins: 4,
  careerLosses: 2,
  previousWins: 0,
  hasCareerSnapshot: true,
);

Widget card({
  String userId = 'one',
  Future<ProfileStatistics> Function()? load,
  VoidCallback? close,
  VoidCallback? edit,
  double scale = 1,
  int? wins = 4,
  int? losses = 2,
  List<ProfileCardAction>? actions,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SafeArea(
      child: PlayerProfileCard(
        userId: userId,
        username: 'Oyuncu_İstanbul_Uzun_İsim',
        avatar: const ColoredBox(color: Colors.teal),
        rating: 23900,
        coins: 12500,
        careerWins: wins,
        careerLosses: losses,
        status: 'Bu senin profilin',
        statusColor: Colors.green,
        loadStatistics: load ?? () async => stats,
        onClose: close ?? () {},
        actions:
            actions ??
            [
              ProfileCardAction(
                Icons.edit,
                label: 'Düzenle',
                onPressed: edit ?? () {},
              ),
              ProfileCardAction(
                Icons.card_giftcard,
                label: 'Hediye Geçmişi',
                onPressed: () {},
              ),
              ProfileCardAction(
                Icons.block,
                secondary: true,
                label: 'Engelle',
                color: Colors.red,
                onPressed: () {},
              ),
            ],
      ),
    ),
  ),
);

void main() {
  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(667, 375),
  ]) {
    testWidgets(
      'all profile content fits without scrolling in safe landscape $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(
          left: 24,
          right: 24,
          bottom: 21,
        );
        tester.view.viewPadding = const FakeViewPadding(
          left: 24,
          right: 24,
          bottom: 21,
        );
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await tester.pumpWidget(
          card(
            scale: 1.3,
            userId: '00000000-0000-4000-8000-000000000001',
            actions: [
              for (final label in [
                'Hediye',
                'Çıkar',
                'Engelle',
                'Şikayet',
                'Karşılaştır',
              ])
                ProfileCardAction(Icons.person, label: label, onPressed: () {}),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsNothing);
        final footerTop = tester.getTopLeft(find.text('Hediye')).dy - 20;
        for (final label in [
          'Önceki\nkazanımlar',
          'Normal',
          'Okeyli',
          'Çiftli',
        ]) {
          final finder = find.text(label);
          expect(finder.hitTestable(), findsOneWidget);
          expect(tester.getBottomRight(finder).dy, lessThan(footerTop));
        }
        var actions = 0;
        for (final label in [
          'Hediye',
          'Çıkar',
          'Engelle',
          'Şikayet',
          'Karşılaştır',
        ]) {
          expect(find.text(label).hitTestable(), findsOneWidget);
          actions++;
        }
        expect(actions, 5);
        for (final state in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          expect(state.position.maxScrollExtent, 0);
        }
      },
    );
  }
  test('validates finish overlap and computes completed-hand rate', () {
    expect(stats.total, 6);
    expect(stats.winRate, closeTo(66.6667, .001));
    expect(
      () => ProfileStatistics.fromJson({
        'wins': 1,
        'losses': 0,
        'normal_wins': 1,
        'okey_wins': 1,
        'double_wins': 0,
        'okey_double_wins': 0,
      }),
      throwsFormatException,
    );
    expect(() => ProfileStatistics.fromJson({}), throwsFormatException);
  });

  testWidgets('career and previous wins use the same RPC snapshot', (
    tester,
  ) async {
    final data = ProfileStatistics.fromJson({
      'wins': 4,
      'losses': 1,
      'normal_wins': 1,
      'okey_wins': 2,
      'double_wins': 2,
      'okey_double_wins': 1,
      'career_wins': 504,
      'career_losses': 201,
      'previous_wins': 500,
    });
    await tester.pumpWidget(
      card(wins: 999, losses: 999, load: () async => data),
    );
    await tester.pumpAndSettle();
    expect(find.text('504'), findsOneWidget);
    expect(find.text('201'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('999'), findsNothing);
    expect(find.text('Önceki\nkazanımlar'), findsOneWidget);
    final surface = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.gradient is LinearGradient)
        .any(
          (d) => (d.gradient! as LinearGradient).colors.every((c) => c.a < 1),
        );
    expect(surface, isTrue);
  });

  for (final size in [
    const Size(568, 320),
    const Size(667, 375),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('landscape $size, text $scale; actions stay visible', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var closed = false;
        var edited = false;
        await tester.pumpWidget(
          card(
            scale: scale,
            close: () => closed = true,
            edit: () => edited = true,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Galibiyet'), findsOneWidget);
        expect(find.text('%66.7'), findsOneWidget);
        expect(find.text('Karşılaştır'), findsNothing);
        await tester.tap(find.text('Düzenle'));
        expect(edited, isTrue);
        await tester.tap(find.byTooltip('Kapat'));
        expect(closed, isTrue);
        expect(find.text('Engelle'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('loads once, retries errors, and never shows errors as zero', (
    tester,
  ) async {
    var calls = 0;
    Future<ProfileStatistics> load() async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return stats;
    }

    await tester.pumpWidget(card(load: load));
    await tester.pumpAndSettle();
    expect(find.text('Bitiş kayıtları yüklenemedi'), findsOneWidget);
    expect(find.text('Galibiyet'), findsOneWidget);
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(card(load: load));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Galibiyet'), findsOneWidget);
  });

  testWidgets('late old-player response cannot populate new profile', (
    tester,
  ) async {
    final old = Completer<ProfileStatistics>();
    final next = Completer<ProfileStatistics>();
    await tester.pumpWidget(card(load: () => old.future));
    await tester.pumpWidget(card(userId: 'two', load: () => next.future));
    old.complete(stats);
    await tester.pump();
    expect(find.text('Normal'), findsNothing);
    next.complete(
      const ProfileStatistics(
        wins: 0,
        losses: 0,
        normalWins: 0,
        okeyWins: 0,
        doubleWins: 0,
        okeyDoubleWins: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Önceki\nkazanımlar'), findsOneWidget);
    expect(find.text('%66.7'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '500 career games survive missing new history and failed detail fetch',
    (tester) async {
      await tester.pumpWidget(
        card(
          wins: 100,
          losses: 400,
          load: () async => const ProfileStatistics(
            wins: 0,
            losses: 0,
            normalWins: 0,
            okeyWins: 0,
            doubleWins: 0,
            okeyDoubleWins: 0,
            careerWins: 100,
            careerLosses: 400,
            previousWins: 100,
            hasCareerSnapshot: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('100'), findsNWidgets(2));
      expect(find.text('400'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('%20.0'), findsOneWidget);
      expect(find.text('Henüz detaylı kayıt yok'), findsNothing);
      expect(find.text('Önceki\nkazanımlar'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
    },
  );

  testWidgets(
    'six other-player actions plus future comparison fit and remain reachable',
    (tester) async {
      tester.view.physicalSize = const Size(568, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reportTapped = false;
      await tester.pumpWidget(
        card(
          scale: 1.3,
          actions: [
            ProfileCardAction(
              Icons.person_add,
              label: 'Ekle',
              onPressed: () {},
            ),
            ProfileCardAction(
              Icons.card_giftcard,
              label: 'Hediye',
              onPressed: () {},
            ),
            // Test the reserved primary-action capacity without adding a live feature.
            ProfileCardAction(
              Icons.compare_arrows,
              label: 'Karşılaştır',
              onPressed: () {},
            ),
            ProfileCardAction(
              Icons.person_remove,
              label: 'Çıkar',
              secondary: true,
              onPressed: () {},
            ),
            ProfileCardAction(
              Icons.block,
              label: 'Engelle',
              secondary: true,
              onPressed: () {},
            ),
            ProfileCardAction(
              Icons.flag,
              label: 'Şikayet',
              secondary: true,
              onPressed: () => reportTapped = true,
            ),
            ProfileCardAction(
              Icons.close,
              label: 'Reddet',
              secondary: true,
              onPressed: () {},
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Karşılaştır'), findsOneWidget);
      await tester.tap(find.byTooltip('Diğer işlemler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Şikayet'));
      await tester.pumpAndSettle();
      expect(reportTapped, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
