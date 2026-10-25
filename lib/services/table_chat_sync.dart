/// Reconciles live notifications with saved messages without replaying bubbles.
class TableChatSync {
  TableChatSync({required this.loadRecent, required this.onMessage});

  final Future<List<Map<String, dynamic>>> Function() loadRecent;
  final void Function(Map<String, dynamic>) onMessage;
  final Set<String> _seen = {};
  bool _disposed = false;
  Future<void>? _pending;
  DateTime? latestMessageAt;

  void _observeTime(Map<String, dynamic> message) {
    final time = DateTime.tryParse(message['created_at']?.toString() ?? '');
    if (time != null &&
        (latestMessageAt == null || time.isAfter(latestMessageAt!))) {
      latestMessageAt = time;
    }
  }

  void seed(Iterable<Map<String, dynamic>> messages) {
    for (final message in messages) {
      final id = message['id']?.toString();
      if (id != null) _seen.add(id);
      _observeTime(message);
    }
  }

  void receive(Map<String, dynamic> message) {
    if (_disposed) return;
    final id = message['id']?.toString();
    if (id == null || !_seen.add(id)) return;
    onMessage(message);
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _pending ??= _refresh().whenComplete(() => _pending = null);
  }

  Future<void> _refresh() async {
    final rows = await loadRecent();
    for (final row in rows.reversed) {
      receive(row);
      // Only a database read advances recovery. A newer live notification
      // must not skip an older notification that was lost in transit.
      if (!_disposed) _observeTime(row);
    }
  }

  void dispose() => _disposed = true;
}
