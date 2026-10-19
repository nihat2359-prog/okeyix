import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'lobby_avatar.dart';

/// Two-seat table listing. Callbacks retain the lobby's server-side checks.
class LobbyTableListingCard extends StatelessWidget {
  final Map<String, dynamic> table;
  final int number;
  final Set<String> blockedUserIds;
  final Function(Map<String, dynamic>) onJoin, onSpectate, onUserTap;
  final bool canSpectateAll;

  const LobbyTableListingCard({
    super.key,
    required this.table,
    required this.number,
    required this.blockedUserIds,
    required this.onJoin,
    required this.onSpectate,
    required this.onUserTap,
    required this.canSpectateAll,
  });

  static const gold = Color(0xFFE6CC91);

  @override
  Widget build(BuildContext context) {
    final players = ((table['_players'] as List?) ?? const [])
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    final seats = List<Map<String, dynamic>?>.generate(2, (seat) {
      for (final player in players) {
        if (player['seat_index'] == seat) return player;
      }
      return null;
    });
    final full = seats.every((p) => p != null);
    final playing = table['status'] == 'playing';
    final fake = table['is_fake'] == true;
    final spectators = table['spectators_enabled'] != false;
    final chat = table['chat_enabled'] != false;
    final canWatch = full && playing && !fake && spectators && canSpectateAll;
    final canJoin = !full && !playing;
    final seconds = (table['turn_seconds'] as int?) ?? 20;
    final label = canJoin
        ? 'KATIL'
        : canWatch
        ? 'İZLE'
        : full
        ? 'DOLU'
        : 'OYUNDA';
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xED171C25), Color(0xD9090E16)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x448E929C), width: .7),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final radius = ((bounds.maxHeight - 16) / 2).clamp(7.0, 19.0);
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Expanded(
                        child: _detail(
                          Icons.monetization_on_rounded,
                          Format.coin((table['entry_coin'] as int?) ?? 0),
                        ),
                      ),
                      Expanded(
                        child: _detail(
                          Icons.emoji_events_outlined,
                          Format.coin((table['pot_amount'] as int?) ?? 0),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _fit(
                                '${table['round_count'] ?? 1} el · $seconds sn',
                                9,
                              ),
                            ),
                            Tooltip(
                              message: spectators
                                  ? 'Seyirci açık'
                                  : 'Seyirci kapalı',
                              child: Icon(
                                spectators
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: gold,
                                size: 11,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Tooltip(
                              message: chat ? 'Sohbet açık' : 'Sohbet kapalı',
                              child: Icon(
                                chat
                                    ? Icons.chat_bubble_outline_rounded
                                    : Icons.comments_disabled_outlined,
                                color: gold,
                                size: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  flex: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      gradient: const RadialGradient(
                        radius: .9,
                        colors: [Color(0x182F4A42), Color(0x002F4A42)],
                      ),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < 2; i++)
                          Expanded(child: _seat(seats[i], radius, i, canJoin)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                SizedBox(
                  width: 52,
                  height: 44,
                  child: Tooltip(
                    message: canJoin
                        ? 'Masaya katıl'
                        : canWatch
                        ? 'Masayı izle'
                        : playing
                        ? 'Oyun devam ediyor'
                        : 'Masa dolu',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.transparent,
                        border: Border.all(
                          color: canJoin || canWatch
                              ? const Color(0x80E6CC91)
                              : const Color(0x335F6875),
                        ),
                      ),
                      child: InkWell(
                        key: ValueKey(
                          '${canWatch ? 'spectate' : 'join'}-${table['id']}',
                        ),
                        borderRadius: BorderRadius.circular(20),
                        onTap: canJoin
                            ? () => onJoin(table)
                            : canWatch
                            ? () => onSpectate(table)
                            : null,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _seat(
    Map<String, dynamic>? player,
    double radius,
    int index,
    bool canJoin,
  ) {
    final name = player?['username']?.toString() ?? 'Oyuncu';
    return InkWell(
      key: ValueKey('seat-${table['id']}-$index'),
      borderRadius: BorderRadius.circular(40),
      onTap: player != null
          ? () => onUserTap(player)
          : canJoin
          ? () => onJoin(table)
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (player != null)
            LobbyAvatar(
              username: name,
              avatarUrl: player['avatar_url']?.toString(),
              size: radius,
              blocked:
                  player['blocked'] == true ||
                  blockedUserIds.contains(player['user_id']?.toString()),
            )
          else
            Container(
              width: radius * 2,
              height: radius * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x33000000),
                border: Border.all(color: const Color(0x668DA495)),
              ),
              child: Icon(
                Icons.add_rounded,
                size: radius,
                color: const Color(0xFFADC0B2),
              ),
            ),
          const SizedBox(height: 2),
          SizedBox(
            height: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Tooltip(
                message: player == null ? 'Boş yer' : name,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    player == null ? '' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFE2E5EB),
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String text) => Semantics(
    label: '${icon == Icons.monetization_on_rounded ? 'Giriş' : 'Ödül'} $text',
    child: Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CustomPaint(
            painter: _StakeEmblem(
              reward: icon != Icons.monetization_on_rounded,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(child: _fit(text, 10)),
      ],
    ),
  );

  Widget _fit(String text, double size, {bool bold = false}) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(
        color: bold ? const Color(0xFFF3E7CB) : const Color(0xFFC4CBD6),
        fontSize: size,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      ),
    ),
  );
}

/// Small metal tokens remain static and readable at compact listing sizes.
class _StakeEmblem extends CustomPainter {
  final bool reward;
  const _StakeEmblem({required this.reward});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 14, size.height / 14);
    final metal = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFEABD),
          Color(0xFFDBB565),
          Color(0xFF936322),
          Color(0xFFF2CF82),
        ],
        stops: [0, .4, .78, 1],
      ).createShader(const Rect.fromLTWH(0, 0, 14, 14));
    if (reward) {
      for (var i = 0; i < 3; i++) {
        final y = 10.5 - i * 3;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(1, y - 1, 9, 3),
            const Radius.circular(1),
          ),
          metal,
        );
        canvas.drawLine(
          Offset(2, y + 1),
          Offset(9, y + 1),
          Paint()
            ..color = const Color(0xFF755023)
            ..strokeWidth = .5,
        );
      }
      canvas.drawCircle(const Offset(9, 7), 4.2, metal);
      canvas.drawCircle(
        const Offset(9, 7),
        2.9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = const Color(0xFF815923),
      );
      final gem = Path()
        ..moveTo(9, 4.8)
        ..lineTo(10.5, 7)
        ..lineTo(9, 9.2)
        ..lineTo(7.5, 7)
        ..close();
      canvas.drawPath(gem, Paint()..color = const Color(0xFFFFE9AF));
    } else {
      canvas.drawCircle(
        const Offset(7, 7.6),
        6,
        Paint()..color = const Color(0xFF735024),
      );
      canvas.drawCircle(const Offset(7, 6.6), 6, metal);
      canvas.drawCircle(
        const Offset(7, 6.6),
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7
          ..color = const Color(0xFF98672D),
      );
      final stamp = Path()
        ..moveTo(7, 3.3)
        ..lineTo(9, 6.6)
        ..lineTo(7, 9.9)
        ..lineTo(5, 6.6)
        ..close();
      canvas.drawPath(stamp, Paint()..color = const Color(0xFF8C5E24));
      canvas.drawLine(
        const Offset(6, 6.6),
        const Offset(7, 4.5),
        Paint()
          ..color = const Color(0xFFFFEFBE)
          ..strokeWidth = .7,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StakeEmblem oldDelegate) =>
      reward != oldDelegate.reward;
}
