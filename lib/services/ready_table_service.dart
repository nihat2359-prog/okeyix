import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// The local table payload/owner presence must never prove system ownership.
class ReadyTableService {
  ReadyTableService(this.client);
  final SupabaseClient client;
  List<Map<String, dynamic>> _botPool = [];
  DateTime? _poolLoadedAt;
  String? _poolUserId;
  Future<List<Map<String, dynamic>>>? _poolRead;

  /// Only names/avatars are cached; the caller creates fresh UI rows per load.
  Future<List<Map<String, dynamic>>> botPlayers() {
    final userId = client.auth.currentUser?.id;
    if (_poolUserId != userId) {
      _botPool = [];
      _poolLoadedAt = null;
      _poolUserId = userId;
    }
    if (_poolLoadedAt != null &&
        DateTime.now().difference(_poolLoadedAt!) < const Duration(minutes: 5)) {
      return Future.value(_botPool);
    }
    return _poolRead ??= _readBotPlayers(userId).whenComplete(() => _poolRead = null);
  }

  Future<List<Map<String, dynamic>>> _readBotPlayers(String? userId) async {
    try {
      final rows = await client.from('users').select('id,username,avatar_url')
          .eq('is_bot', true).order('id').limit(200)
          .timeout(const Duration(seconds: 5));
      if (client.auth.currentUser?.id != userId) return [];
      _botPool = rows.map((row) => Map<String, dynamic>.from(row)).toList();
      _poolLoadedAt = DateTime.now();
      return _botPool;
    } catch (error) {
      // A display-scene outage must not hide real tables or block joining.
      debugPrint('LOBBY SHOWCASE LOAD ERROR: $error');
      return client.auth.currentUser?.id == userId ? _botPool : [];
    }
  }

  Future<bool> isManaged(String tableId) async {
    try {
      final result = await client
          .rpc(
            'okeyix_ready_table_ids',
            params: {
              'p_table_ids': [tableId],
            },
          )
          .timeout(const Duration(seconds: 5));
      return result is List && result.contains(tableId);
    } on PostgrestException catch (error) {
      // Backwards compatible before the ready-table migration is installed.
      if (error.code == 'PGRST202' || error.code == '42883') return false;
      rethrow;
    }
  }
}
