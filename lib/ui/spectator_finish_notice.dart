import 'package:flutter/material.dart';
import 'lobby/lobby_metal_surface.dart';

/// Brief spectator result notice. Timing remains owned by SpectatorScreen.
class SpectatorFinishNotice extends StatelessWidget {
  final String winnerName;
  final String? finishLabel;
  const SpectatorFinishNotice({
    super.key,
    required this.winnerName,
    this.finishLabel,
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0x66050A10),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: LobbyMetalSurface(
              radius: 24,
              metal: const Color(0xFFE5C585),
              surfaceOpacity: 2.4,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          center: Alignment(-.4, -.5),
                          colors: [Color(0xFF53604B), Color(0xFF14211E)],
                        ),
                        border: Border.all(color: const Color(0xFFDDBD7E)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 12,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        size: 38,
                        color: Color(0xFFF0D49A),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ELİN KAZANANI',
                            style: TextStyle(
                              color: Color(0xFFE5C585),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.3,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            winnerName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF4EBDD),
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            finishLabel ?? 'Bu eli kazandı',
                            style: const TextStyle(
                              color: Color(0xFFCBD6D0),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
