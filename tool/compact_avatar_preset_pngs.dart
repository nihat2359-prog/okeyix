import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final staged = Directory(args.isNotEmpty ? args[0] : '.dart_tool/avatar-refresh/staged');
  final expectedCount = args.length > 1 ? int.parse(args[1]) : 32;
  final files = staged.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList();
  if (files.length != expectedCount) throw StateError('Expected $expectedCount staged PNGs');
  for (final file in files) {
    final decoded = img.decodePng(file.readAsBytesSync());
    if (decoded == null || decoded.width != 256 || decoded.height != 256) {
      throw StateError('Invalid staged preset: ${file.path}');
    }
    // Preserve RGB pixels. Indexed palette quantization introduced black speckles.
    final rgb = decoded.convert(numChannels: 3);
    final bytes = img.encodePng(rgb, level: 9);
    if (bytes.length > 200000) throw StateError('Preset exceeds 200KB');
    final roundTrip = img.decodePng(bytes);
    if (roundTrip == null) throw StateError('PNG round trip failed');
    final expectedPixels = rgb.getBytes(order: img.ChannelOrder.rgb);
    final actualPixels = roundTrip.getBytes(order: img.ChannelOrder.rgb);
    if (expectedPixels.length != actualPixels.length) {
      throw StateError('PNG pixel count changed');
    }
    for (var i = 0; i < expectedPixels.length; i++) {
      if (expectedPixels[i] != actualPixels[i]) {
        throw StateError('PNG changed source colors: ${file.path}');
      }
    }
    file.writeAsBytesSync(bytes);
  }
  stdout.writeln('Saved $expectedCount lossless true-color 256px PNGs.');
}
