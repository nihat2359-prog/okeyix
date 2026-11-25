import 'dart:convert';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device/install-scoped signals; never cleared on logout.
class QualityConversionService {
  QualityConversionService({Future<SharedPreferences> Function()? preferences,
    Future<void> Function(String name)? logEvent})
      : _preferences = preferences ?? SharedPreferences.getInstance,
        _logEvent = logEvent ?? ((name) => FirebaseAnalytics.instance.logEvent(name: name));

  static final instance = QualityConversionService();
  static const storageKey = 'quality_conversions_v1';
  final Future<SharedPreferences> Function() _preferences;
  final Future<void> Function(String name) _logEvent;
  Future<void> _pending = Future.value();

  /// Serializes realtime/polling/local-finish races. Per-table round receipts
  /// prevent recounting after route recreation or application restart.
  Future<void> recordCompletedRound({required String tableId, required int round}) {
    if (tableId.isEmpty || round < 1) return Future.value();
    return _pending = _pending.then((_) async {
      final prefs = await _preferences();
      final raw = prefs.getString(storageKey);
      final state = raw == null
          ? <String, dynamic>{'completed_rounds': 0, 'tables': <String, dynamic>{}}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final tables = Map<String, dynamic>.from(state['tables'] as Map);
      var total = (state['completed_rounds'] as num).toInt();
      if (round > ((tables[tableId] as num?)?.toInt() ?? 0)) {
        // Observing round 20 is one completion, never twenty retroactive ones.
        tables[tableId] = round;
        state['tables'] = tables;
        state['completed_rounds'] = ++total;
        if (!await prefs.setString(storageKey, jsonEncode(state))) return;
      }
      for (final milestone in {'first_match_completed': 1, 'engaged_player': 3}.entries) {
        if (total < milestone.value || state[milestone.key] == true) continue;
        try {
          await _logEvent(milestone.key);
          state[milestone.key] = true;
          if (!await prefs.setString(storageKey, jsonEncode(state))) return;
        } catch (error) {
          // Failed SDK submissions retry on the next confirmed receipt.
          debugPrint('QUALITY CONVERSION EVENT ERROR (${milestone.key}): $error');
        }
      }
    }).catchError((Object error) {
      // Storage/analytics failures must never interrupt a game.
      debugPrint('QUALITY CONVERSION STORAGE ERROR: $error');
    });
  }
}
