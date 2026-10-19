import 'package:flutter/material.dart';
import 'package:okeyix/game/okey_game.dart';

/// Draws the real Flame tile components above the Flutter avatar overlay.
/// IgnorePointer preserves all existing Flame drag/drop hit testing.
class DraggedTilesOverlay extends StatelessWidget {
  const DraggedTilesOverlay({super.key, required this.game});

  final OkeyGame game;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _DraggedTilesPainter(game),
        ),
      ),
    );
  }
}

class _DraggedTilesPainter extends CustomPainter {
  _DraggedTilesPainter(this.game) : super(repaint: game.dragOverlayRevision);

  final OkeyGame game;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Matches CameraComponent.withFixedResolution(width:1600,height:900).
    final scale = (size.width / 1600.0 < size.height / 900.0)
        ? size.width / 1600.0
        : size.height / 900.0;
    final cameraCenter = game.cameraComponent.viewfinder.position;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale * game.cameraComponent.viewfinder.zoom);
    canvas.translate(-cameraCenter.x, -cameraCenter.y);
    for (final tile in game.dragOverlayTiles.toList()) {
      if (tile.isMounted) tile.paintOnDragOverlay(canvas);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DraggedTilesPainter oldDelegate) =>
      oldDelegate.game != game;
}
