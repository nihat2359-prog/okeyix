import 'dart:io';
import 'package:image/image.dart' as img;
void main() {
  final empty = img.Image(width: 32, height: 32, numChannels: 4);
  File('assets/images/android12_splash_empty.png').writeAsBytesSync(img.encodePng(empty));
  final decoded = img.decodePng(File('assets/images/android12_splash_empty.png').readAsBytesSync())!;
  if (decoded.any((p) => p.a != 0)) throw StateError('Splash must be transparent');
}
