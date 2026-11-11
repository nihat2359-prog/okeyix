import 'package:supabase_flutter/supabase_flutter.dart';

/// Serializes membership registration before participant-only reads.
class SpectatorAccess {
  final Future<void> Function() register;
  Future<void>? _registration;

  SpectatorAccess({required this.register});

  Future<void> ensureJoined() {
    return _registration ??= _register();
  }

  Future<void> _register() async {
    try {
      await register();
    } catch (_) {
      _registration = null;
      rethrow;
    }
  }

  Future<T> read<T>(Future<T> Function() load) async {
    await ensureJoined();
    try {
      return await load();
    } on PostgrestException catch (error) {
      if (error.code != '42501' ||
          error.message != 'TABLE_VIEW_ACCESS_REQUIRED') {
        rethrow;
      }
      // A previous screen's leave or server cleanup can remove membership.
      // Re-register once, then let any genuine denial reach the caller.
      _registration = null;
      await ensureJoined();
      return await load();
    }
  }
}
