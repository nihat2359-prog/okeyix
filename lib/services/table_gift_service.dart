import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/models/table_gift.dart';

class TableGiftService {
  TableGiftService({SupabaseClient? client})
    : client = client ?? Supabase.instance.client;
  final SupabaseClient client;
  String? get userId => client.auth.currentUser?.id;
  Future<Map<String, dynamic>> snapshot(String tableId) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'okeyix_table_gift_snapshot',
              params: {'p_table_id': tableId},
            )
            as Map,
      );
  Future<List<TableGiftEvent>> events(String tableId, int after) async {
    final rows = await client
        .from('okeyix_table_gift_purchases')
        .select('seq,request_id,table_id,sender_id,recipient_id,gift_id')
        .eq('table_id', tableId)
        .gt('seq', after)
        .order('seq')
        .limit(100);
    return rows.map(TableGiftEvent.fromJson).toList();
  }

  Future<Map<String, dynamic>> buy(
    String tableId,
    String recipient,
    String gift,
    String request,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
          'okeyix_buy_table_gift',
          params: {
            'p_table_id': tableId,
            'p_recipient_id': recipient,
            'p_gift_id': gift,
            'p_request_id': request,
          },
        )
        as Map,
  );
  Future<void> Function() watch(
    String tableId,
    void Function(TableGiftEvent?) changed,
    VoidCallback reconnected,
  ) {
    final channel = client
        .channel('table-gifts:$tableId:${const Uuid().v4()}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'okeyix_table_gift_purchases',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: tableId,
          ),
          callback: (payload) {
            TableGiftEvent? event;
            try {
              event = TableGiftEvent.fromJson(payload.newRecord);
            } catch (_) {
              /* Reconcile from the ordered server feed below. */
            }
            changed(event);
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) reconnected();
        });
    return () async {
      await client.removeChannel(channel);
    };
  }
}

/// Server state is authoritative. Ordered cursor reads close Realtime gaps;
/// reconnect restores latest state without replaying old flights. No polling.
class TableGiftController extends ChangeNotifier {
  TableGiftController({
    required this.tableId,
    required this.service,
    required this.spectator,
  });
  final String tableId;
  final TableGiftService service;
  final bool spectator;
  List<TableGiftItem> catalog = [];
  final Map<String, TableLastGift> latest = {};
  final Set<int> _earlyReceipts = {};
  String? _readyIdentity;
  int? balance;
  bool ready = false, failed = false, buying = false;
  int _cursor = 0;
  int restoration = 0;
  bool _disposed = false, _dirty = false, _restore = true;
  Future<void>? _sync;
  Future<void> Function()? _close;
  String? _request, _recipient, _gift;
  void Function(List<TableGiftEvent>)? onEvents;

  void start() {
    _close = service.watch(tableId, (event) {
      if (event != null && ready && _readyIdentity == service.userId) {
        _receiveVerified(event);
      }
      unawaited(sync());
    }, () => unawaited(restore()));
    unawaited(restore());
  }

  // Only committed RPC receipts or Postgres Changes rows enter here. Never
  // accept client broadcasts. Keep the cursor for ordered gap reconciliation.
  void _receiveVerified(TableGiftEvent event) {
    if (_disposed ||
        event.tableId != tableId ||
        event.seq <= _cursor ||
        !_earlyReceipts.add(event.seq)) {
      return;
    }
    final old = latest[event.recipientId];
    if (old == null || event.seq > old.seq) {
      latest[event.recipientId] = TableLastGift(event.seq, event.giftId);
      if (!spectator) onEvents?.call([event]);
      notifyListeners();
    }
  }

  Future<void> restore() {
    _restore = true;
    return sync();
  }

  Future<void> sync() {
    if (_disposed) return Future.value();
    _dirty = true;
    return _sync ??= _run().whenComplete(() {
      _sync = null;
      if (_dirty && !_disposed) unawaited(sync());
    });
  }

