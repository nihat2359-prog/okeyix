import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

String pistiError(Object error) {
  final text = error.toString();
  const messages = {
    'PISTI_DISABLED': 'Pişti henüz sunucuda açılmadı.',
    'NOT_ENOUGH_COINS': 'Bu masanın giriş bedeli için yeterli coinin yok.',
    'TABLE_FULL': 'Masa doldu veya oyun başladı. Başka bir masa seç.',
    'INVITE_EXPIRED': 'Davetin süresi doldu. Arkadaşından yeni bir davet iste.',
    'NO_BOT_AVAILABLE': 'Şu anda uygun bot yok. Biraz sonra yeniden dene.',
    'ALREADY_SEATED_OKEY': 'Önce Okey masandan ayrılmalısın.',
    'INVITE_REQUIRED': 'Bu masaya arkadaş davetiyle katılabilirsin.',
    'STALE_VERSION': 'Masa güncellendi. Güncel kartların yükleniyor.',
    'STALE_MATCH': 'Yeni maç başladı. Masa yenileniyor.',
    'TURN_EXPIRED': 'Hamle süren doldu. Sunucu hamleyi tamamlıyor.',
    'VIEW_DENIED': 'Bu masada seyirciye izin verilmiyor.',
    'NOT_A_MEMBER': 'Artık bu masada değilsin. Lobiye dönebilirsin.',
    'RATE_LIMITED': 'Yeni mesaj için bir saniye bekle.',
    'CHAT_DISABLED': 'Bu masada sohbet kapalı.',
    'PLAYER_BANNED': 'Hesabının oyun erişimi kısıtlandı.',
    'INVITES_DISABLED': 'Arkadaşın masa davetlerini kapatmış.',
    'TABLE_NOT_WAITING': 'Oyun başladı. Masa güncelleniyor.',
    'PGRST205': 'Pişti sunucu kurulumu henüz tamamlanmadı.',
    'SPECTATOR_PASS_REQUIRED':
        'Arkadaşlarının masalarını ücretsiz izleyebilirsin. Diğer masalar için Genel Seyirci Geçişi gerekir.',
  };
  for (final entry in messages.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'Bağlantı doğrulanamadı. Yeniden dene; bekleyen işlem korunuyor.';
}

class PistiService {
  PistiService({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> invitablePlayers(String roomId) async =>
      List<Map<String, dynamic>>.from(
        await client.rpc(
              'okeyix_pisti_invitable_players',
              params: {'p_room': roomId},
            )
            as List,
      );
  Future<List<Map<String, dynamic>>> recentMessages(String roomId) => client
      .from('okeyix_pisti_messages')
      .select()
      .eq('table_id', roomId)
      .order('created_at', ascending: false)
      .limit(50);
  RealtimeChannel? watchMessages(
    String roomId,
    void Function(Map<String, dynamic>) receive,
    VoidCallback reconnect,
  ) => client
      .channel('pisti-social:$roomId:${const Uuid().v4()}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'okeyix_pisti_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'table_id',
          value: roomId,
        ),
        callback: (payload) =>
            receive(Map<String, dynamic>.from(payload.newRecord)),
      )
      .subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed) reconnect();
      });
  Future<Map<String, dynamic>> lobby() async {
    final settings = await client
        .from('okeyix_pisti_settings')
        .select()
        .single();
    final rooms = await client
        .from('okeyix_pisti_rooms')
        .select()
        .inFilter('status', ['waiting', 'playing'])
        .contains(
          'seats',
          jsonEncode([
            {'id': client.auth.currentUser!.id},
          ]),
        )
        .order('created_at', ascending: false)
        .limit(1);
    final invites = await client
        .from('okeyix_pisti_invites')
        .select()
        .eq('to_user', client.auth.currentUser!.id)
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .limit(10);
    return {
      'settings': settings,
      'active_room_id': rooms.isEmpty ? null : rooms.first['id'],
      'invites': invites,
    };
  }

  Future<Map<String, dynamic>> command(
    String action,
    Map<String, dynamic> args, {
    String? request,
  }) async {
    final response = await client.functions
        .invoke(
          'pisti',
          body: {
            'action': action,
            ...args,
            if (action != 'snapshot')
              'request_id': request ?? const Uuid().v4(),
          },
        )
        .timeout(const Duration(seconds: 15));
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw StateError(data['error'].toString());
    return data;
  }
}

/// Realtime carries room versions only. Every read goes through the filtered
/// server snapshot. One reconciliation loop prevents out-of-order responses.
class PistiController extends ChangeNotifier {
  PistiController(this.roomId, this.service);
  final String roomId;
  final PistiService service;
  Map<String, dynamic>? snapshot;
  String? error;
  bool membershipEnded = false;
  bool get hasPendingCommand => _request != null;
  bool busy = false, active = false, _disposed = false, _dirty = false;
  Future<void>? _sync;
  Timer? _heartbeat;
  Timer? _botWake;
  num? _botWakeVersion;
  RealtimeChannel? _channel;
  String? _request, _action;
  Map<String, dynamic>? _args;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _endMembership() {
    membershipEnded = true;
    active = false;
    _dirty = false;
    _heartbeat?.cancel();
    _botWake?.cancel();
    _request = null;
    _action = null;
    _args = null;
  }

