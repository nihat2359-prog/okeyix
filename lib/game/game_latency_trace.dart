import 'package:flutter/foundation.dart';

/// Opt-in local timings. No tiles, users or network telemetry are recorded.
class GameLatencyTrace {
  static const enabled =
      !kReleaseMode && bool.fromEnvironment('OKEYIX_LATENCY_TRACE');
  final String operation;
  final Stopwatch? _clock = enabled ? (Stopwatch()..start()) : null;

  GameLatencyTrace(this.operation);

  void mark(String stage) {
    final clock = _clock;
    if (clock == null) return;
    debugPrint('GAME_LATENCY $operation $stage ${clock.elapsedMilliseconds}ms');
  }
}
