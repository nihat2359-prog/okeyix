import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'feedback_settings_service.dart';

enum RewardSound { opening, won, deposit }

/// Owned by the presenting widget; cues replace each other instead of stacking.
class RewardAudio {
  final AudioPlayer _player;
  RewardAudio({AudioPlayer? player}) : _player = player ?? AudioPlayer();
  bool _disposed = false;
  int _generation = 0;

  Future<void> play(RewardSound sound) async {
    final generation = ++_generation;
    try {
      await FeedbackSettingsService.load();
      if (_disposed ||
          generation != _generation ||
          !FeedbackSettingsService.soundEnabled) {
        return;
      }
      await _player.stop();
      if (_disposed || generation != _generation) return;
      await _player.setAsset('assets/sounds/reward_${sound.name}.wav');
      if (_disposed ||
          generation != _generation ||
          !FeedbackSettingsService.soundEnabled) {
        return;
      }
      await _player.setVolume(.55);
      if (_disposed ||
          generation != _generation ||
          !FeedbackSettingsService.soundEnabled) {
        return;
      }
      await _player.play();
    } catch (_) {
      // Optional feedback must never interrupt a reward or authentication flow.
    }
  }

  void stop() {
    _generation++;
    if (!_disposed) unawaited(_player.stop().catchError((_) {}));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    unawaited(_player.dispose().catchError((_) {}));
  }
}
