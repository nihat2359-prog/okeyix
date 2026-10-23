import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'lobby_avatar.dart';
import '../bot_badge.dart';
import '../display_okey_tile.dart';

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
    final canWatch = full && playing && !fake && spectators && canSpectateAll;
    final canJoin = !full && table['status'] == 'waiting';
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = bounds.maxWidth < 220 ? 220.0 : bounds.maxWidth;
        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: width,
            height:
                142 +
                (MediaQuery.textScalerOf(context).scale(48) - 48).clamp(0, 72),
            child: Material(
              color: Colors.transparent,
              child: CustomPaint(
                painter: _TableStagePainter(active: canJoin),
                child: Stack(
                  children: [
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 29,
                      height: 34,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: CustomPaint(
                            painter: OpeningOkeyTilesPainter(),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 16, 13, 18),
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 66,
                                  child: _seat(seats[0], 22, 0, canJoin),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.monetization_on_rounded,
                                            size: 15,
                                            color: gold,
                                          ),
                                          const SizedBox(width: 3),
                                          Flexible(
                                            child: _fit(
                                              Format.coin(
                                                (table['entry_coin'] as int?) ??
                                                    0,
                                              ),
                                              21,
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
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      FittedBox(
                                        child: Text(
                                          'GİRİŞ',
                                          style: TextStyle(
                                            color: gold.withValues(alpha: .85),
                                            fontSize: 10,
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
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                SizedBox(
                                  width: 66,
                                  child: _seat(seats[1], 22, 1, canJoin),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 21),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _detail(
                                    Icons.emoji_events_outlined,
                                    Format.coin(
                                      (table['pot_amount'] as int?) ?? 0,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _fit(
                                      '${table['round_count'] ?? 0}. el',
                                      12,
                                    ),
                                  ),
                                ),
                              ],
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
            _RaisedSeatButton(radius: radius, enabled: canJoin),
          const SizedBox(height: 4),
          SizedBox(
            height: 20,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
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
                      fontSize: 12,
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
        Expanded(child: _fit(text, 12)),
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

/// Pointer feedback is local to the empty seat; the parent owns the join action.
class _RaisedSeatButton extends StatefulWidget {
  final double radius;
  final bool enabled;
  const _RaisedSeatButton({required this.radius, required this.enabled});

  @override
  State<_RaisedSeatButton> createState() => _RaisedSeatButtonState();
}

class _RaisedSeatButtonState extends State<_RaisedSeatButton> {
  bool _pressed = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final pressed = widget.enabled && _pressed;
    return Listener(
      onPointerDown: widget.enabled ? (_) => _press(true) : null,
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, pressed ? 2 : 0, 0),
        width: widget.radius * 2,
        height: widget.radius * 2,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFE6AD), Color(0xFFB28A47), Color(0xFF5B411E)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xAA020C09),
              offset: Offset(1, pressed ? 1 : 4),
              blurRadius: pressed ? 2 : 5,
            ),
          ],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: pressed
                  ? const [Color(0xFF102B23), Color(0xFF245342)]
                  : const [Color(0xFF376B54), Color(0xFF102B23)],
            ),
            border: Border.all(color: const Color(0x557BAD8B), width: .7),
          ),
          child: Icon(
            widget.enabled ? Icons.add_rounded : Icons.lock_outline_rounded,
            size: widget.radius * (widget.enabled ? 1.5 : 1),
            color: widget.enabled
                ? const Color(0xFFFFEBC1)
                : const Color(0xFFADC0B2),
            shadows: const [
              Shadow(
                color: Color(0xBB000000),
                offset: Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
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

/// Shallow perspective table, painted once per state with a translucent felt.
class _TableStagePainter extends CustomPainter {
  final bool active;
  const _TableStagePainter({required this.active});

  Path _rim(Size size, double inset, double drop) {
    final w = size.width;
    final h = size.height;
    // Narrower back edge and gently splayed sides imply a view from above.
    return Path()
      ..moveTo(30 + inset, 3 + inset + drop)
      ..lineTo(w - 30 - inset, 3 + inset + drop)
      ..quadraticBezierTo(
        w - 14 - inset,
        3 + inset + drop,
        w - 11 - inset,
        20 + inset + drop,
      )
      ..lineTo(w - 3 - inset, h - 26 - inset + drop)
      ..quadraticBezierTo(
        w - inset,
        h - 8 - inset + drop,
        w - 25 - inset,
        h - 8 - inset + drop,
      )
      ..lineTo(25 + inset, h - 8 - inset + drop)
      ..quadraticBezierTo(
        inset,
        h - 8 - inset + drop,
        3 + inset,
        h - 26 - inset + drop,
      )
      ..lineTo(11 + inset, 20 + inset + drop)
      ..quadraticBezierTo(
        14 + inset,
        3 + inset + drop,
        30 + inset,
        3 + inset + drop,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final top = _rim(size, 0, 0);
    final felt = _rim(size, 6, 0);
    // Keep every opaque rail, sidewall and shadow draw outside the felt.
    // Transparency must reveal the lobby, rather than a lower body layer.
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(24))
        ..addPath(felt, Offset.zero),
    );
    canvas.drawShadow(
      top.shift(const Offset(1, 4)),
      const Color(0xB0000609),
      5,
      true,
    );
    // Only the exposed sidewall is opaque: the centre remains see-through.
    final side = Path.combine(PathOperation.difference, _rim(size, 0, 5), top);
    canvas.drawPath(
      side,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF78502A), Color(0xFF23140D)],
        ).createShader(rect),
    );
    final wood = Path.combine(PathOperation.difference, top, felt);
    canvas.drawPath(
      wood,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF967044),
            Color(0xFF46301D),
            Color(0xFF76502A),
            Color(0xFF2C1B11),
          ],
          stops: [0, .35, .7, 1],
        ).createShader(rect),
    );
    canvas.drawPath(
      top,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3D99D), Color(0xFFB98D48), Color(0xFF584025)],
        ).createShader(rect),
    );
    canvas.restore();
    canvas.drawPath(
      felt,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, -.55),
          radius: 1.2,
          colors: active
              ? const [Color(0x80245A43), Color(0x990A241E)]
              : const [Color(0x80244C3D), Color(0x990A201C)],
        ).createShader(rect),
    );
    canvas.drawPath(
      felt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..color = const Color(0x887FA16B),
    );
    canvas.save();
    canvas.clipPath(felt);
    canvas.drawPath(
      felt.shift(const Offset(0, 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x66010D09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    final fibres = Path();
    for (double y = 10; y < size.height - 10; y += 3.2) {
      for (double x = 10; x < size.width - 10; x += 4.1) {
        final drift = (x.toInt() * 13 + y.toInt() * 7) % 5 * .2;
        fibres.moveTo(x, y + drift);
        fibres.lineTo(x + .9, y + drift - .5);
      }
    }
    canvas.drawPath(
      fibres,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5
        ..color = const Color(0x207DAE8A),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TableStagePainter oldDelegate) => true;
}
