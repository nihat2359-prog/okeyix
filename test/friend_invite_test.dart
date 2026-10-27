import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/screens/friend_invite_screen.dart';
import 'package:okeyix/services/friend_invite_service.dart';
import 'package:okeyix/ui/invite_strings.dart';
import 'package:okeyix/ui/lobby/lobby_bottom_dock.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InviteFake extends FriendInviteService {
  InviteFake({this.used = false, this.rewarded = false, this.fail = false})
    : super(
        client: SupabaseClient(
          'https://fixture.invalid',
          'fixture-anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  bool used, rewarded, fail;
  int loads = 0, redeems = 0;
  String? shared;
  @override
  Future<Map<String, dynamic>> dashboard() async {
    loads++;
    if (fail) throw StateError('fixture error');
    return {
      'code': 'A123456789BC',
      'total_invites': 0,
      'successful_invites': 0,
      'earned_coin': 0,
      'redemption': used
          ? {
              'code': 'B123456789AB',
              'progress': rewarded ? 10 : 6,
              'rewarded': rewarded,
            }
          : null,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> friends({
    Map<String, dynamic>? before,
  }) async => [];
  @override
  Future<String> redeem(String code) async {
    redeems++;
    used = true;
    return 'accepted';
  }

  @override
  Future<void> shareWhatsApp(String message, Rect origin) async {
    shared = message;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'localized invitation includes code, real-hand rule and reward without tracking links',
    () {
      final tr = InviteStrings(const Locale('tr')).shareMessage('ABC123');
      final en = InviteStrings(const Locale('de')).shareMessage('ABC123');
      expect(tr, contains('ABC123'));
      expect(tr, contains('10 el'));
      expect(tr, contains('1.000.000'));
      expect(en, contains('10 hands'));
      expect(en, contains('ABC123'));
      for (final message in [tr, en]) {
        expect(
          message,
          contains(
            'Android: https://play.google.com/store/apps/details?id=com.okeyix.game&hl=tr',
          ),
        );
        expect(
          message,
          contains(
            'iPhone / iPad: https://apps.apple.com/tr/app/okeyix/id6761813938',
          ),
        );
        expect(message, isNot(contains('\\&')));
        expect(message, isNot(contains('ref=')));
      }
    },
  );
  for (final size in [
    const Size(480, 270),
    const Size(568, 320),
    const Size(844, 390),
  ]) {
    testWidgets('invite content and keyboard fit $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.binding.platformDispatcher.localeTestValue = const Locale('tr');
      addTearDown(t.binding.platformDispatcher.clearLocaleTestValue);
      final fake = InviteFake();
      await t.pumpWidget(MaterialApp(home: FriendInviteScreen(service: fake)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ListView), findsNothing);
      expect(
        find.text('WhatsApp ile Davet Gönder').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Kodu Doğrula').hitTestable(), findsOneWidget);
      final input = find.byKey(const Key('invite-code-input'));
      await t.ensureVisible(input);
      await t.tap(input);
      await t.enterText(input, 'B123456789AB');
      t.view.viewInsets = FakeViewPadding(bottom: size.height * .4);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      final verify = find.text('Kodu Doğrula');
      await t.ensureVisible(verify);
      await t.tap(verify);
      await t.pumpAndSettle();
      expect(fake.redeems, 1);
      expect(find.byKey(const Key('invite-code-input')), findsNothing);
      expect(find.text('6 / 10 el tamamlandı'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'used code stays locked and completed reward is real server state',
    (t) async {
      t.binding.platformDispatcher.localeTestValue = const Locale('tr');
      addTearDown(t.binding.platformDispatcher.clearLocaleTestValue);
      await t.pumpWidget(
        MaterialApp(
          home: FriendInviteScreen(
            service: InviteFake(used: true, rewarded: true),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Tamamlandı · 1 Mn coin kazanıldı!'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('load error offers retry instead of fabricated progress', (
    t,
  ) async {
    final fake = InviteFake(fail: true);
    await t.pumpWidget(MaterialApp(home: FriendInviteScreen(service: fake)));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('A123456789BC'), findsNothing);
    fake.fail = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('A123456789BC'), findsOneWidget);
    expect(fake.loads, 2);
  });
  testWidgets('WhatsApp action sends the displayed code and confirmed rules', (
    t,
  ) async {
    t.binding.platformDispatcher.localeTestValue = const Locale('tr');
    addTearDown(t.binding.platformDispatcher.clearLocaleTestValue);
    final fake = InviteFake();
    await t.pumpWidget(MaterialApp(home: FriendInviteScreen(service: fake)));
    await t.pumpAndSettle();
    final share = find.text('WhatsApp ile Davet Gönder');
    await t.ensureVisible(share);
    await t.tap(share);
    await t.pumpAndSettle();
    expect(fake.shared, contains('A123456789BC'));
    expect(fake.shared, contains('1.000.000'));
    expect(fake.shared, contains('10 el'));
    expect(fake.shared, contains(InviteStrings.androidDownloadUrl));
    expect(fake.shared, contains(InviteStrings.iosDownloadUrl));
  });
  testWidgets('only invited friends open separately on a small landscape', (
    t,
  ) async {
    t.view.physicalSize = const Size(480, 270);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.binding.platformDispatcher.localeTestValue = const Locale('tr');
    addTearDown(t.binding.platformDispatcher.clearLocaleTestValue);
    final s = InviteStrings(const Locale('tr'));
    await t.pumpWidget(
      MaterialApp(home: FriendInviteScreen(service: InviteFake())),
    );
    await t.pumpAndSettle();
    expect(find.text(s.rules), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    await t.tap(find.text('Davet ettiğim arkadaşlar'));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('İlk davetini gönder, birlikte kazanın!'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test(
    'WhatsApp bridge uses existing channel with invitation text only',
    () async {
      MethodCall? captured;
      const channel = MethodChannel('test.invite');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return null;
          });
      final service = FriendInviteService(
        client: SupabaseClient(
          'https://fixture.invalid',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
        channel: channel,
      );
      await service.shareWhatsApp(
        'Invitation code ABC',
        const Rect.fromLTWH(0, 0, 48, 48),
      );
      expect(captured!.method, 'shareInviteWhatsApp');
      expect((captured!.arguments as Map)['text'], 'Invitation code ABC');
      expect((captured!.arguments as Map).containsKey('user_id'), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  testWidgets('five lobby actions with send emblem fit a narrow rail', (
    t,
  ) async {
    t.view.physicalSize = const Size(480, 270);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var tapped = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LobbyBottomDock(
            left: const SizedBox(width: 100),
            center: const SizedBox(width: 80, height: 60),
            right: Row(
              children: [
                for (final kind in [
                  LobbyDockEmblemKind.store,
                  LobbyDockEmblemKind.invite,
                  LobbyDockEmblemKind.ranking,
                  LobbyDockEmblemKind.social,
                  LobbyDockEmblemKind.messages,
                ])
                  LobbyDockAction(
                    label: kind.name,
                    emblem: kind,
                    onTap: () => tapped = true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('invite'));
    expect(tapped, isTrue);
  });
}
