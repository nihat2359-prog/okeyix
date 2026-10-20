/// A minimum scale can make a tile wider than its slot on small screens.
/// Leave a small, real gap instead; do not change slot indices or ordering.
double finishTileScale(double slotWidth, double baseWidth) =>
    ((slotWidth - 1.6).clamp(1.0, slotWidth) / baseWidth).toDouble();
