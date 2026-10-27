import 'package:shared_preferences/shared_preferences.dart';

class PlayerNameReminder {
  final SharedPreferences prefs;
  PlayerNameReminder(this.prefs);
  bool shouldShow({
    required String userId,
    required String name,
    required int games,
  }) =>
      games > 0 &&
      name.trim().toLowerCase().startsWith('oyuncu_') &&
      prefs.getBool('name_reminder_dismissed_$userId') != true;
  Future<void> dismiss(String userId) =>
      prefs.setBool('name_reminder_dismissed_$userId', true);
}
