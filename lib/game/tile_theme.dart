import 'package:flutter/material.dart';
import 'package:okeyix/engine/models/tile.dart';

enum TileThemeId { porcelain, emerald, midnight, burgundy, gold, pink }

/// Presentation only: logical TileColor values never change.
class TileThemePalette {
  final TileThemeId id;
  final String name;
  final Color shadow, surface;
  final List<Color> inks;
  final bool dark;
  const TileThemePalette(
    this.id,
    this.name,
    this.shadow,
    this.surface,
    this.inks, {
    this.dark = false,
  });

  static const all = [
    TileThemePalette(
      TileThemeId.porcelain,
      'Klasik Porselen',
      Color(0xFFB1A590),
      Color(0xFFF4F0E5),
      [
        Color(0xFFD12B3F),
        Color(0xFF1F5BFF),
        Color(0xFF1A1A1A),
        Color(0xFFAA7B12),
      ],
    ),
    TileThemePalette(
      TileThemeId.emerald,
      'Zümrüt Yeşili',
      Color(0xFF071C08),
      Color(0xFF225124),
      [
        Color(0xFFFFA1B0),
        Color(0xFF80D6FF),
        Color(0xFFF0F7F2),
        Color(0xFFFFE56E),
      ],
      dark: true,
    ),
    TileThemePalette(
      TileThemeId.midnight,
      'Gece Mavisi',
      Color(0xFF080F25),
      Color(0xFF243752),
      [
        Color(0xFFFF9BAD),
        Color(0xFF70CFFF),
        Color(0xFFF0F3FF),
        Color(0xFFFFDF63),
      ],
      dark: true,
    ),
    TileThemePalette(
      TileThemeId.burgundy,
      'Bordo',
      Color(0xFF18060F),
      Color(0xFF581F30),
      [
        Color(0xFFFFA4B6),
        Color(0xFF80D6FF),
        Color(0xFFF6EDF3),
        Color(0xFFFFE16B),
      ],
      dark: true,
    ),
    TileThemePalette(
      TileThemeId.gold,
      'Koyu Sarı',
      Color(0xFF594009),
      Color(0xFFC69A24),
      [
        Color(0xFFCE0038),
        Color(0xFF124BEB),
        Color(0xFF11120E),
        Color(0xFFFFEE49),
      ],
    ),
    TileThemePalette(
      TileThemeId.pink,
      'Pembe',
      Color(0xFF71304F),
      Color(0xFFE78FB5),
      [
        Color(0xFFB90038),
        Color(0xFF063BBE),
        Color(0xFF16121A),
        Color(0xFFFFEE49),
      ],
    ),
  ];

  static TileThemePalette of(TileThemeId id) =>
      all.firstWhere((p) => p.id == id);

  /// Keep vivid game colors on pink/gold surfaces; a thin contrasting edge
  /// makes the glyph and dot legible without recoloring the porcelain body.
  Color? inkOutline(TileColor color, {bool colorBlind = false}) {
    if (id != TileThemeId.gold && id != TileThemeId.pink) return null;
    return ink(color, colorBlind: colorBlind).computeLuminance() > .4
        ? const Color(0xFF201425)
        : const Color(0xFFFFF6E8);
  }

  List<Shadow>? inkShadows(TileColor color, {bool colorBlind = false}) {
    final edge = inkOutline(color, colorBlind: colorBlind);
    if (edge == null) return null;
    return [
      for (final offset in const [
        Offset(-1.5, 0),
        Offset(1.5, 0),
        Offset(0, -1.5),
        Offset(0, 1.5),
        Offset(-1, -1),
        Offset(1, -1),
        Offset(-1, 1),
        Offset(1, 1),
      ])
        Shadow(color: edge, offset: offset),
    ];
  }

  Color ink(TileColor color, {bool colorBlind = false}) {
    if (color == TileColor.yellow && colorBlind) {
      return dark
          ? const Color(0xFF70F1B6)
          : id == TileThemeId.porcelain
          ? const Color(0xFF2E8B57)
          : const Color(0xFF002813);
    }
    return switch (color) {
      TileColor.red => inks[0],
      TileColor.blue => inks[1],
      TileColor.black => inks[2],
      TileColor.yellow => inks[3],
    };
  }

  // Luminance remapping preserves the source texture, bevel and alpha. Only
  // the base sprite is filtered; numbers, gems and the joker back stay separate.
  ColorFilter? get filter => id == TileThemeId.porcelain
      ? null
      : ColorFilter.matrix([
          ..._channel(shadow.r, surface.r),
          ..._channel(shadow.g, surface.g),
          ..._channel(shadow.b, surface.b),
          0,
          0,
          0,
          1,
          0,
        ]);

  static List<double> _channel(double low, double high) => [
    .2126 * (high - low),
    .7152 * (high - low),
    .0722 * (high - low),
    0,
    low * 255,
  ];
}
