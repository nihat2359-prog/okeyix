import 'package:flutter/material.dart';

/// Only the signed-in player's completed results in this table session.
class TableSessionScore extends StatelessWidget {
  final int wins;
  final int losses;

  const TableSessionScore({
    super.key,
    required this.wins,
    required this.losses,
  });

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x80101917),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0x44B99B61), width: .6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _value('Galibiyet', wins, const Color(0xFFE4C88D)),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 9),
                width: .6,
                height: 12,
                color: const Color(0x44B99B61),
              ),
              _value('Mağlubiyet', losses, const Color(0xFFCDA59C)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _value(String label, int count, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFFC5C6BC), fontSize: 10),
      ),
      const SizedBox(width: 5),
      Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
