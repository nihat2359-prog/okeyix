import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/models/player_comparison.dart';

class PlayerComparisonService {
  const PlayerComparisonService(this.client);
  final SupabaseClient client;
  Future<PlayerComparison> load(String viewerId, String opponentId) async {
    if (client.auth.currentUser?.id != viewerId || viewerId == opponentId) {
      throw StateError('Comparison requires the signed-in player');
    }
    final json = await client
        .rpc('okeyix_compare_player', params: {'p_opponent_id': opponentId})
        .timeout(const Duration(seconds: 12));
    if (client.auth.currentUser?.id != viewerId) {
      throw StateError('Account changed');
    }
    return PlayerComparison.fromJson(
      Map<String, dynamic>.from(json as Map),
      viewerId: viewerId,
      opponentId: opponentId,
    );
  }
}
