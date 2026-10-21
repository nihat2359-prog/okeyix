/// The bot's complete information boundary. No game, network client, opponent
/// hand, shuffled deck, or server RNG can be passed to the decision engine.
class BotStone {
  final String id;
  final String color;
  final int number;
  final bool wild;
  final bool fake;
  const BotStone(
    this.id,
    this.color,
    this.number, {
    this.wild = false,
    this.fake = false,
  });

  static const colors = ['red', 'blue', 'black', 'yellow'];
  String get kind => fake
      ? 'fake'
      : wild
      ? 'wild'
      : '$color:$number';

  factory BotStone.fromJson(Map<String, dynamic> json, {BotStone? indicator}) {
    final fake =
        json['isFakeJoker'] == true ||
        json['is_fake_joker'] == true ||
        json['fake_joker'] == true;
    var color = '${json['color'] ?? ''}';
    if (int.tryParse(color) case final int index when index >= 0 && index < 4) {
      color = colors[index];
    }
    var number = int.tryParse('${json['value'] ?? json['number']}') ?? 0;
    if (fake &&
        indicator != null &&
        indicator.number >= 1 &&
        indicator.number <= 13) {
      color = indicator.color;
      number = indicator.number % 13 + 1;
    }
    final wild =
        !fake &&
        (json['isJoker'] == true ||
            json['is_joker'] == true ||
            json['joker'] == true ||
            (indicator != null &&
                color == indicator.color &&
                number == indicator.number % 13 + 1));
    return BotStone(
      '${json['id'] ?? ''}',
      color,
      number,
      wild: wild,
      fake: fake,
    );
  }

  Map<String, dynamic> toPayload() => {
    'id': id,
    'value': number,
    'number': number,
    'color': color,
    'isJoker': wild,
    'is_joker': wild,
    'joker': wild,
    'isFakeJoker': fake,
    'is_fake_joker': fake,
    'fake_joker': fake,
  };
}

class BotPublicMove {
  final String eventId;
  final int seat;
  final BotStone stone;
  final int? takenBySeat;
  const BotPublicMove(this.eventId, this.seat, this.stone, {this.takenBySeat});
}

class BotObservation {
  final String handKey;
  final List<BotStone> hand;
  final List<BotPublicMove> history;
  final BotStone? indicator;
  final BotStone? topDiscard;
  final int ownSeat;
  final int deckRemaining;
  final bool pairsDeclared;
  // Declaration requires a server-authorized adapter. The pure engine only
  // proposes it; it never changes game state itself.
  final bool canDeclarePairs;
  final int seed;
  BotObservation({
    required this.handKey,
    required List<BotStone> hand,
    List<BotPublicMove> history = const [],
    this.indicator,
    this.topDiscard,
    required this.ownSeat,
    required this.deckRemaining,
    this.pairsDeclared = false,
    this.canDeclarePairs = false,
    this.seed = 0,
  }) : hand = List.unmodifiable(hand),
       history = List.unmodifiable(history) {
    if (hand.length != 14 && hand.length != 15) {
      throw ArgumentError('Bot requires 14 or 15 own stones');
    }
    if (hand.any(
          (s) =>
              s.id.isEmpty ||
              !BotStone.colors.contains(s.color) ||
              s.number < 1 ||
              s.number > 13,
        ) ||
        hand.map((s) => s.id).toSet().length != hand.length) {
      throw ArgumentError('Invalid/duplicate physical stone in own hand');
    }
  }

  BotObservation withHand(List<BotStone> stones, {BotStone? top}) =>
      BotObservation(
        handKey: handKey,
        hand: stones,
        history: history,
        indicator: indicator,
        topDiscard: top ?? topDiscard,
        ownSeat: ownSeat,
        deckRemaining: deckRemaining,
        pairsDeclared: pairsDeclared,
        canDeclarePairs: canDeclarePairs,
        seed: seed,
      );

  /// Physical IDs deduplicate a stone that was discarded, taken, discarded
  /// again, or is now in our hand. Retained taken stones are public knowledge,
  /// not available copies in the unknown pool.
  Map<String, int> get knownCopies {
    final physical = <String, BotStone>{};
    for (final m in history) {
      if (m.stone.id.isNotEmpty) physical[m.stone.id] = m.stone;
    }
    if (indicator case final BotStone s when s.id.isNotEmpty) {
      physical[s.id] = s;
    }
    if (topDiscard case final BotStone s when s.id.isNotEmpty) {
      physical[s.id] = s;
    }
    for (final s in hand) {
      physical[s.id] = s;
    }
    final counts = <String, int>{};
    for (final s in physical.values) {
      counts.update(s.kind, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

/// Database history is projected using an explicit public-column allowlist.
/// Callers must supply only the current hand's rows, in chronological order.
List<BotPublicMove> botPublicHistory(
  List<Map<String, dynamic>> rows,
  Map<String, int> seats, {
  BotStone? indicator,
}) {
  final unique = <String, BotPublicMove>{};
  for (final row in rows) {
    final raw = row['tile'];
    final id = '${row['id'] ?? ''}';
    if (raw is! Map || id.isEmpty || row['seat_index'] is! num) continue;
    final stone = BotStone.fromJson(
      Map<String, dynamic>.from(raw),
      indicator: indicator,
    );
    if (stone.id.isEmpty) continue;
    unique[id] = BotPublicMove(
      id,
      (row['seat_index'] as num).toInt(),
      stone,
      takenBySeat: row['drawn_at'] != null
          ? seats['${row['drawn_by_user_id']}']
          : null,
    );
  }
  return List.unmodifiable(unique.values);
}
