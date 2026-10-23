import 'package:supabase_flutter/supabase_flutter.dart';

/// The local table payload/owner presence must never prove system ownership.
class ReadyTableService {
  const ReadyTableService(this.client);
  final SupabaseClient client;

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
