import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

abstract class QuickPlayBackend {
  Future<Map<String, dynamic>> command(String action);
  Future<void> close();
}

class SupabaseQuickPlayBackend implements QuickPlayBackend {
  final SupabaseClient client;
  final String requestId = const Uuid().v4();
  SupabaseQuickPlayBackend(this.client);
  @override
  Future<Map<String, dynamic>> command(String action) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'okeyix_quick_play',
              params: {'p_request_id': requestId, 'p_action': action},
            )
            as Map,
      );
  @override
  Future<void> close() async {}
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

  Future<void> retry() => _run(result == null ? 'start' : 'refresh');
  Future<void> cancel() async {
    if (terminal || _disposed) return;
    _cancelRequested = true;
    phase = QuickPlayPhase.cancelling;
    _notify();
    if (!busy) await _run('cancel');
  }

  Future<void> _run(String action) async {
    if (_disposed || busy || terminal) return;
    busy = true;
    _notify();
    try {
      final data = await backend
          .command(action)
          .timeout(const Duration(seconds: 15));
      if (_disposed) return;
      result = data;
      message = null;
      if (data['state'] == 'ready') {
        phase = QuickPlayPhase.ready;
      } else if (data['state'] == 'cancelled') {
        phase = QuickPlayPhase.cancelled;
      } else {
        phase = QuickPlayPhase.error;
        message =
            'Hızlı Oyna sunucu güncellemesi gerekiyor. İşlemi iptal edebilirsin.';
      }
    } catch (error) {
      if (_disposed) return;
      phase = QuickPlayPhase.error;
      final text = error.toString();
      if (action == 'cancel' && text.contains('PGRST202') && result == null) {
        phase = QuickPlayPhase.cancelled;
        return;
      }
      message = text.contains('NOT_ENOUGH_COINS')
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
    unawaited(backend.close());
    super.dispose();
  }
}
