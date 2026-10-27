import 'format.dart';

/// Keeps the existing stakes and fills the largest gaps until six are available.
/// Never invents amounts outside the league's configured inclusive bounds.
List<int> buildTableStakes(int minimum, int maximum) {
  if (minimum <= 0 || maximum < minimum) {
    throw ArgumentError('Geçersiz lig giriş bedeli aralığı.');
  }
  final values = <int>{minimum, maximum};
  var amount = minimum;
  for (var i = 0; amount < maximum && i < 9; i++) {
    values.add(amount);
    final next = amount < 100000
        ? amount * 2
        : amount < 1000000
        ? (amount * 2.5).toInt()
        : amount * 2;
    if (next <= amount) break;
    amount = next;
  }
  final target = (maximum - minimum + 1).clamp(1, 6);
  while (values.length < target) {
    final sorted = values.toList()..sort();
    var lower = sorted.first, upper = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] - sorted[i - 1] > upper - lower) {
        lower = sorted[i - 1];
        upper = sorted[i];
      }
    }
    var middle = lower + (upper - lower) ~/ 2;
    // Two significant decimal places produce readable coin denominations.
    var unit = 1;
    while (middle ~/ unit >= 100) {
      unit *= 10;
    }
    final rounded = (middle / unit).round() * unit;
    if (rounded > lower && rounded < upper) middle = rounded;
    values.add(middle);
  }
  return values.toList()..sort();
}

/// Compact labels must not round two different selectable stakes to one label.
String formatTableStake(int amount) => Format.coinExact(amount);

/// The same validated draft used by the UI is sent to the existing insert.
Map<String, dynamic> tableCreationPayload({
  required Map<String, dynamic> league,
  required String userId,
  required int entry,
  required int turnSeconds,
  required bool spectatorsEnabled,
  required bool chatEnabled,
}) {
  final minimum = (league['min_coin'] as num?)?.toInt() ?? 100;
  final maximum = (league['max_coin'] as num?)?.toInt() ?? minimum;
  if (userId.isEmpty ||
      league['id'] == null ||
      !buildTableStakes(minimum, maximum).contains(entry) ||
      (turnSeconds != 15 && turnSeconds != 20)) {
    throw ArgumentError('Geçersiz masa kurma seçimi.');
  }
  return {
    'league_id': league['id'],
    'max_players': 2,
    'entry_coin': entry,
    'min_rounds': league['min_rounds'] ?? 2,
    'status': 'waiting',
    'created_by': userId,
    'turn_seconds': turnSeconds,
    'spectators_enabled': spectatorsEnabled,
    'chat_enabled': chatEnabled,
  };
}
