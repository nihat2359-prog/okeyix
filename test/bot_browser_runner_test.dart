import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/game/bot/bot_observation.dart';
import 'package:okeyix/game/bot/bot_runner.dart';

// No dart:io or desktop-only fixtures: run this file with --platform chrome.
void main() {
  test(
    'platform runner accepts a useful discard with the actual browser budget',
    () async {
      final values = <(String, int)>[
        ('red', 2),
        ('red', 3),
        ('red', 4),
        ('blue', 6),
        ('blue', 7),
        ('blue', 8),
        ('black', 10),
        ('black', 11),
        ('black', 12),
        ('red', 6),
        ('red', 8),
        ('yellow', 2),
        ('black', 5),
        ('yellow', 10),
      ];
      final hand = [
        for (var i = 0; i < values.length; i++)
          BotStone('s$i', values[i].$1, values[i].$2),
      ];
      final decision = await runBotDecision(
        BotObservation(
          handKey: 'browser-fixture',
          hand: hand,
          ownSeat: 0,
          deckRemaining: 30,
          topDiscard: const BotStone('top', 'red', 7),
        ),
      );
      expect(decision.limited, false, reason: '${decision.draw?.toJson()}');
      expect(decision.takeDiscard, true, reason: '${decision.draw?.toJson()}');
      final discard = await runBotDecision(
        BotObservation(
          handKey: 'browser-fixture',
          hand: [...hand, const BotStone('top', 'red', 7)],
          ownSeat: 0,
          deckRemaining: 30,
        ),
      );
      expect(discard.limited, false);
      expect(discard.discardId, isNot('top'));
      expect(discard.score, greaterThan(0));
    },
  );
}
