import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';

/// Progress within the current level, with no maximum user level.
class LobbyLevelBadge extends StatelessWidget {
  const LobbyLevelBadge({super.key, required this.rating});
  final int rating;
  @override
  Widget build(BuildContext context) {
    final level = Format.ratingLevel(rating);
    final next = level + 1;
    final remaining = (next * Format.ratingLevelStep) - rating;
    final progress = Format.ratingLevelProgress(rating);
    return Tooltip(
      message: 'Seviye $next için $remaining puan',
      child: Semantics(
        label: 'Seviye $level. Seviye $next için $remaining puan.',
        child: SizedBox(
          width: 106,
          height: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        'Seviye $level',
                        style: const TextStyle(
                          color: Color(0xFFE5D3AA),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '→ $next',
                        style: const TextStyle(
                          color: Color(0xFF8997A8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: const Color(0xFF131820),
                  color: const Color(0xFFFFCE68),
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}
