import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../../services/tile_theme_service.dart';
import '../tile_theme.dart';
import '../../engine/models/tile.dart';

/// Only presentation changes; never carries a hidden tile's logical identity.
class ThemedTileBack extends SpriteComponent {
  ThemedTileBack({
    required super.sprite,
    required super.size,
    required super.position,
    super.anchor,
    super.priority,
  });
  void _applyTheme() => paint.colorFilter = TileThemeService.palette.filter;
  @override
  void onMount() {
    super.onMount();
    _applyTheme();
    TileThemeService.selected.addListener(_applyTheme);
  }

  @override
  void onRemove() {
    TileThemeService.selected.removeListener(_applyTheme);
    super.onRemove();
  }
}

class ThemedDeckCount extends TextComponent {
  final TextStyle classicStyle;
  ThemedDeckCount({
    required this.classicStyle,
    required super.text,
    required super.position,
    super.anchor,
    super.priority,
  }) : super(textRenderer: TextPaint(style: classicStyle));
  void _applyTheme() {
    final palette = TileThemeService.palette;
    textRenderer = TextPaint(
      style: classicStyle.copyWith(
        color: palette.id == TileThemeId.porcelain
            ? classicStyle.color
            : palette.ink(TileColor.black),
      ),
    );
  }

  @override
  void onMount() {
    super.onMount();
    _applyTheme();
    TileThemeService.selected.addListener(_applyTheme);
  }

  @override
  void onRemove() {
    TileThemeService.selected.removeListener(_applyTheme);
    super.onRemove();
  }
}
