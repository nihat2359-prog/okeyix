import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final name in ['tile_wood_contact', 'turn_soft_tick']) {
    test('$name is a short, mono, unclipped PCM cue with a quiet tail', () {
      final bytes = File('assets/sounds/$name.wav').readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(data.getUint16(20, Endian.little), 1);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 44100);
      expect(data.getUint16(34, Endian.little), 16);
      final samples = (bytes.length - 44) ~/ 2;
      expect(samples / 44100, lessThan(.2));
      var peak = 0;
      var tail = 0;
      for (var i = 0; i < samples; i++) {
        final value = data.getInt16(44 + i * 2, Endian.little).abs();
        if (value > peak) peak = value;
        if (i > samples - 100 && value > tail) tail = value;
      }
      expect(peak, inInclusiveRange(1000, 30000));
      expect(tail, lessThan(500));
    });
  }
}