  void _checkMembershipError(Object e, {bool snapshotRead = false}) {
    final details = e is FunctionException ? e.details ?? e : e;
    final text = details.toString();
    final lostPlayerAccess =
        snapshotRead &&
        (snapshot?['viewer'] as int? ?? -1) >= 0 &&
        (text.contains('VIEW_DENIED') ||
            text.contains('SPECTATOR_PASS_REQUIRED'));
    if (text.contains('NOT_A_MEMBER') ||
        text.contains('TABLE_NOT_FOUND') ||
        lostPlayerAccess) {
      _endMembership();
    }
  }

  void start() {
    _channel = service.client
        .channel('pisti:$roomId:${const Uuid().v4()}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'okeyix_pisti_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (_) {
            if (active) unawaited(refresh());
          },
        )
        .subscribe((status, _) {
          if (active && status == RealtimeSubscribeStatus.subscribed) {
            unawaited(refresh());
          }
        });
    setActive(true);
  }

  void setActive(bool value) {
    if (_disposed || membershipEnded || active == value) return;
    active = value;
    _heartbeat?.cancel();
    _botWake?.cancel();
    _botWakeVersion = null;
    if (value) {
      unawaited(refresh());
      _heartbeat = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(refresh()),
      );
    }
  }

  Future<void> refresh() {
    if (_disposed || !active || membershipEnded) return Future.value();
    _dirty = true;
    return _sync ??= _run().whenComplete(() {
      _sync = null;
      if (_dirty && active && !_disposed) unawaited(refresh());
    });
  }

  Future<void> _run() async {
    while (_dirty && active && !_disposed && !membershipEnded) {
      _dirty = false;
      try {
        if ((snapshot?['viewer'] as int? ?? 0) >= 0) {
          // The authenticated heartbeat also lets the handler advance a due bot;
          // the subsequent snapshot itself remains read-only.
          try {
            await service.command('heartbeat', {'room_id': roomId});
          } catch (_) {}
        }
        final next = await service.command('snapshot', {'room_id': roomId});
        if (_disposed || !active) return;
        if (snapshot == null ||
            (next['room']['version'] as num) >=
                (snapshot!['room']['version'] as num)) {
          if ((snapshot?['viewer'] as int? ?? -1) >= 0 &&
              (next['viewer'] as int) < 0) {
            _endMembership();
          }
          snapshot = next;
          _scheduleBotRefresh(next);
        }
        error = null;
      } catch (e) {
        _checkMembershipError(e, snapshotRead: true);
        error = pistiError(e is FunctionException ? e.details ?? e : e);
      }
      _notify();
    }
  }

  Future<void> send(
    String action, [
    Map<String, dynamic> args = const {},
    String? requestId,
  ]) async {
    if (busy || _disposed || membershipEnded) return;
    // Unknown transport outcome keeps the original request and exact arguments.
    if (_request != null && _action != action) {
      error = 'Önce bekleyen işlemi yeniden dene.';
      _notify();
      return;
    }
    _request ??= requestId ?? const Uuid().v4();
    _action ??= action;
    _args ??= {'room_id': roomId, ...args};
    busy = true;
    error = null;
    _notify();
    String? failure;
    try {
      await service.command(_action!, _args!, request: _request);
      if (_action == 'leave') {
        _endMembership();
      }
      _request = null;
      _action = null;
      _args = null;
    } on FunctionException catch (e) {
      _checkMembershipError(e);
      // A structured rejection is definitive; a failed HTTP connection is not.
      if (e.details is Map &&
          (e.details as Map)['error'] != null &&
          e.status < 500) {
        _request = null;
        _action = null;
        _args = null;
      }
      failure = pistiError(e.details ?? e);
    } catch (e) {
      _checkMembershipError(e);
      failure = pistiError(e);
    } finally {
      await refresh();
      busy = false;
      if (failure != null) error = failure;
      _notify();
    }
  }

  Future<void> retry() => _action == null ? refresh() : send(_action!);

  void _scheduleBotRefresh(Map<String, dynamic> data) {
    final room = data['room'] as Map;
    final game = data['game'] as Map?;
    final version = room['version'] as num;
    if (room['status'] != 'playing' ||
        game == null ||
        room['seats'][game['turn']]['bot'] != true) {
      _botWake?.cancel();
      _botWakeVersion = null;
      return;
    }
    if (_botWakeVersion == version) return;
    final now = DateTime.tryParse(data['now']?.toString() ?? '');
    final deadline = DateTime.tryParse(room['deadline']?.toString() ?? '');
    if (now == null || deadline == null) return;
    _botWake?.cancel();
    _botWakeVersion = version;
    final delay = (deadline.difference(now).inMilliseconds + 120).clamp(
      250,
      5000,
    );
    _botWake = Timer(Duration(milliseconds: delay), () {
      if (active && !_disposed && !membershipEnded) unawaited(refresh());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    active = false;
    _heartbeat?.cancel();
    _botWake?.cancel();
    final channel = _channel;
    if (channel != null) unawaited(service.client.removeChannel(channel));
    super.dispose();
  }
}
