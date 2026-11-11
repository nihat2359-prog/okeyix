import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/dev/pisti/pisti_model.dart';

void main() {
  void conserved(PistiGame game) {
    final cards = [
      ...game.deck,
      ...game.pile,
      ...game.hands.values.expand((h) => h),
      ...game.won.values.expand((h) => h),
    ];
    expect(cards.length, 52);
    expect(cards.map((c) => c.id).toSet().length, 52);
  }

  test(
    '52 cards survive complete local games; scoring and six deals are consistent',
    () {
      for (var seed = 0; seed < 40; seed++) {
        final game = PistiGame(random: Random(seed));
        conserved(game);
        var moves = 0;
        while (!game.finished && moves < 60) {
          final seat = game.turn;
          final card = seat == PistiSeat.opponent
              ? game.chooseOpponentCard()
              : game.hand(seat).first;
          expect(game.play(seat, card.id), isNotNull);
          moves++;
          conserved(game);
          if (game.hands.values.every((h) => h.isEmpty)) {
            if (game.deck.isNotEmpty) {
              expect(game.dealNext(), isTrue);
            } else {
              game.finish();
            }
          }
        }
        expect(game.finished, isTrue);
        expect(moves, 48);
        expect(game.dealNumber, 6);
        expect(game.won.values.expand((h) => h).length, 52);
        final majority = game.won[PistiSeat.player]!.length == 26 ? 0 : 3;
        expect(
          game.score(PistiSeat.player) + game.score(PistiSeat.opponent),
          13 + majority + game.bonuses.values.reduce((a, b) => a + b),
        );
        conserved(game);
      }
    },
  );
  test('scenario cards are explicit and conserve the real deck', () {
    for (final scenario in PistiScenario.values) {
      conserved(PistiGame(scenario: scenario));
    }
    final pisti = PistiGame(scenario: PistiScenario.pisti);
    final seven = pisti.hand(PistiSeat.player).first;
    final result = pisti.play(PistiSeat.player, seven.id)!;
    expect(result.pistiBonus, 10);
    expect(result.taken.length, 2);
    expect(pisti.score(PistiSeat.player), 10);
    expect(pisti.pile, isEmpty);
    conserved(pisti);
    final capture = PistiGame(scenario: PistiScenario.capture);
    final ordinary = capture.play(
      PistiSeat.player,
      capture.hand(PistiSeat.player).first.id,
    )!;
    expect(ordinary.isPisti, isFalse);
    expect(ordinary.taken.length, 4);
    conserved(capture);
  });
  test('jack capture, jack pişti, and empty-table jack are distinct', () {
    PistiMove jackOn(PistiCard? top) {
      final game = PistiGame();
      game.hand(PistiSeat.player)
        ..clear()
        ..add(const PistiCard(PistiSuit.clubs, 11));
      game.pile
        ..clear()
        ..addAll(top == null ? [] : [top]);
      return game.play(PistiSeat.player, game.hand(PistiSeat.player).first.id)!;
    }

    expect(jackOn(const PistiCard(PistiSuit.hearts, 7)).pistiBonus, 0);
    expect(jackOn(const PistiCard(PistiSuit.hearts, 7)).taken.length, 2);
    expect(jackOn(const PistiCard(PistiSuit.hearts, 11)).pistiBonus, 20);
    expect(jackOn(null).taken, isEmpty);
  });
  test(
    'wrong turn, duplicate move and premature deal cannot mutate the game',
    () {
      final game = PistiGame(scenario: PistiScenario.pisti);
      final card = game.hand(PistiSeat.player).first;
      expect(game.play(PistiSeat.opponent, card.id), isNull);
      expect(game.dealNext(), isFalse);
      expect(game.play(PistiSeat.player, -1), isNull);
      expect(game.play(PistiSeat.player, card.id), isNotNull);
      expect(game.play(PistiSeat.player, card.id), isNull);
      expect(game.won[PistiSeat.player]!.length, 2);
      conserved(game);
    },
  );
  test(
    'end fixture finishes in two moves and awards the last table to collector',
    () {
      final game = PistiGame(scenario: PistiScenario.finish);
      game.play(PistiSeat.player, game.hand(PistiSeat.player).first.id);
      game.play(PistiSeat.opponent, game.chooseOpponentCard().id);
      final sweep = game.finish();
      expect(sweep?.seat, PistiSeat.player);
      expect(sweep?.isPisti, isFalse);
      expect(game.finished, isTrue);
      expect(game.finish(), isNull);
      conserved(game);
    },
  );
}
