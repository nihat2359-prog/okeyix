import 'package:flutter/material.dart';
import 'game_world.dart';

Future<bool?> showPistiInviteWindow(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => GameWindow(
    title: const Text('Pişti Molası daveti'),
    content: const Row(
      children: [
        SizedBox(
          width: 110,
          height: 100,
          child: GameArtwork(kind: GameArtKind.pisti),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Text(
            'Arkadaşın seni ücretsiz Pişti Molası’na davet ediyor. Coin veya rating değişmez. Davet 60 saniye geçerlidir.',
            style: TextStyle(height: 1.5, fontSize: 13),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Reddet'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Katıl'),
      ),
    ],
  ),
);
