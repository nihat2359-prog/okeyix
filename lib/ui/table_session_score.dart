import 'package:flutter/material.dart';

/// Only the signed-in player's completed results in this table session.
class TableSessionScore extends StatelessWidget {
  final int wins;
  final int losses;

  const TableSessionScore({super.key, required this.wins, required this.losses});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      width: 72,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xB3101917),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0x66B99B61), width: .7),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Table(
              columnWidths: const {0: FixedColumnWidth(24), 1: FlexColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: const TableBorder(
                horizontalInside: BorderSide(color: Color(0x33B99B61), width: .5),
                verticalInside: BorderSide(color: Color(0x33B99B61), width: .5),
              ),
              children: [
                _row(Icons.emoji_events_rounded, 'Galibiyet', wins, const Color(0xFFE4C88D)),
                _row(Icons.cancel_outlined, 'Mağlubiyet', losses, const Color(0xFFCDA59C)),
              ],
            ),
            const Divider(height: 1, thickness: .5, color: Color(0x55B99B61)),
            Semantics(label: 'Toplam el', child: _number(wins + losses, const Color(0xFFE4C88D))),
          ]),
        ),
      ),
    ),
  );

  TableRow _row(IconData icon, String label, int count, Color color) => TableRow(children: [
    Semantics(label: label, child: SizedBox(height: 19, child: Icon(icon, size: 14, color: color))),
    _number(count, color),
  ]);

  Widget _number(int count, Color color) => SizedBox(
    height: 19,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('$count', maxLines: 1, style: TextStyle(
          color: color, fontSize: 10, fontWeight: FontWeight.w600,
        )),
      ),
    ),
  );
}