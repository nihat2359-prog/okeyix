import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'lobby_avatar.dart';
import '../bot_badge.dart';

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
    final starting = table['status'] == 'start';
    final fake = table['is_fake'] == true;
    final spectators = table['spectators_enabled'] != false;
    final chat = table['chat_enabled'] != false;
    final canWatch = full && playing && !fake && spectators && canSpectateAll;
    final canJoin = !full && table['status'] == 'waiting';
    final seconds = (table['turn_seconds'] as int?) ?? 20;
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = bounds.maxWidth < 220 ? 220.0 : bounds.maxWidth;
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: width,
            height:
                116 +
                (MediaQuery.textScalerOf(context).scale(48) - 48).clamp(0, 72),
            child: Material(
              color: Colors.transparent,
              child: CustomPaint(
                painter: _TableStagePainter(active: canJoin),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(17, 12, 17, 17),
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: _seat(seats[0], 19, 0, canJoin),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.monetization_on_rounded,
                                        size: 12,
                                        color: gold,
                                      ),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: _fit(
                                          Format.coin(
                                            (table['entry_coin'] as int?) ?? 0,
                                          ),
                                          17,
                                          bold: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  if (starting)
                                    const FittedBox(
                                      child: Text(
                                        'BAŞLIYOR',
                                        style: TextStyle(
                                          color: gold,
                                          fontSize: 8,
                                        ),
                                      ),
                                    ),
                                  FittedBox(
                                    child: Text(
                                      'GİRİŞ',
                                      style: TextStyle(
                                        color: gold.withValues(alpha: .65),
                                        fontSize: 7,
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                  ),
                                  if (canWatch)
                                    SizedBox(
                                      height: 24,
                                      child: TextButton(
                                        key: ValueKey(
                                          'spectate-${table['id']}',
                                        ),
                                        onPressed: () => onSpectate(table),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          foregroundColor: gold,
                                          minimumSize: Size.zero,
                                        ),
                                        child: const Text(
                                          'İZLE',
                                          style: TextStyle(fontSize: 9),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 52,
                              child: _seat(seats[1], 19, 1, canJoin),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: _detail(
                              Icons.emoji_events_outlined,
                              Format.coin((table['pot_amount'] as int?) ?? 0),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: _fit(
                              '${table['round_count'] ?? 1} el · $seconds sn',
                              8,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: spectators
                                ? 'Seyirci açık'
                                : 'Seyirci kapalı',
                            child: Icon(
                              spectators
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 11,
                              color: const Color(0xFFADBDB5),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Tooltip(
                            message: chat ? 'Sohbet açık' : 'Sohbet kapalı',
                            child: Icon(
                              chat
                                  ? Icons.chat_bubble_outline_rounded
                                  : Icons.comments_disabled_outlined,
                              size: 10,
                              color: const Color(0xFFADBDB5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
            Stack(
              alignment: Alignment.bottomCenter,
              children: [
                LobbyAvatar(
                  premium: true,
                  username: name,
                  avatarUrl: player['avatar_url']?.toString(),
                  size: radius,
                  blocked:
                      player['blocked'] == true ||
                      blockedUserIds.contains(player['user_id']?.toString()),
                ),
                if (player['is_bot'] == true)
                  const Positioned(bottom: 0, child: BotBadge()),
              ],
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
                canJoin ? Icons.add_rounded : Icons.lock_outline_rounded,
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

/// Static felt and brushed rail: no continuous animation or image allocation.
class _TableStagePainter extends CustomPainter {
  final bool active;
  const _TableStagePainter({required this.active});
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
      rect.deflate(2),
      const Radius.circular(30),
    );
    canvas.drawRRect(
      outer.shift(const Offset(0, 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x6604080B),
    );
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF8C7751),
            Color(0xFF282E2C),
            Color(0xFFB59B68),
            Color(0xFF353B35),
          ],
          stops: [0, .35, .72, 1],
        ).createShader(rect),
    );
    final felt = RRect.fromRectAndRadius(
      rect.deflate(5),
      const Radius.circular(27),
    );
    canvas.drawRRect(
      felt,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.3),
          radius: 1,
          colors: active
              ? const [Color(0xD0214B40), Color(0xDC0B201F)]
              : const [Color(0xD0243C37), Color(0xDC0C1B1E)],
        ).createShader(rect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(9), const Radius.circular(23)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..color = const Color(0x447DA58E),
    );
    canvas.save();
    canvas.clipRRect(felt);
    // Short, interlaced fibres give felt a soft nap without a repeating stripe.
    // Deterministic paths keep the texture still and require only two draws.
    final lightFibres = Path();
    final darkFibres = Path();
    var row = 0;
    for (double y = 6; y < size.height - 5; y += 3.1, row++) {
      var column = 0;
      for (
        double x = 6 + (row.isEven ? 0 : 1.7);
        x < size.width - 5;
        x += 3.4, column++
      ) {
        final seed = (row * 37 + column * 17) % 23;
        final dx = (seed % 5) * .18;
        final dy = (seed % 7) * .13;
        lightFibres.moveTo(x + dx, y + dy);
        lightFibres.lineTo(x + dx + .8, y + dy - .55);
        darkFibres.moveTo(x + .8, y + 1.1);
        darkFibres.lineTo(x + 1.55, y + 1.65);
      }
    }
    canvas.drawPath(
      lightFibres,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5
        ..color = const Color(0x2477AF8C),
    );
    canvas.drawPath(
      darkFibres,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .45
        ..color = const Color(0x26031410),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.25, -.45),
          radius: 1.1,
          colors: [Color(0x0C8EB995), Color(0x00000000), Color(0x33020806)],
          stops: [0, .5, 1],
        ).createShader(rect),
    );
    canvas.restore();
    for (final x in [size.width * .29, size.width * .71]) {
      canvas.drawLine(
        Offset(x, 43),
        Offset(x, 88),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x007CA78E), Color(0x557CA78E), Color(0x007CA78E)],
          ).createShader(Rect.fromLTWH(x, 43, 1, 45))
          ..strokeWidth = .7,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TableStagePainter oldDelegate) =>
      active != oldDelegate.active;
}
