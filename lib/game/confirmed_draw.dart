import 'dart:async';

/// One mutation only. A slow response can be replaced by an authoritative read
/// proving the original fourteen physical tiles plus exactly one new tile.
Future<dynamic> confirmedDraw({
  required Future<dynamic> mutation,
  required Future<List<dynamic>?> Function() readHand,
  required Set<String> previousIds,
  required String tableId,
  required bool Function() isCurrent,
  Duration retryAfter = const Duration(milliseconds: 750),
}) {
  if (previousIds.length != 14) return mutation;
  final result = Completer<dynamic>();
  Timer? retry;

  mutation.then(
    (response) {
      if (!result.isCompleted) result.complete(response);
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
  );

  Future<void> recover() async {
    if (result.isCompleted || !isCurrent()) return;
    try {
      final hand = await readHand().timeout(const Duration(seconds: 2));
      if (result.isCompleted || !isCurrent()) return;
      if (hand != null && hand.length == 15) {
        final ids = <String>{};
        final valid = hand.every(
          (tile) =>
              tile is Map &&
              tile['id'] is String &&
              (tile['id'] as String).isNotEmpty &&
              ids.add(tile['id'] as String),
        );
        if (valid && ids.containsAll(previousIds)) {
          result.complete({'ok': true, 'table_id': tableId, 'hand': hand});
          return;
        }
      }
    } catch (_) {
      // Read failures never retry or reject the in-flight mutation.
    }
    if (!result.isCompleted && isCurrent()) retry = Timer(retryAfter, recover);
  }

  retry = Timer(retryAfter, recover);
  return result.future.whenComplete(() => retry?.cancel());
}
