import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/models/player_comparison.dart';
import 'package:okeyix/models/profile_statistics.dart';
import 'package:okeyix/screens/player_comparison_screen.dart';
import 'package:okeyix/services/comparison_image_share.dart';
import 'package:okeyix/ui/comparison_share_dialog.dart';

const leftPlayer = ComparedPlayer(
  id: 'viewer',
  name: 'Oyuncu_İstanbul_Uzun_İsim',
  league: 'Acemiler',
  stats: ProfileStatistics(
    wins: 2,
    losses: 1,
    normalWins: 1,
    okeyWins: 1,
    doubleWins: 1,
    okeyDoubleWins: 1,
  ),
);
const rightPlayer = ComparedPlayer(
  id: 'opponent',
  name: 'Rakip_Uzun_İsim',
  league: 'Ustalar',
  stats: ProfileStatistics(
    wins: 1,
    losses: 2,
    normalWins: 0,
    okeyWins: 1,
    doubleWins: 0,
    okeyDoubleWins: 0,
  ),
);
PlayerComparison comparison({int left = 2, int right = 1}) => PlayerComparison(
  left: ComparedPlayer(
    id: leftPlayer.id,
    name: leftPlayer.name,
    league: leftPlayer.league,
    stats: ProfileStatistics(
      wins: left,
      losses: right,
      normalWins: left > 0 ? 1 : 0,
      okeyWins: left > 1 ? left - 1 : 0,
      doubleWins: left > 1 ? left - 1 : 0,
      okeyDoubleWins: left > 1 ? left - 1 : 0,
    ),
  ),
  right: ComparedPlayer(
    id: rightPlayer.id,
    name: rightPlayer.name,
    league: rightPlayer.league,
    stats: ProfileStatistics(
      wins: right,
      losses: left,
      normalWins: 0,
      okeyWins: right,
      doubleWins: 0,
      okeyDoubleWins: 0,
    ),
  ),
  leftWins: left,
  rightWins: right,
  asOf: DateTime.utc(2026, 10, 20),
);

Widget screen({
  Future<PlayerComparison> Function(String, String)? load,
  String target = 'opponent',
  Future<void> Function(BuildContext, PlayerComparison)? share,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)),
    child: child!,
  ),
  home: PlayerComparisonScreen(
    viewerId: 'viewer',
    opponentId: target,
    load: load ?? (_, _) async => comparison(),
    share: share,
  ),
);

