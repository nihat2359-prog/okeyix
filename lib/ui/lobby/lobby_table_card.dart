import 'package:flutter/material.dart';
import 'lobby_avatar.dart';

class LobbyTableCard extends StatelessWidget {
  final Map<String, dynamic> table;
  final Set<String> blockedUserIds;
  final Function(Map<String, dynamic>) onJoin;
  final Function(Map<String, dynamic>) onSpectate;
  final bool canSpectateAll;
  final Function(Map<String, dynamic>) onUserTap;

  static void _defaultOnSpectate(Map<String, dynamic> _) {}

  const LobbyTableCard({
    super.key,
    required this.table,
    required this.blockedUserIds,
    required this.onJoin,
    this.onSpectate = _defaultOnSpectate,
    this.canSpectateAll = false,
    required this.onUserTap,
  });

  static const Color goldBorderColor = Color(0xCCB07A1A);

  @override
  Widget build(BuildContext context) {
    final maxPlayers = (table['max_players'] as int?) ?? 2;

    final players = ((table['_players'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final status = (table['status']?.toString() ?? 'waiting').trim();
    final isPlaying = status == 'playing';
    final isFake = table['is_fake'] == true;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66146744), Color(0x220F3B2B)],
        ),
        border: Border.all(color: goldBorderColor, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/lobby/table_surface.png',
                fit: BoxFit.fill,
              ),
            ),
          ),

          Positioned(
            left: 10,
            top: 8,
            child: Text(
              'Masa Coin\n${_formatEntryShort((table['entry_coin'] as int?) ?? 0)}',
              style: const TextStyle(
                color: Colors.white,
                height: 1.02,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          if (isPlaying && !isFake)
            Positioned(
              right: 8,
              top: 7,
              child: InkWell(
                onTap: () => onSpectate(table),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFEBC778), Color(0xFFC8942D)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFFFF1BA),
                      width: 1.1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66A16D18),
                        blurRadius: 10,
                        spreadRadius: 0.4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.remove_red_eye_rounded,
                        size: 12,
                        color: Color(0xFF493000),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'IZLE',
                        style: TextStyle(
                          color: Color(0xFF3F2900),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          ...List.generate(maxPlayers, (seat) {
            Map<String, dynamic>? player;

            for (final p in players) {
              if (p['seat_index'] == seat) {
                player = p;
                break;
              }
            }

            return _seatAnchor(
              seatIndex: seat,
              maxPlayers: maxPlayers,
              child: _seatContent(player),
            );
          }),
        ],
      ),
    );
  }

  String _formatEntryShort(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}MİL';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}BİN';
    }
    return '$value';
  }

  Widget _seatAnchor({
    required int seatIndex,
    required int maxPlayers,
    required Widget child,
  }) {
    if (maxPlayers == 2) {
      if (seatIndex == 0) {
        return Positioned(left: 48, right: 48, bottom: 5, child: child);
      }
      return Positioned(left: 48, right: 48, top: 10, child: child);
    }

    switch (seatIndex) {
      case 0:
        return Positioned(left: 48, right: 48, bottom: 14, child: child);
      case 1:
        return Positioned(
          left: 14,
          top: 76,
          child: SizedBox(width: 96, child: child),
        );
      case 2:
        return Positioned(left: 48, right: 48, top: 34, child: child);
      case 3:
      default:
        return Positioned(
          right: 14,
          top: 76,
          child: SizedBox(width: 96, child: child),
        );
    }
  }

  Widget _seatContent(Map<String, dynamic>? player) {
    if (player != null) {
      final userId = player['user_id']?.toString();
      final blocked =
          (player['blocked'] == true) ||
          (userId != null && blockedUserIds.contains(userId));

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => onUserTap(player),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LobbyAvatar(
                username: player['username']?.toString() ?? 'Oyuncu',
                avatarUrl: player['avatar_url']?.toString(),
                size: 18,
                blocked: blocked,
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xCC111A17),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  player['username']?.toString() ?? 'Oyuncu',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => onJoin(table),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFFFFE887), Color(0xFFF2BE3E), Color(0xFFCB8E20)],
          ),
          border: Border.all(color: const Color(0xFFFFF1BA), width: 1.1),
        ),
        child: const Icon(Icons.south_rounded, color: Color(0xFF664407)),
      ),
    );
  }
}
