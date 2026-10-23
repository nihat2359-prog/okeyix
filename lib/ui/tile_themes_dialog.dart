import 'package:flutter/material.dart';
import '../engine/models/tile.dart';
import '../game/tile_theme.dart';
import '../services/tile_theme_service.dart';
import '../services/user_state.dart';
import 'lobby/lobby_metal_surface.dart';

Future<TileThemeId?> showTileThemes(
  BuildContext context, {
  bool closeOnSelect = false,
}) => showDialog<TileThemeId>(
  context: context,
  barrierColor: const Color(0x99000000),
  builder: (_) => TileThemesDialog(closeOnSelect: closeOnSelect),
);

class TileThemesDialog extends StatefulWidget {
  final bool closeOnSelect;
  const TileThemesDialog({super.key, this.closeOnSelect = false});
  @override
  State<TileThemesDialog> createState() => _TileThemesDialogState();
}

class _TileThemesDialogState extends State<TileThemesDialog> {
  String? _error;
  bool _selecting = false;

  Future<void> _select(TileThemeId id) async {
    if (widget.closeOnSelect && _selecting) return;
    _selecting = true;
    setState(() => _error = null);
    try {
      await TileThemeService.select(id);
      if (mounted &&
          widget.closeOnSelect &&
          ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(id);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Tema kaydedilemedi. Tekrar dokun.');
    } finally {
      _selecting = false;
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 850, maxHeight: 440),
      child: LobbyMetalSurface(
        radius: 20,
        flatBorder: true,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const Icon(
                      Icons.style_outlined,
                      color: Color(0xFFE5C585),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'TAŞ TEMALARI',
                        maxLines: 1,
                        style: TextStyle(
                          color: Color(0xFFE5C585),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final columns = bounds.maxWidth >= 300 ? 3 : 2;
                    final rows = (6 / columns).ceil();
                    final height = ((bounds.maxHeight - (rows - 1) * 8) / rows)
                        .clamp(65.0, 200.0);
                    return ValueListenableBuilder<TileThemeId>(
                      valueListenable: TileThemeService.selected,
                      builder: (context, selected, _) => GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: height,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: TileThemePalette.all.length,
                        itemBuilder: (context, index) {
                          final palette = TileThemePalette.all[index];
                          final active = palette.id == selected;
                          return Semantics(
                            selected: active,
                            button: true,
                            label: palette.name,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                key: ValueKey('tile-theme-${palette.id.name}'),
                                onTap: () => _select(palette.id),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: active
                                        ? const Color(0x664C422C)
                                        : const Color(0x66101920),
                                    border: Border.all(
                                      width: active ? 1.5 : .7,
                                      color: active
                                          ? const Color(0xFFE5C585)
                                          : const Color(0x55646C75),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: RepaintBoundary(
                                          child: TileThemePreview(
                                            palette: palette,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      SizedBox(
                                        height: 18,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            if (active) ...[
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                size: 12,
                                                color: Color(0xFFE5C585),
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                            Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  palette.name,
                                                  style: const TextStyle(
                                                    color: Color(0xFFF2E6CE),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 17,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _error ??
                        'Seçimin yalnızca senin ekranında uygulanır ve otomatik kaydedilir.',
                    style: TextStyle(
                      fontSize: 10,
                      color: _error != null
                          ? const Color(0xFFFF91A4)
                          : Colors.white60,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Uses the very same PNG, luminance filter, palette, and 90:118 tile geometry.
class TileThemePreview extends StatelessWidget {
  final TileThemePalette palette;
  const TileThemePreview({super.key, required this.palette});

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.contain,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final color in TileColor.values) _tile(color)],
    ),
  );

  Widget _tile(TileColor color) {
    final ink = palette.ink(color, colorBlind: UserState.colorBlindMode);
    Widget image = Image.asset(
      'assets/images/tile_base.png',
      width: 90,
      height: 118,
      fit: BoxFit.fill,
    );
    final filter = palette.filter;
    if (filter != null) {
      image = ColorFiltered(colorFilter: filter, child: image);
    }
    return SizedBox(
      width: 94,
      height: 118,
      child: Stack(
        children: [
          image,
          Positioned(
            left: 0,
            top: 13,
            width: 90,
            height: 56,
            child: Center(
              child: Text(
                '8',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w700,
                  fontSize: 56,
                  height: 1,
                  color: ink,
                  shadows: palette.inkShadows(
                    color,
                    colorBlind: UserState.colorBlindMode,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 34.5,
            top: 73.3,
            child: Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ink,
                border:
                    palette.inkOutline(
                          color,
                          colorBlind: UserState.colorBlindMode,
                        ) ==
                        null
                    ? null
                    : Border.all(
                        color: palette.inkOutline(
                          color,
                          colorBlind: UserState.colorBlindMode,
                        )!,
                        width: 1.5,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
