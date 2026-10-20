import 'package:flutter/widgets.dart';

/// The app currently has no localization catalog. Keep this feature's strings
/// together, using device language with English fallback rather than forcing TR.
class InviteStrings {
  static const androidDownloadUrl =
      'https://play.google.com/store/apps/details?id=com.okeyix.game&hl=tr';
  static const iosDownloadUrl =
      'https://apps.apple.com/tr/app/okeyix/id6761813938';
  InviteStrings(this.locale);
  final Locale locale;
  static InviteStrings of(BuildContext context) =>
      InviteStrings(WidgetsBinding.instance.platformDispatcher.locale);
  String t(String tr, String en) => locale.languageCode == 'tr' ? tr : en;
  String get title => t('ARKADAŞINI DAVET ET', 'INVITE A FRIEND');
  String get reward => t('1.000.000 COIN KAZAN!', 'WIN 1,000,000 COINS!');
  String get description => t(
    'Arkadaşını davet et, birlikte kazanın! Davet ettiğin arkadaşın 10 gerçek oyunculu el tamamladığında hem sen hem arkadaşın 1.000.000 coin kazanırsınız.',
    'Invite a friend and win together! When your friend completes 10 hands with real players, you both receive 1,000,000 coins.',
  );
  String get rules => t(
    'Yeni ve eski oyuncular katılabilir. Her oyuncu yalnızca bir kod kullanabilir; kendi kodunu kullanamaz. Sınırsız arkadaş davet edebilirsin. Botlu, iptal edilen ve yarım kalan eller sayılmaz. Kod kullanılmadan önce tamamlanan eller sayılmaz. Ödül yalnızca şart tamamlandığında verilir.',
    'New and existing players can join. Each player can redeem one code, never their own. Invite unlimited friends. Hands with bots, cancelled or unfinished hands do not count. Hands completed before redemption do not count. Rewards are paid only after qualification.',
  );
  String get steps => t(
    '1. Kodunu arkadaşına gönder.\n2. Arkadaşın kodunu Okeyix’te doğrulasın.\n3. Gerçek oyuncularla 10 el tamamlasın.\n4. İkiniz de 1.000.000 coin kazanın!',
    '1. Send your code to a friend.\n2. Your friend redeems it in Okeyix.\n3. They complete 10 hands with real players.\n4. You both receive 1,000,000 coins!',
  );
  String shareMessage(String code) =>
      '${t('Okeyix’te birlikte oynayalım! Davet kodum: $code. Kodu oyunda doğrula; gerçek oyuncularla 10 el tamamladığında ikimiz de 1.000.000 coin kazanalım!', 'Join me in Okeyix! My invite code: $code. Redeem it in the game and complete 10 hands with real players so we each earn 1,000,000 coins!')}\n\nAndroid: $androidDownloadUrl\niPhone / iPad: $iosDownloadUrl';
  String status(String value) => switch (value) {
    'accepted' => t(
      'Kod doğrulandı! 10 el yolculuğun başladı.',
      'Code accepted! Your 10-hand challenge has started.',
    ),
    'already_used' => t(
      'Zaten bir davet kodu kullandın.',
      'You have already redeemed an invite code.',
    ),
    'own_code' => t(
      'Kendi davet kodunu kullanamazsın.',
      'You cannot redeem your own code.',
    ),
    'invalid_code' => t(
      'Bu davet kodu bulunamadı.',
      'This invite code was not found.',
    ),
    'slow_down' => t(
      'Tekrar denemeden önce birkaç saniye bekle.',
      'Please wait a few seconds before trying again.',
    ),
    _ => t(
      'İşlem tamamlanamadı. Tekrar dene.',
      'Could not complete the request. Please retry.',
    ),
  };
}
