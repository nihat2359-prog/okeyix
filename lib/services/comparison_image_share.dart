import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

Future<Uint8List> captureComparisonCard(GlobalKey key) async {
  final boundary = key.currentContext?.findRenderObject();
  if (boundary is! RenderRepaintBoundary) {
    throw StateError('Share card is not ready');
  }
  // The dedicated card is always 360x640 logical pixels, independent of phone.
  final image = await boundary.toImage(pixelRatio: 3);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG generation failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

class ComparisonImageShare {
  ComparisonImageShare({
    Future<Directory> Function()? temporaryDirectory,
    MethodChannel channel = const MethodChannel(
      'com.okeyix.game/comparison_share',
    ),
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _channel = channel;
  final Future<Directory> Function() _temporaryDirectory;
  final MethodChannel _channel;

  Future<void> share(Uint8List png, Rect origin) async {
    if (png.length < 8 ||
        png[0] != 137 ||
        png[1] != 80 ||
        png[2] != 78 ||
        png[3] != 71) {
      throw const FormatException('PNG required');
    }
    final root = await _temporaryDirectory();
    final directory = await Directory(
      '${root.path}/okeyix_comparisons',
    ).create(recursive: true);
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    // Only old generated cards in this dedicated cache folder. No timer/polling.
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File &&
          entry.path.endsWith('.png') &&
          (await entry.lastModified()).isBefore(cutoff)) {
        try {
          await entry.delete();
        } on FileSystemException {
          /* OS may still own a share. */
        }
      }
    }
    final file = File(
      '${directory.path}/okeyix_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png, flush: true);
    // Keep the file until a later cleanup: Android recipients may read it after
    // the chooser opens. Filename contains neither player IDs nor names.
    await _channel.invokeMethod<void>('shareComparison', {
      'path': file.path,
      'x': origin.left,
      'y': origin.top,
      'width': origin.width,
      'height': origin.height,
    });
  }
}
