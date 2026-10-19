import 'package:flutter/material.dart';

/// The preview keeps the larger share; league content may scroll independently.
class LobbyColumns extends StatelessWidget {
  final Widget leagues;
  final Widget tables;
  const LobbyColumns({super.key, required this.leagues, required this.tables});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: bounds.maxWidth * .46, child: leagues),
        const SizedBox(width: 8),
        Expanded(child: tables),
      ],
    ),
  );
}
