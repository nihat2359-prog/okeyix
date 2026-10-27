import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/format.dart';

void main() {
  test('Turkish units and decimal separator cover every magnitude', () {
    final examples = <num, String>{
      0: '0', 950: '950', 1000: '1 Bin', 2500: '2,5 Bin',
      25500: '25,5 Bin', 125400: '125,4 Bin',
      125437: '125,4 Bin', 125850: '125,9 Bin',
      999499: '999,5 Bin', 999500: '999,5 Bin', 999950: '1 Mn',
      1000000: '1 Mn', 12500000: '12,5 Mn',
      999950000: '1 Mr', 1500000000: '1,5 Mr',
      999950000000: '1 Tn', 1000000000000: '1 Tn',
      -2500: '-2,5 Bin', -1500000000: '-1,5 Mr',
    };
    for (final entry in examples.entries) {
      expect(Format.coin(entry.key), entry.value, reason: '${entry.key}');
    }
  });
  test('player balances use the same single decimal in every unit', () {
    for (final value in [125437, 125850, 125400000, 125400000000, 125400000000000]) {
      expect(Format.balance(value), Format.coin(value));
    }
    expect(Format.balance(125400000), '125,4 Mn');
    expect(Format.balance(125400000000), '125,4 Mr');
    expect(Format.balance(125400000000000), '125,4 Tn');
  });
  test('selectable amounts retain exact values and share Turkish units', () {
    expect(Format.coinExact(1001), '1,001 Bin');
    expect(Format.coinExact(1000001), '1,000001 Mn');
    expect(Format.coinExact(1000000001), '1,000000001 Mr');
    expect(Format.coinExact(1000000000001), '1,000000000001 Tn');
    expect(Format.coinExact(-1250), '-1,25 Bin');
    expect(Format.coinExact(1000000), '1 Mn');
    expect(Format.coinExact(500), '500');
  });
}
