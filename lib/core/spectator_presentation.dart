import 'dart:convert';

String? spectatorFinishLabel(Map<String, dynamic> result) {
  final okey = result['is_okey_finish'];
  final pairs = result['is_double_finish'];
  if (okey is! bool || pairs is! bool) return null;
  if (okey && pairs) return 'Çiftten, okey atarak bitiş';
  if (okey) return 'Okey atarak bitiş';
  if (pairs) return 'Çiftten bitiş';
  return 'Normal bitiş';
}

Map<String, dynamic>? spectatorSnapshotWinner(Map<String, dynamic> snapshot) {
  dynamic wrapper = snapshot['players'];
  if (wrapper is String) {
    try {
      wrapper = jsonDecode(wrapper);
    } catch (_) {
      return null;
    }
  }
  final rows = wrapper is Map ? wrapper['players'] : wrapper;
  if (rows is! List) return null;
  final winners = rows
      .whereType<Map>()
      .where((p) => p['is_winner'] == true)
      .toList();
  if (winners.length != 1) return null;
  return Map<String, dynamic>.from(winners.single);
}

double spectatorTurnProgress(DateTime? startedAt, int seconds, DateTime now) {
  if (startedAt == null || seconds <= 0) return 0;
  final elapsed = now.difference(startedAt).inMilliseconds;
  return (1 - elapsed / (seconds * 1000)).clamp(0.0, 1.0);
}

List<Map<String, dynamic>> otherSpectators(
  List<Map<String, dynamic>> entries,
  String? viewerId,
) => entries
    .where((entry) => entry['user_id']?.toString() != viewerId)
    .take(3)
    .toList();
