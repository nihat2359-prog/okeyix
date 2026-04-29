import 'package:intl/intl.dart';

class Format {
  static String coin(num value) {
    if (value >= 1000000) {
      final v = value / 1000000;
      return "${_formatShort(v)}M";
    }

    if (value >= 1000) {
      final v = value / 1000;

      /// 🔥 CRITICAL FIX
      if (v >= 999.5) {
        return "1M";
      }

      return "${_formatShort(v)}K";
    }

    return value.toString();
  }

  static String _formatShort(num v) {
    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(1);
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
