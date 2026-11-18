import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class QuickPlayBackend {
  Future<Map<String, dynamic>> command(String action);
  Future<void> close();
}

class SupabaseQuickPlayBackend implements QuickPlayBackend {
  final SupabaseClient client;
  String requestId = const Uuid().v4();
  bool _loaded = false, _terminal = false, _restartAllowed = false;
  Future<void>? _initialization;
  SharedPreferences? _prefs;
  String? _pendingKey;
  SupabaseQuickPlayBackend(this.client);
  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final user = client.auth.currentUser;
    _pendingKey = 'quick_play_v2_${user?.id}_${user?.lastSignInAt}';
    requestId = _prefs!.getString(_pendingKey!) ?? requestId;
    _loaded = true;
  }

  @override
  Future<Map<String, dynamic>> command(String action) async {
    await (_initialization ??= _initialize());
    if (action == 'start' && _restartAllowed) {
      requestId = const Uuid().v4();
      _restartAllowed = false;
      _terminal = false;
    }
    await _prefs!.setString(_pendingKey!, requestId);
    final data = Map<String, dynamic>.from(
      await client.rpc(
            'okeyix_quick_play_v2',
            params: {'p_request_id': requestId, 'p_action': action},
          )
          as Map,
    );
    _terminal = const ['ready', 'cancelled', 'error'].contains(data['state']);
    _restartAllowed = data['state'] == 'error';
    if (_terminal && _prefs!.getString(_pendingKey!) == requestId) {
      await _prefs!.remove(_pendingKey!);
    }
    return data;
  }

  @override
  Future<void> close() async {
    if (!_loaded || _terminal) return;
    try {
      await command('cancel').timeout(const Duration(seconds: 5));
    } catch (_) {
      // Retain the request ID for reconciliation. Unrenewed server leases expire.
    }
  }
}

enum QuickPlayPhase { finding, cancelling, ready, cancelled, error }

class QuickPlayController extends ChangeNotifier {
  final QuickPlayBackend backend;
  QuickPlayController(this.backend);
  QuickPlayPhase phase = QuickPlayPhase.finding;
  Map<String, dynamic>? result;
  String? message;
  bool busy = false;
  bool _started = false, _disposed = false, _cancelRequested = false;
  Timer? _poll;
  bool get terminal =>
      phase == QuickPlayPhase.ready || phase == QuickPlayPhase.cancelled;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _run('start');
  }

  Future<void> retry() => _run(
    _cancelRequested
        ? 'cancel'
        : result == null || result?['state'] == 'error'
        ? 'start'
        : 'refresh',
  );
  Future<void> cancel() async {
    if (terminal || _disposed) return;
    if (_cancelRequested && phase == QuickPlayPhase.cancelling) return;
    _cancelRequested = true;
    _poll?.cancel();
    phase = QuickPlayPhase.cancelling;
    _notify();
    if (!busy) {
      await _run('cancel');
    } else {
      // Do not wait for a lost start/refresh response before cancelling its lease.
      try {
        final data = await backend
            .command('cancel')
            .timeout(const Duration(seconds: 15));
        if (_disposed || terminal) return;
        if (data['state'] == 'ready' || data['state'] == 'cancelled') {
          result = data;
          phase = data['state'] == 'ready'
              ? QuickPlayPhase.ready
              : QuickPlayPhase.cancelled;
        }
      } catch (_) {
        // The outstanding operation's finally block retries cancellation.
      }
      _notify();
    }
  }

  Future<void> _run(String action) async {
    if (_disposed || busy || terminal) return;
    busy = true;
    _poll?.cancel();
    _notify();
    try {
      final data = await backend
          .command(action)
          .timeout(const Duration(seconds: 15));
      if (_disposed || terminal) return;
      result = data;
      message = null;
      if (data['state'] == 'error') {
        throw StateError(data['code']?.toString() ?? 'QUICK_PLAY_FAILED');
      }
      if (data['state'] == 'ready') {
        phase = QuickPlayPhase.ready;
      } else if (data['state'] == 'cancelled') {
        phase = QuickPlayPhase.cancelled;
      } else if (data['state'] == 'waiting') {
        phase = _cancelRequested
            ? QuickPlayPhase.cancelling
            : QuickPlayPhase.finding;
        final remaining = (data['remaining_ms'] as num?)?.toInt() ?? 1000;
        if (!_cancelRequested) {
          _poll = Timer(Duration(milliseconds: remaining.clamp(1, 1000)), () {
            unawaited(_run('refresh'));
          });
        }
      } else {
        phase = QuickPlayPhase.error;
        message =
            'Hızlı Oyna sunucu güncellemesi gerekiyor. İşlemi iptal edebilirsin.';
      }
    } catch (error) {
      if (_disposed || terminal) return;
      phase = QuickPlayPhase.error;
      final text = error.toString();
      if (action == 'cancel' && text.contains('PGRST202') && result == null) {
        phase = QuickPlayPhase.cancelled;
        return;
      }
      message = text.contains('HUMAN_ONLY_LEAGUE')
          ? 'Ustalar ve Şampiyonlar liglerinde botla oynanmaz. Gerçek bir oyuncunun masasına katılabilir veya masa açabilirsin.'
          : text.contains('NOT_ENOUGH_COINS')
          ? 'Liginin en düşük giriş bedeli için yeterli coinin yok.'
          : text.contains('NO_BOT_AVAILABLE')
          ? 'Şu anda uygun açık masa veya bot yok. Biraz sonra tekrar dene.'
          : text.contains('ALREADY_SEATED')
          ? 'Zaten bir masadasın. Önce o masadan ayrıl.'
          : text.contains('PGRST202')
          ? 'Hızlı Oyna henüz sunucuda etkinleştirilmedi.'
          : text.contains('LEGACY_REQUEST')
          ? 'Önce eski bekleyen isteği iptal et.'
          : 'İşlem doğrulanamadı. Yeniden deneyebilir veya güvenle iptal edebilirsin.';
    } finally {
      busy = false;
      _notify();
      if (!_disposed && !terminal && _cancelRequested && action != 'cancel') {
        unawaited(_run('cancel'));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(backend.close());
    super.dispose();
  }
}