void main() {
  test('general totals cannot be shown as mutual details', () {
    Map<String, dynamic> person(String id, int wins, int losses) => {
      'id': id,
      'username': id,
      'wins': wins,
      'losses': losses,
      'normal_wins': wins,
      'okey_wins': 0,
      'double_wins': 0,
      'okey_double_wins': 0,
    };
    final mutual = <String, dynamic>{
      'scope': 'head_to_head',
      'left_player': person('viewer', 0, 0),
      'right_player': person('opponent', 0, 0),
      'left_wins': 0,
      'right_wins': 0,
      'as_of': '2026-10-20T00:00:00Z',
    };
    expect(
      PlayerComparison.fromJson(
        mutual,
        viewerId: 'viewer',
        opponentId: 'opponent',
      ).left.stats.total,
      0,
    );
    expect(
      () => PlayerComparison.fromJson(
        {...mutual, 'left_player': person('viewer', 1, 1)},
        viewerId: 'viewer',
        opponentId: 'opponent',
      ),
      throwsFormatException,
    );
    expect(
      () => PlayerComparison.fromJson(
        {...mutual}..remove('scope'),
        viewerId: 'viewer',
        opponentId: 'opponent',
      ),
      throwsFormatException,
    );
  });
  test('empty, tie and winner presentation use head-to-head totals', () {
    expect(comparison().meetings, 3);
    expect(comparison().leftShare, closeTo(2 / 3, .001));
    expect(
      comparison(left: 0, right: 0).resultLabel,
      'Henüz birbirinize karşı tamamlanmış el yok',
    );
    expect(comparison(left: 1, right: 1).resultLabel, 'Rekabette eşitlik var');
    expect(comparison().resultLabel, contains(leftPlayer.name));
  });

  test('response for another pair is rejected', () {
    expect(
      () => PlayerComparison.fromJson(
        {
          'scope': 'head_to_head',
          'left_player': {
            'id': 'intruder',
            'username': 'Other',
            'wins': 0,
            'losses': 0,
            'normal_wins': 0,
            'okey_wins': 0,
            'double_wins': 0,
            'okey_double_wins': 0,
          },
          'right_player': {
            'id': 'opponent',
            'username': 'Other',
            'wins': 0,
            'losses': 0,
            'normal_wins': 0,
            'okey_wins': 0,
            'double_wins': 0,
            'okey_double_wins': 0,
          },
          'left_wins': 0,
          'right_wins': 0,
          'as_of': '2026-10-20T00:00:00Z',
        },
        viewerId: 'viewer',
        opponentId: 'opponent',
      ),
      throwsFormatException,
    );
  });

  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(844, 390),
  ]) {
    testWidgets(
      'comparison fits safe landscape $size and sharing uses loaded data',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(
          left: 24,
          right: 24,
          bottom: 21,
        );
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        PlayerComparison? shared;
        await tester.pumpWidget(
          screen(
            share: (_, data) async {
              shared = data;
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(leftPlayer.name), findsOneWidget);
        expect(find.text('VS'), findsOneWidget);
        expect(find.text('Normal bitiş'), findsOneWidget);
        expect(find.byType(SingleChildScrollView), findsNothing);
        await tester.tap(find.text('Paylaş'));
        expect(shared?.leftWins, 2);
        expect(shared?.rightWins, 1);
      },
    );
  }

  testWidgets('failed fetch cannot present fabricated 0-0 and supports retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      screen(
        load: (_, _) async {
          if (++calls == 1) throw StateError('offline');
          return comparison(left: 0, right: 0);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Karşılaştırma yüklenemedi'), findsOneWidget);
    expect(find.text('VS'), findsNothing);
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(find.text('Henüz birbirinize karşı tamamlanmış el yok'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('stale profile comparison never replaces a newly opened target', (
    tester,
  ) async {
    final old = Completer<PlayerComparison>();
    final next = Completer<PlayerComparison>();
    await tester.pumpWidget(screen(load: (_, _) => old.future));
    await tester.pumpWidget(
      screen(target: 'next', load: (_, _) => next.future),
    );
    old.complete(comparison());
    await tester.pump();
    expect(find.text('VS'), findsNothing);
    next.complete(comparison(left: 1, right: 1));
    await tester.pumpAndSettle();
    expect(find.text('Rekabette eşitlik var'), findsOneWidget);
  });

  testWidgets(
    'dedicated story exports 1080x1920 PNG without user IDs or controls',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FittedBox(
              child: RepaintBoundary(
                key: key,
                child: ComparisonShareCard(data: comparison()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('viewer'), findsNothing);
      expect(find.text('opponent'), findsNothing);
      expect(find.text('Paylaş'), findsNothing);
      expect(find.text('VS'), findsOneWidget);
      expect(tester.getSize(find.byKey(key)), const Size(360, 640));
      await tester.runAsync(() async {
        final png = await captureComparisonCard(key);
        final codec = await ui.instantiateImageCodec(png);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 1080);
        expect(image.height, 1920);
        image.dispose();
        codec.dispose();
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('share preview controls fit a small safe landscape display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 270);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(
      left: 24,
      right: 24,
      bottom: 21,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paylaş'));
    await tester.pumpAndSettle();
    expect(find.text('REKABETİ PAYLAŞ'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('comparison-share-close')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('comparison-share-close')));
    await tester.pumpAndSettle();
  });

  test(
    'native bridge receives a real cached PNG and anchor, without identity arguments',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final temporary = await Directory.systemTemp.createTemp(
        'okeyix_compare_test_',
      );
      addTearDown(() async {
        await temporary.delete(recursive: true);
      });
      const channel = MethodChannel('comparison_test');
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = ComparisonImageShare(
        temporaryDirectory: () async => temporary,
        channel: channel,
      );
      final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
      await service.share(bytes, const Rect.fromLTWH(10, 20, 90, 40));
      expect(received?.method, 'shareComparison');
      final args = Map<String, dynamic>.from(received!.arguments as Map);
      expect(args.keys.toSet(), {'path', 'x', 'y', 'width', 'height'});
      expect(await File(args['path'] as String).readAsBytes(), bytes);
      expect(args['width'], 90);
      await expectLater(
        service.share(Uint8List(0), Rect.zero),
        throwsFormatException,
      );
    },
  );
}
