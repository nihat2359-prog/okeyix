import 'package:intl/intl.dart';

class Format {
  static String coin(int value) {
    if (value >= 1000000) {
      final v = value / 1000000;
      return v % 1 == 0 ? "${v.toInt()}M" : "${v.toStringAsFixed(1)}M";
    } else if (value >= 1000) {
      final v = value / 1000;
      return v % 1 == 0 ? "${v.toInt()}K" : "${v.toStringAsFixed(1)}K";
    }
    return value.toString();
  }

  /// 🔥 İleride lazım olacak
  static String number(int value) {
    return value.toString();
  }

  static final _trNumber = NumberFormat("#,###", "tr_TR");
  static String rating(int value) {
    return _trNumber.format(value);
  }
}
