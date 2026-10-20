import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:okeyix/services/feedback_settings_service.dart';
import 'package:okeyix/services/reward_audio.dart';
import 'package:okeyix/ui/reward_dialogs.dart';
import 'package:okeyix/ui/coin_transfer_overlay.dart';

class _Player extends Fake implements AudioPlayer {
  final assets = <String>[];
  int plays = 0, disposed = 0;
  Completer<Duration?>? pending;
  @override
  Future<void> stop() async {}
  @override
  Future<Duration?> setAsset(
    String path, {
    String? package,
    bool preload = true,
    Duration? initialPosition,
    dynamic tag,
  }) async {
    assets.add(path);
    return pending == null ? Duration.zero : pending!.future;
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> play() async {
    plays++;
  }

  @override
  Future<void> dispose() async {
    disposed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('three original WAV cues contain short valid mono PCM audio', () {
    for (final cue in RewardSound.values) {
      final bytes = File(
        'assets/sounds/reward_${cue.name}.wav',
      ).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(40, Endian.little), bytes.length - 44);
      expect(bytes.length, lessThan(45000));
      expect(bytes.skip(44).any((b) => b != 0), isTrue);
    }
  });

  test('sound setting mutes cues and disposal is idempotent', () async {
    final player = _Player();
    final audio = RewardAudio(player: player);
    await FeedbackSettingsService.setSoundEnabled(false);
    await audio.play(RewardSound.opening);
    expect(player.assets, isEmpty);
    await FeedbackSettingsService.setSoundEnabled(true);
    await audio.play(RewardSound.deposit);
    expect(player.assets, ['assets/sounds/reward_deposit.wav']);
    expect(player.plays, 1);
    audio.dispose();
    audio.dispose();
    await audio.play(RewardSound.won);
    expect(player.disposed, 1);
    expect(player.plays, 1);
  });

  test('late audio loading cannot play after disposal', () async {
    final player = _Player()..pending = Completer<Duration?>();
    final audio = RewardAudio(player: player);
    await FeedbackSettingsService.setSoundEnabled(true);
    final playing = audio.play(RewardSound.opening);
    await Future<void>.delayed(Duration.zero);
    audio.dispose();
    player.pending!.complete(Duration.zero);
    await playing;
    expect(player.plays, 0);
  });

  for (final outcome in ['success', 'already', 'error']) {
    testWidgets('reward cues follow server $outcome, never the tap', (
      tester,
    ) async {
      final sounds = <RewardSound>[];
      final response = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailyBonusDialog(
              amount: 2500,
              onClaim: () => response.future,
              onSound: sounds.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sounds, [RewardSound.opening]);
      await tester.tap(find.text('Al'));
      await tester.pump();
      expect(sounds, [RewardSound.opening]);
      if (outcome == 'error') {
        response.completeError(StateError('offline'));
      } else {
        response.complete(outcome == 'success');
      }
      await tester.pumpAndSettle();
      expect(
        sounds,
        outcome == 'success'
            ? [RewardSound.opening, RewardSound.won]
            : [RewardSound.opening],
      );
      await tester.pump();
      expect(sounds.length, outcome == 'success' ? 2 : 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('coin transfer does not intercept input or leave a ticker', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 1100),
    );
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                child: TextButton(
                  onPressed: () => taps++,
                  child: const Text('Katıl'),
                ),
              ),
              Positioned.fill(
                child: CoinTransferOverlay(
                  progress: controller,
                  source: const Offset(320, 100),
                  destination: const Offset(160, 300),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.forward();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Katıl'));
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(controller.value, 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    expect(tester.takeException(), isNull);
  });
}
