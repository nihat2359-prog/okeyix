import 'dart:ui' as ui;

import 'package:flame/components.dart';

/// Records only immutable, size-dependent local decoration commands.
/// Transforms, children, visibility and effects remain owned by Flame.
/// Do not use for time-, theme- or interaction-dependent drawing.
mixin CachedDecoration on PositionComponent {
  ui.Picture? _decoration;
  double? _width;
  double? _height;
  Object? _key;

  Object? get decorationKey => null;

  void renderDecoration(ui.Canvas canvas);

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    final key = decorationKey;
    if (_decoration == null ||
        _width != size.x ||
        _height != size.y ||
        _key != key) {
      final recorder = ui.PictureRecorder();
      renderDecoration(ui.Canvas(recorder));
      final replacement = recorder.endRecording();
      _decoration?.dispose();
      _decoration = replacement;
      _width = size.x;
      _height = size.y;
      _key = key;
    }
    canvas.drawPicture(_decoration!);
  }

  @override
  void onRemove() {
    _decoration?.dispose();
    _decoration = null;
    super.onRemove();
  }
}
