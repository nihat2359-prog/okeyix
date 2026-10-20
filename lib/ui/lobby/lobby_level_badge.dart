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
          width: 92,
          height: 26,
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
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '→ $next',
                        style: const TextStyle(
                          color: Color(0xFF8997A8),
                          fontSize: 9,
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
                  minHeight: 3,
                  backgroundColor: const Color(0xFF28323F),
                  color: const Color(0xFFC9A86C),
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
