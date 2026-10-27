class Format {
  static const int ratingStep = 100;
  static const int ratingMaxValue = 34000; // 34.0
  static const int ratingLevelStep = 1000; // per-level bucket

  static const _coinDivisors = [1, 1000, 1000000, 1000000000, 1000000000000];
  static const _coinUnits = ['', 'Bin', 'Mn', 'Mr', 'Tn'];

  static String balance(num value) => coin(value);

  static String coin(num value) {
    final magnitude = value.abs();
    var unit = 0;
    while (unit < _coinDivisors.length - 1 &&
        magnitude >= _coinDivisors[unit + 1]) {
      unit++;
    }
    if (unit == 0) return value.toString().replaceAll('.', ',');
    var tenths = (magnitude * 10 / _coinDivisors[unit]).round();
    // Carry rounding into the next unit instead of displaying 1000 Bin/Mn/Mr.
    if (tenths >= 10000 && unit < _coinDivisors.length - 1) {
      unit++;
      tenths = (magnitude * 10 / _coinDivisors[unit]).round();
    }
    final text = tenths % 10 == 0 ? '${tenths ~/ 10}'
        : '${tenths ~/ 10},${tenths % 10}';
    return '${value < 0 ? '-' : ''}$text ${_coinUnits[unit]}';
  }

  /// Exact labels for selectable stakes: never merge distinct amounts by rounding.
  static String coinExact(int value) {
    final magnitude = value.abs();
    var unit = 0;
    while (unit < _coinDivisors.length - 1 &&
        magnitude >= _coinDivisors[unit + 1]) {
      unit++;
    }
    if (unit == 0) return '$value';
    final divisor = _coinDivisors[unit];
    final remainder = magnitude % divisor;
    final fraction = remainder == 0 ? '' :
        ',${remainder.toString().padLeft(unit * 3, '0').replaceFirst(RegExp(r'0+$'), '')}';
    return '${value < 0 ? '-' : ''}${magnitude ~/ divisor}$fraction ${_coinUnits[unit]}';
  }
  static String number(int value) {
    return value.toString();
  }

  static String rating(int value) {
    final scaledFloor = (value ~/ ratingStep) / 10.0;
    return scaledFloor.toStringAsFixed(1);
  }

  static double ratingProgress(int value) {
    if (value <= 0) return 0;
    return (value / ratingMaxValue).clamp(0.0, 1.0).toDouble();
  }

  static int ratingLevel(int value) {
    final safe = value < 0 ? 0 : value;
    final level = safe ~/ ratingLevelStep;
    return level < 1 ? 1 : level;
  }

  static double ratingLevelProgress(int value) {
    final safe = value < 0 ? 0 : value;
    final inLevel = safe % ratingLevelStep;
    return (inLevel / ratingLevelStep).clamp(0.0, 1.0).toDouble();
  }

  static int ratingNextTarget(int value) {
    if (value <= 0) return ratingStep;
    final next = ((value ~/ ratingStep) + 1) * ratingStep;
    return next > ratingMaxValue ? ratingMaxValue : next;
  }

}
