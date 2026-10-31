/// Shared wire IDs for standard 52-card games. Hidden cards have local negative
/// IDs and carry no information about the server's card identity.
enum PlayingSuit { clubs, diamonds, hearts, spades }

class PlayingCard {
  const PlayingCard(this.suit, this.rank)
    : hiddenId = null,
      assert(rank >= 1 && rank <= 13);
  const PlayingCard.hidden(int index)
    : suit = PlayingSuit.clubs,
      rank = 1,
      hiddenId = index;
  final PlayingSuit suit;
  final int rank;
  final int? hiddenId;
  int get id => hiddenId == null ? suit.index * 13 + rank - 1 : -1 - hiddenId!;
  bool get isRed => suit == PlayingSuit.hearts || suit == PlayingSuit.diamonds;
  String get label => switch (rank) {
    1 => 'A',
    11 => 'J',
    12 => 'Q',
    13 => 'K',
    _ => '$rank',
  };
  String get suitName => switch (suit) {
    PlayingSuit.clubs => 'sinek',
    PlayingSuit.diamonds => 'karo',
    PlayingSuit.hearts => 'kupa',
    PlayingSuit.spades => 'maça',
  };
}
