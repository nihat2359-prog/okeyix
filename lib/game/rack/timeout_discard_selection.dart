/// Prefer a physically isolated rack tile, respecting the row boundary.
/// Protected slots (real jokers) still count as occupied neighbours.
int? timeoutDiscardSlot({
  required Iterable<int> occupiedSlots,
  required Set<int> protectedSlots,
  required int columns,
}) {
  final occupied = occupiedSlots.toSet();
  final candidates = occupied.where((s) => !protectedSlots.contains(s)).toList()
    ..sort();
  for (final slot in candidates.reversed) {
    final left = slot % columns > 0 && occupied.contains(slot - 1);
    final right = slot % columns < columns - 1 && occupied.contains(slot + 1);
    if (!left && !right) return slot;
  }
  return candidates.isEmpty ? null : candidates.last;
}