  Future<void> _run() async {
    while (_dirty && !_disposed) {
      _dirty = false;
      final identity = service.userId;
      try {
        if (_restore) {
          _restore = false;
          final data = await service.snapshot(tableId);
          if (_disposed || identity != service.userId) return;
          if (data['table_id'] != tableId) {
            throw const FormatException('Wrong table');
          }
          catalog = (data['catalog'] as List)
              .map(
                (e) =>
                    TableGiftItem.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList();
          latest.clear();
          for (final raw in data['last_gifts'] as List) {
            final row = Map<String, dynamic>.from(raw as Map);
            if (row['table_id'] != tableId ||
                !TableGiftItem.ids.contains(row['gift_id'])) {
              continue;
            }
            latest[row['user_id'] as String] = TableLastGift(
              (row['purchase_seq'] as num).toInt(),
              row['gift_id'] as String,
            );
          }
          _cursor = (data['cursor'] as num).toInt();
          _earlyReceipts.clear();
          _readyIdentity = identity;
          balance = (data['balance'] as num?)?.toInt();
          ready = true;
          failed = false;
          restoration++;
          notifyListeners();
          // Always check after the snapshot: an event may have committed while
          // restoring. Never clear a dirty notification arriving during await.
          _dirty = true;
        } else {
          final batch = await service.events(tableId, _cursor);
          if (_disposed || identity != service.userId) return;
          final accepted = <TableGiftEvent>[];
          for (final e in batch..sort((a, b) => a.seq.compareTo(b.seq))) {
            if (e.tableId != tableId || e.seq <= _cursor) continue;
            _cursor = e.seq;
            final alreadyPresented = _earlyReceipts.remove(e.seq);
            final old = latest[e.recipientId];
            if (old == null || e.seq > old.seq) {
              latest[e.recipientId] = TableLastGift(e.seq, e.giftId);
            }
            if (!alreadyPresented && (old == null || e.seq >= old.seq)) {
              accepted.add(e);
            }
          }
          if (batch.length == 100) _dirty = true;
          if (accepted.isNotEmpty) {
            if (!spectator) onEvents?.call(accepted);
            notifyListeners();
          }
        }
      } catch (_) {
        if (_disposed) return;
        failed = true;
        _dirty = false;
        if (!ready) _restore = true;
        notifyListeners();
        // A later Realtime event, reconnect or explicit retry tries again.
        return;
      }
    }
  }

  Future<void> buy(String recipient, String gift) async {
    if (_disposed || spectator || buying) {
      throw StateError('GIFT_PURCHASE_DISABLED');
    }
    if (_request != null && (_recipient != recipient || _gift != gift)) {
      throw StateError('GIFT_PENDING_REQUEST');
    }
    _request ??= const Uuid().v4();
    _recipient = recipient;
    _gift = gift;
    buying = true;
    notifyListeners();
    final identity = service.userId;
    try {
      final result = await service.buy(tableId, recipient, gift, _request!);
      if (_disposed || identity != service.userId) return;
      final e = TableGiftEvent.fromJson(
        Map<String, dynamic>.from(result['event'] as Map),
      );
      if (e.tableId != tableId ||
          e.senderId != identity ||
          e.recipientId != recipient ||
          e.giftId != gift ||
          e.requestId != _request) {
        throw const FormatException('Wrong purchase receipt');
      }
      balance = (result['balance'] as num?)?.toInt();
      _receiveVerified(e);
      _request = null;
      _recipient = null;
      _gift = null;
      unawaited(sync());
    } on PostgrestException catch (e) {
      // Confirmed SQL rejection has no committed purchase. Transport failures
      // keep the exact same request for retry, even when the panel is reopened.
      if (e.message.contains('GIFT_')) {
        _request = null;
        _recipient = null;
        _gift = null;
      }
      rethrow;
    } finally {
      if (!_disposed) {
        buying = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final close = _close;
    if (close != null) unawaited(close());
    super.dispose();
  }
}
