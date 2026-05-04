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
  final String id;
  final int value; // 1–13
  final TileColor color;
  final bool isJoker;
  final bool isFakeJoker;

  const TileModel({
    required this.id,
    required this.value,
    required this.color,
    this.isJoker = false,
    this.isFakeJoker = false,
  });

  factory TileModel.fromJson(Map<String, dynamic> json) {
    return TileModel(
      id: json['id'],
      value: json['value'],
      color: TileColor.values[json['color']],
      isJoker: json['isJoker'] ?? false,
      isFakeJoker: json['isFakeJoker'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'value': value,
      'color': color.index,
      'isJoker': isJoker,
      'isFakeJoker': isFakeJoker,
    };
  }

  bool isSameTile(TileModel other) {
    return id == other.id;
  }

  void validateNoDuplicateTiles(List<TileModel> tiles) {
    final seen = <String>{};

    for (var t in tiles) {
      if (seen.contains(t.id)) {
        throw Exception("Duplicate tile detected!");
      }
      seen.add(t.id);
    }
  }
}
