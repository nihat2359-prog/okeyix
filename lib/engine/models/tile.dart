import 'package:flutter/material.dart';

enum TileColor { red, blue, black, yellow }

extension TileColorStyle on TileColor {
  Color get color {
    switch (this) {
      case TileColor.red:
        return const Color(0xFFB3261E);
      case TileColor.blue:
        return const Color(0xFF1E5CC6);
      case TileColor.black:
        return const Color(0xFF1A1A1A);
      case TileColor.yellow:
        return const Color(0xFFC49A00);
    }
  }
}

class TileModel {
  final int value; // 1–13
  final TileColor color;
  final bool isJoker;
  final bool isFakeJoker;

  const TileModel({
    required this.value,
    required this.color,
    this.isJoker = false,
    this.isFakeJoker = false,
  });
}
