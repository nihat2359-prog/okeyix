import 'package:flutter/material.dart';
import 'table_session_score.dart';

class SpectatorTableScores extends StatelessWidget {
  final List<Map<String, dynamic>> players;
  const SpectatorTableScores({super.key, required this.players});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (MediaQuery.sizeOf(context).width * .42).clamp(200, 260),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in players.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        p['username']?.toString() ?? 'Oyuncu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE4C88D),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TableSessionScore(
                      wins: (p['wins'] as num?)?.toInt() ?? 0,
                      losses: (p['losses'] as num?)?.toInt() ?? 0,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Outside the game's fixed 16:9 viewport, so wide phones have no black side bars.
class SpectatorBackdrop extends StatelessWidget {
  const SpectatorBackdrop({super.key});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/lobby/lobby.png',
    fit: BoxFit.fill,
    width: double.infinity,
    height: double.infinity,
  );
}
