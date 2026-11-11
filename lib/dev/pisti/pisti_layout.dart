import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'pisti_model.dart';

/// Coordinates are in the SafeArea's local space. Height drives every card size.
class PistiLayout {
  PistiLayout(this.size);
  final Size size;
  double get w => size.width;
  double get h => size.height;
  bool get compact => h < 330;
  double get handHeight => math.min(156, h * .315);
  double get handWidth => handHeight * .70;
  double get opponentHeight => math.min(100, h * .22);
  double get tableHeight => math.min(132, h * .29);
  Offset get center => Offset(w * .535, h * .43);
  Rect get deck => Rect.fromCenter(
    center: Offset(w * (w < 700 ? .31 : .267), h * .455),
    width: tableHeight * .60,
    height: tableHeight * .86,
  );
  Rect get dropZone => Rect.fromCenter(
    center: center,
    width: math.max(140, w * .23),
    height: h * .38,
  );
  Rect hand(PistiSeat seat, int index, int count, {bool selected = false}) {
    final player = seat == PistiSeat.player;
    final height = player ? handHeight : opponentHeight;
    final width = height * .70;
    final spacing = player ? width + (compact ? 7 : 10) : width * .65;
    final x = w * .535 + (index - (count - 1) / 2) * spacing;
    final curve = (index - (count - 1) / 2).abs() * (player ? 3 : 2);
    final y = player
        ? h - height / 2 - 19 + curve - (selected ? (compact ? 12 : 18) : 0)
        : height / 2 + 12 + curve;
    return Rect.fromCenter(center: Offset(x, y), width: width, height: height);
  }

  double handAngle(int index, int count, PistiSeat seat) =>
      (index - (count - 1) / 2) * (seat == PistiSeat.player ? .035 : -.055);
  Rect tableCard(int index, int count) {
    final relative = index - (count - 1);
    return Rect.fromCenter(
      center:
          center +
          Offset(relative.clamp(-3, 0) * -3.8, relative.clamp(-3, 0) * -2.2),
      width: tableHeight * .70,
      height: tableHeight,
    );
  }

  double tableAngle(int index) => const [-.085, .045, -.025, .065][index % 4];
  Rect collected(PistiSeat seat) => Rect.fromCenter(
    center: Offset(
      w - (compact ? 49 : 61),
      h * (seat == PistiSeat.player ? .73 : .28),
    ),
    width: tableHeight * .43,
    height: tableHeight * .59,
  );
  Rect playerInfo(PistiSeat seat) => Rect.fromLTWH(
    16,
    seat == PistiSeat.opponent ? math.max(76, h * .19) : h * .72,
    math.min(154, w * .235),
    math.min(90, h * .25),
  );
}
