class Format {
  static const int ratingStep = 100;
  static const int ratingMaxValue = 34000; // 34.0
  static const int ratingLevelStep = 1000; // per-level bucket

  static String coin(num value) {
    if (value >= 1000000000000) {
      final v = value / 1000000000000;
      return "${_formatShort(v)} T";
    }

    if (value >= 1000000000) {
      final v = value / 1000000000;
      return "${_formatShort(v)} B";
    }

    if (value >= 1000000) {
      final v = value / 1000000;
      return "${_formatShort(v)} M";
    }

    if (value >= 1000) {
      final v = value / 1000;

      /// 🔥 CRITICAL FIX
      if (v >= 999.5) {
        return "1 M";
      }

      return "${_formatShort(v)} K";
    }

    return value.toString();
  }

  static String _formatShort(num v) {
    // 🔥 tam sayıysa .0 gösterme
    if (v % 1 == 0) {
      return v.toStringAsFixed(0);
    }

    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 10) return v.toStringAsFixed(1);

    return v.toStringAsFixed(1);
  }

  /// 🔥 İleride lazım olacak
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
