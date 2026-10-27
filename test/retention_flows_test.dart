// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/daily_reward_service.dart';
import 'package:okeyix/services/player_name_reminder.dart';
import 'package:okeyix/ui/player_name_reminder_dialog.dart';
import 'package:okeyix/ui/reward_dialogs.dart';
import 'package:okeyix/ui/profile_setup_dialog.dart';
import 'package:okeyix/services/reward_audio.dart';

const rewards = [2500, 3000, 3500, 4000, 4500, 5000, 7500];
void ignoreSound(RewardSound _) {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final text = FontLoader('Montserrat')
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([text.load(), icons.load()]);
  });
  for (final kind in ['week', 'name']) {
    testWidgets('retention visual $kind', (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(RepaintBoundary(key: const ValueKey('retention-capture'),
        child: MaterialApp(theme: ThemeData(fontFamily: 'Montserrat'),
          home: Scaffold(backgroundColor: const Color(0xFF0A101A),
            body: kind == 'week' ? DailyBonusDialog(amount: 7500, rewardDay: 7,
              weeklyRewards: rewards, onSound: ignoreSound, onClaim: () async => true)
              : const PlayerNameReminderDialog()))));
      await tester.pumpAndSettle();
      if (kind == 'week') {
        await tester.runAsync(() async {
          final context = tester.element(find.byType(DailyBonusDialog));
          await precacheImage(const AssetImage('assets/images/coins/coins_huge.png'), context);
          if (context.mounted) await precacheImage(const AssetImage('assets/images/table.png'), context);
        });
        await tester.pumpAndSettle();
      }
      await expectLater(find.byKey(const ValueKey('retention-capture')),
        matchesGoldenFile('goldens/retention_$kind.png'));
    });
  }
  test(
    'name reminder waits for a game, respects custom names and account preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final reminder = PlayerNameReminder(prefs);
      bool show({
        String uid = 'one',
        String name = 'Oyuncu_ABC',
        int games = 1,
      }) => reminder.shouldShow(userId: uid, name: name, games: games);
      expect(show(games: 0), isFalse);
      expect(show(name: 'Serkan'), isFalse);
      expect(show(), isTrue);
      expect(show(uid: 'two'), isTrue);
      expect(show(), isTrue);
      await reminder.dismiss('one');
      expect(show(), isFalse);
      expect(
        PlayerNameReminder(
          prefs,
        ).shouldShow(userId: 'one', name: 'Oyuncu_ABC', games: 3),
        isFalse,
      );
    },
  );
  test(
    'daily service uses server amounts and only missing RPC enables legacy fallback',
    () async {
      var missing = false;
      var denied = false;
      var claimed = true;
      final calls = <String>[];
      final client = SupabaseClient(
        'https://fixture.invalid',
        'test',
        httpClient: MockClient((request) async {
          final route = request.url.path.split('/').last;
          calls.add(route);
          final body = missing
              ? {'code': 'PGRST202', 'message': 'missing'}
              : denied
              ? {'code': '42501', 'message': 'denied'}
              : route == 'okeyix_daily_reward_status'
              ? {
                  'day': 7,
                  'amount': 7500,
                  'rewards': rewards,
                  'available': true,
                  'day_key': 'daily_bonus:2026-10-27',
                }
              : {'credited': claimed, 'amount': claimed ? 7500 : 0, 'day': 7};
          return http.Response(
            jsonEncode(body),
            missing || denied ? 400 : 200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final service = DailyRewardService(client);
      final status = (await service.status())!;
      expect(status.day, 7);
      expect(await service.claim(status), 7500);
      claimed = false;
      expect(await service.claim(status), 0);
      denied = true;
      await expectLater(service.status(), throwsA(isA<PostgrestException>()));
      denied = false;
      missing = true;
      expect(await service.status(), isNull);
      expect(calls, isNot(contains('claim_daily_bonus')));
    },
  );
  test('later and unchanged edit remain eligible; old daily records do not suppress reminders', () async {
    SharedPreferences.setMockInitialValues({'name_reminder_seen_one': '2026-10-27',
      'name_reminder_seen_v2_one': '2026-10-27'});
    final prefs = await SharedPreferences.getInstance();
    final reminder = PlayerNameReminder(prefs);
    expect(reminder.shouldShow(userId: 'one', name: 'Oyuncu_ABC', games: 1), isTrue);
    expect(reminder.shouldShow(userId: 'one', name: 'Oyuncu_ABC', games: 1), isTrue);
    expect(PlayerNameReminder(prefs).shouldShow(userId: 'one', name: 'Oyuncu_ABC', games: 1), isTrue);
    expect(reminder.shouldShow(userId: 'one', name: 'Deniz', games: 1), isFalse);
    await reminder.dismiss('one');
    expect(reminder.shouldShow(userId: 'one', name: 'Oyuncu_ABC', games: 1), isFalse);
  });
  testWidgets(
    'name action opens existing editor focused with the generated name selected',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileSetupDialog(
              forceComplete: false,
              focusUsername: true,
              initialUsername: 'Oyuncu_ABC',
              initialAvatarRef: 'assets/images/avatars/avatar1.png',
              currentUserId: 'test',
              currentCoins: 10000,
              renameCoinCost: 1000,
              freeRenameUsed: false,
              ownedPremiumAvatarRefs: {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      expect(
        field.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 10),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(568, 320), const Size(844, 390)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'weekly reward fits $size text $scale and only celebrates confirmed credit',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: DailyBonusDialog(
                    amount: 7500,
                    rewardDay: 7,
                    weeklyRewards: rewards,
                    onSound: ignoreSound,
                    onClaim: () async => true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('reward-day-7')), findsOneWidget);
          expect(find.text('Harika! Kazandın.'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const ValueKey('reward-action')));
          await tester.pumpAndSettle();
          expect(find.text('Harika! Kazandın.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'name reminder fits $size text $scale and returns never-again with edit',
        (tester) async {
          await tester.binding.setSurfaceSize(size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          PlayerNameReminderResult? result;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async {
                        result = await showDialog<PlayerNameReminderResult>(
                          context: context,
                          builder: (_) => const PlayerNameReminderDialog(),
                        );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pump();
          await tester.ensureVisible(find.text('Adımı seç'));
          await tester.tap(find.text('Adımı seç'));
          await tester.pumpAndSettle();
          expect(result?.edit, isTrue);
          expect(result?.neverAgain, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
