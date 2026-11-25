/// Short-lived public names/avatar URLs only. No hands, balances or permissions.
class PlayerMetadataCache {
  static String? _viewer;
  static final _rows = <String, ({DateTime at, Map<String, dynamic> row})>{};
  static void invalidate(String id) => _rows.remove(id);
  static void _session(String? viewer) {
    if (_viewer == viewer) return;
    _viewer = viewer;
    _rows.clear();
  }

  static void put(
    String? viewer,
    Iterable<Map<String, dynamic>> rows, {
    DateTime? now,
  }) {
    _session(viewer);
    if (viewer == null) return;
    for (final row in rows) {
      final id = row['id']?.toString();
      // Preserve the users/email fallback for accounts without a name.
      if (id == null || (row['username']?.toString().trim() ?? '').isEmpty) {
        continue;
      }
      _rows[id] = (
        at: now ?? DateTime.now(),
        row: {
          for (final key in ['id', 'username', 'avatar_url', 'is_bot'])
            if (row.containsKey(key)) key: row[key],
        },
      );
    }
    while (_rows.length > 512) {
      _rows.remove(_rows.keys.first);
    }
  }

  static Map<String, dynamic>? get(String? viewer, String id, {DateTime? now}) {
    _session(viewer);
    final value = _rows[id];
    if (viewer == null ||
        value == null ||
        (now ?? DateTime.now()).difference(value.at) >=
            const Duration(seconds: 60)) {
      return null;
    }
    return Map.of(value.row);
  }
}
