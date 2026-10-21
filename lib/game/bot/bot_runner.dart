import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bot_engine.dart';
import 'bot_observation.dart';

BotEngine _platformEngine() =>
    BotEngine(maxNodes: 300000, timeBudget: const Duration(milliseconds: 180));
Future<BotDecision> _calculate(BotObservation observation) =>
    _platformEngine().decideCooperatively(observation);
Future<BotDecision> _calculateDiscard(BotObservation observation) async =>
    _platformEngine().decide(observation, discardOnly: true);

/// Native platforms run in a worker isolate. Web yields between draw types.
/// Both platforms use the same strategic node budget; a browser frame budget
/// must not silently become a different (first-tile fallback) playing policy.
Future<BotDecision> runBotDecision(
  BotObservation observation, {
  Duration? timeout,
  Future<BotDecision> Function(BotObservation)? worker,
  bool discardOnly = false,
}) async {
  // Slower debug JavaScript gets time for the same complete comparison.
  // The engine still yields to the browser and has a finite search deadline.
  final deadline = timeout ?? Duration(milliseconds: kIsWeb ? 2100 : 750);
  try {
    return await (worker?.call(observation) ??
            (kIsWeb
                ? _platformEngine().decideCooperatively(
                    observation,
                    discardOnly: discardOnly,
                    // Reserve time for the bounded fallback if the exact
                    // expectation still cannot finish on slow debug Chrome.
                    totalBudget: const Duration(milliseconds: 1400),
                  )
                : compute(
                    discardOnly ? _calculateDiscard : _calculate,
                    observation,
                  )))
        .timeout(deadline);
  } catch (e) {
    final fallback = observation.hand.firstWhere(
      (s) => !s.wild,
      orElse: () => observation.hand.first,
    );
    return BotDecision(
      discardId: fallback.id,
      limited: true,
      draw: observation.hand.length == 14
          ? BotDrawTrace(
              e is TimeoutException ? 'worker_timeout' : 'worker_error',
            )
          : null,
      elapsedMicros: e is TimeoutException ? deadline.inMicroseconds : 0,
    );
  }
}

/// A transport timeout is ambiguous: a finish may already have committed.
/// Always re-read state before the adapter submits any fallback discard.
bool botFinishSucceeded(Object? response) =>
    response is Map && response['ok'] == true;

Future<bool> botFinishOrRecover({
  required Future<Object?> Function() finish,
  required Future<void> Function() revalidateAndDiscard,
}) async {
  try {
    if (botFinishSucceeded(await finish())) return true;
  } catch (_) {
    // Both exceptions and ok:false require fresh state, not a blind retry.
  }
  await revalidateAndDiscard();
  return false;
}

bool botCanCommit({
  required String expectedTurn,
  required String currentTurn,
  required List<BotStone> expectedHand,
  required List<BotStone> currentHand,
  required String discardId,
}) {
  if (expectedTurn != currentTurn || currentHand.length != 15) return false;
  String signature(List<BotStone> hand) =>
      (hand
              .map((s) => '${s.id}:${s.color}:${s.number}:${s.wild}:${s.fake}')
              .toList()
            ..sort())
          .join('|');
  return signature(expectedHand) == signature(currentHand) &&
      currentHand.any((s) => s.id == discardId);
}
