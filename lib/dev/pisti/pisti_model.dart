import 'dart:math';

import '../../cards/playing_card.dart';

enum PistiSeat { player, opponent }

enum PistiScenario { normal, capture, pisti, finish }

typedef PistiCard = PlayingCard;
typedef PistiSuit = PlayingSuit;

extension PistiCardScoring on PlayingCard {
  int get points => (rank == 1 || rank == 11)
      ? 1
      : suit == PlayingSuit.clubs && rank == 2
      ? 2
      : suit == PlayingSuit.diamonds && rank == 10
      ? 3
      : 0;
}

class PistiMove {
  const PistiMove({
    required this.card,
    required this.seat,
    required this.taken,
    this.pistiBonus = 0,
  });
  final PistiCard card;
  final PistiSeat seat;
  final List<PistiCard> taken;
  final int pistiBonus;
  bool get isPisti => pistiBonus > 0;
}

/// Offline rules only. No production models, services, wallets or player records.
class PistiGame {
  /// Presentation projection only; no opponent cards or stock are received.
  PistiGame.remote(Map<String, dynamic> data, int viewer)
    : _random = Random(0),
      scenario = PistiScenario.normal {
    final local = viewer < 0 ? 0 : viewer;
    PistiCard card(int id) =>
        PistiCard(PistiSuit.values[id ~/ 13], id % 13 + 1);
    for (final seat in PistiSeat.values) {
      final index = seat == PistiSeat.player ? local : 1 - local;
      hands[seat]!.addAll(
        seat == PistiSeat.player && viewer >= 0
            ? (data['hand'] as List).map((id) => card(id as int))
            : List.generate(
                data['hand_counts'][index] as int,
                (i) => PistiCard.hidden(100 + index * 10 + i),
              ),
      );
      won[seat]!.addAll(
        List.generate(data['won_counts'][index] as int, PistiCard.hidden),
      );
      pistis[seat] = data['pistis'][index] as int;
      _remoteScores[seat] = (data['score'] ?? data['total'])[index] as int;
    }
    deck.addAll(List.generate(data['deck_count'] as int, PistiCard.hidden));
    pile.addAll(List.generate(data['pile_count'] as int, PistiCard.hidden));
    if (pile.isNotEmpty && data['top'] != null) {
      pile[pile.length - 1] = card(data['top'] as int);
    }
    turn = data['turn'] == local ? PistiSeat.player : PistiSeat.opponent;
    dealNumber = data['deal'] as int;
    finished = data['status'] == 'finished';
  }
  PistiGame({Random? random, this.scenario = PistiScenario.normal})
    : _random = random ?? Random() {
    _start();
  }
  final Random _random;
  final PistiScenario scenario;
  final deck = <PistiCard>[];
  final pile = <PistiCard>[];
  final hands = {for (final seat in PistiSeat.values) seat: <PistiCard>[]};
  final won = {for (final seat in PistiSeat.values) seat: <PistiCard>[]};
  final bonuses = {for (final seat in PistiSeat.values) seat: 0};
  final pistis = {for (final seat in PistiSeat.values) seat: 0};
  PistiSeat turn = PistiSeat.player;
  PistiSeat? lastCollector;
  int dealNumber = 0;
  bool finished = false;
  final _remoteScores = <PistiSeat, int>{};

  List<PistiCard> hand(PistiSeat seat) => hands[seat]!;
  int score(PistiSeat seat) =>
      _remoteScores[seat] ??
      (won[seat]!.fold(0, (n, c) => n + c.points) +
          bonuses[seat]! +
          (finished && won[seat]!.length > won[_other(seat)]!.length ? 3 : 0));
  static PistiSeat _other(PistiSeat seat) =>
      seat == PistiSeat.player ? PistiSeat.opponent : PistiSeat.player;

