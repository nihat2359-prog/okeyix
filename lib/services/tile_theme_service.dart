import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../game/tile_theme.dart';

class TileThemeSelection extends ValueNotifier<TileThemeId> {
  TileThemeSelection() : super(TileThemeId.porcelain);
  void refreshPresentation() => notifyListeners();
}

class TileThemeService {
  static const preferenceKey = 'settings.tile_theme';
  static final selected = TileThemeSelection();
  static TileThemePalette get palette => TileThemePalette.of(selected.value);
  static Future<void>? _writes;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = switch (prefs.getString(preferenceKey)) {
        'champagne' => 'emerald',
        'anthracite' || 'turquoise' => 'gold',
        'lavender' || 'copper' => 'pink',
        final value => value,
      };
      selected.value = TileThemeId.values.firstWhere(
        (id) => id.name == stored,
        orElse: () => TileThemeId.porcelain,
      );
    } catch (_) {
      // An unreadable cosmetic preference must not block application startup.
      selected.value = TileThemeId.porcelain;
    }
  }

  static Future<void> select(TileThemeId id) {
    selected.value = id;
    final write = (_writes ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(preferenceKey, id.name)) {
        throw StateError('Tile theme could not be saved');
      }
    });
    final settled = write.catchError((Object _) {});
    _writes = settled;
    settled.then((_) {
      if (identical(_writes, settled)) _writes = null;
    });
    return write;
  }
}
