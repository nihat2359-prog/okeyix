import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/services/feedback_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await FeedbackSettingsService.setSoundEnabled(true);
    await FeedbackSettingsService.setVibrationEnabled(true);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('sound disabled still sends a medium impact to the platform', () async {
    await FeedbackSettingsService.setSoundEnabled(false);
    await FeedbackSettingsService.triggerHaptic();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'HapticFeedback.vibrate');
    expect(calls.single.arguments, 'HapticFeedbackType.mediumImpact');
  });

  test('vibration disabled suppresses platform feedback regardless of sound', () async {
    await FeedbackSettingsService.setVibrationEnabled(false);
    for (final sound in [true, false]) {
      await FeedbackSettingsService.setSoundEnabled(sound);
      await FeedbackSettingsService.triggerHaptic();
    }
    expect(calls, isEmpty);
  });
}