  void _start() {
    deck.addAll(
      [
        for (final suit in PistiSuit.values)
          for (var rank = 1; rank <= 13; rank++) PistiCard(suit, rank),
      ]..shuffle(_random),
    );
    if (scenario == PistiScenario.normal) {
      pile.addAll(List.generate(4, (_) => deck.removeLast()));
      // The initial open card is never a jack. Preserve all 52 cards when swapping.
      if (pile.last.rank == 11) {
        final i = deck.indexWhere((c) => c.rank != 11);
        final replacement = deck[i];
        deck[i] = pile.removeLast();
        pile.add(replacement);
      }
      dealNext();
      return;
    }
    PistiCard take(PistiSuit suit, int rank) {
      final i = deck.indexWhere((c) => c.suit == suit && c.rank == rank);
      return deck.removeAt(i);
    }

    pile.add(take(PistiSuit.hearts, 7));
    hand(PistiSeat.player).addAll([
      take(PistiSuit.spades, 7),
      take(PistiSuit.diamonds, 10),
      take(PistiSuit.clubs, 2),
      take(PistiSuit.hearts, 13),
    ]);
    hand(PistiSeat.opponent).addAll([
      take(PistiSuit.clubs, 5),
      take(PistiSuit.spades, 12),
      take(PistiSuit.diamonds, 4),
      take(PistiSuit.hearts, 9),
    ]);
    dealNumber = 1;
    if (scenario == PistiScenario.capture) {
      pile.insertAll(0, [
        take(PistiSuit.clubs, 3),
        take(PistiSuit.diamonds, 1),
      ]);
    }
    if (scenario == PistiScenario.finish) {
      // Explicit end-of-hand fixture, not a random game. Still conserves 52 cards.
      final playerLast = hand(PistiSeat.player).first;
      final opponentLast = hand(PistiSeat.opponent).first;
      deck.addAll(hand(PistiSeat.player).skip(1));
      deck.addAll(hand(PistiSeat.opponent).skip(1));
      hand(PistiSeat.player)
        ..clear()
        ..add(playerLast);
      hand(PistiSeat.opponent)
        ..clear()
        ..add(opponentLast);
      while (deck.isNotEmpty) {
        won[deck.length.isEven ? PistiSeat.player : PistiSeat.opponent]!.add(
          deck.removeLast(),
        );
      }
      dealNumber = 6;
      lastCollector = PistiSeat.opponent;
    }
  }

  bool dealNext() {
    if (finished || deck.isEmpty || hands.values.any((h) => h.isNotEmpty)) {
      return false;
    }
    for (var i = 0; i < 4; i++) {
      for (final seat in PistiSeat.values) {
        if (deck.isNotEmpty) hand(seat).add(deck.removeLast());
      }
    }
    dealNumber++;
    turn = PistiSeat.player;
    return true;
  }

  PistiMove? play(PistiSeat seat, int cardId) {
    if (finished || seat != turn) return null;
    final index = hand(seat).indexWhere((c) => c.id == cardId);
    if (index < 0) return null;
    final card = hand(seat).removeAt(index);
    final matches = pile.isNotEmpty && card.rank == pile.last.rank;
    final captures = pile.isNotEmpty && (matches || card.rank == 11);
    // Jack on a non-jack single card is an ordinary capture, never a pişti.
    final bonus = captures && pile.length == 1 && matches
        ? (card.rank == 11 ? 20 : 10)
        : 0;
    pile.add(card);
    final taken = captures ? List<PistiCard>.of(pile) : <PistiCard>[];
    if (captures) {
      won[seat]!.addAll(taken);
      pile.clear();
      lastCollector = seat;
      bonuses[seat] = bonuses[seat]! + bonus;
      if (bonus > 0) pistis[seat] = pistis[seat]! + 1;
    }
    turn = _other(seat);
    return PistiMove(card: card, seat: seat, taken: taken, pistiBonus: bonus);
  }

  PistiCard chooseOpponentCard() {
    final cards = hand(PistiSeat.opponent);
    if (cards.isEmpty) throw StateError('Opponent has no card');
    if (pile.isNotEmpty) {
      final matching = cards.where((c) => c.rank == pile.last.rank);
      if (matching.isNotEmpty) return matching.first;
      final jacks = cards.where((c) => c.rank == 11);
      if (jacks.isNotEmpty) return jacks.first;
    }
    final ordinary = cards.where((c) => c.rank != 11).toList();
    return ordinary.isEmpty
        ? cards.first
        : ordinary[_random.nextInt(ordinary.length)];
  }

  /// Last table cards go to the last collector (dealer/opponent if no capture).
  /// The final sweep is never a pişti.
  PistiMove? finish() {
    if (finished || deck.isNotEmpty || hands.values.any((h) => h.isNotEmpty)) {
      return null;
    }
    finished = true;
    if (pile.isEmpty) return null;
    final seat = lastCollector ?? PistiSeat.opponent;
    final taken = List<PistiCard>.of(pile);
    won[seat]!.addAll(taken);
    pile.clear();
    return PistiMove(card: taken.last, seat: seat, taken: taken);
  }
}
