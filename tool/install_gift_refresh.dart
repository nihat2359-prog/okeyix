import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final root = Directory('output/gift-refresh-v2')..createSync(recursive: true);
  final entries =
      jsonDecode(File('${root.path}/manifest.json').readAsStringSync()) as List;
  final backup = Directory('.dart_tool/gift-refresh-v2/originals')
    ..createSync(recursive: true);
  final sheet = img.Image(width: 800, height: 800, numChannels: 3);
  img.fill(sheet, color: img.ColorRgb8(18, 42, 34));
  final staged = <String, List<int>>{};
  final report = <Map<String, dynamic>>[];
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final id = entry['id'] as String;
    final source = img.decodePng(
      File(entry['path'] as String).readAsBytesSync(),
    );
    if (source == null || !source.hasAlpha)
      throw StateError('Missing alpha: $id');
    final scaled = img
        .copyResize(
          source,
          width: 512,
          height: 512,
          interpolation: img.Interpolation.average,
        )
        .convert(numChannels: 4);
    if (!args.contains('--preview') && scaled.getPixel(0, 0).a != 0)
      throw StateError('Opaque corner: $id');
    final bytes = img.encodePng(scaled, level: 9);
    if (bytes.length > 650000) throw StateError('Oversized: $id');
    staged[id] = bytes;
    final thumb = img.copyResize(
      scaled,
      width: 160,
      height: 160,
      interpolation: img.Interpolation.average,
    );
    final x = (index % 4) * 200, y = (index ~/ 4) * 200;
    img.compositeImage(sheet, thumb, dstX: x + 20, dstY: y + 4);
    img.drawString(
      sheet,
      id,
      font: img.arial14,
      x: x + 5,
      y: y + 174,
      color: img.ColorRgb8(235, 220, 180),
    );
    report.add({
      'id': id,
      'width': 512,
      'height': 512,
      'bytes': bytes.length,
      'alpha': true,
    });
  }
  if (staged.length != 16) throw StateError('Expected all 16 catalog assets');
  for (final entry
      in args.contains('--preview')
          ? <MapEntry<String, List<int>>>[]
          : staged.entries) {
    final target = File('assets/images/hediyeler/${entry.key}.png');
    final original = File('${backup.path}/${entry.key}.png');
    if (!original.existsSync()) target.copySync(original.path);
    target.writeAsBytesSync(entry.value);
  }
  File('${root.path}/preview.png').writeAsBytesSync(img.encodePng(sheet));
  File(
    '${root.path}/verification.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(
    'Installed ${staged.length} RGBA assets: ${report.fold<int>(0, (sum, e) => sum + (e['bytes'] as int))} bytes',
  );
}
