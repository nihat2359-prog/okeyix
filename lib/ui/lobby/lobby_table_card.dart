import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
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
    final spectatorsEnabled = (table['spectators_enabled'] as bool?) ?? true;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x661B222B), Color(0x2210151B)],
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth;
          final cardHeight = constraints.maxHeight;
          return Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.88, 0.04, 0.04, 0, 0,
                  0.04, 0.88, 0.04, 0, 0,
                  0.04, 0.04, 0.88, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/table.png',
                      fit: BoxFit.fill,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/images/lobby/table_surface.png',
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x44101514), Color(0x55101514)],
                        ),
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0, 0.05),
                          radius: 1.0,
                          colors: [Color(0x00101514), Color(0x55101514)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 10,
            top: 8,
            child: _tableMetaColumn(),
          ),
          ..._decorativeDiscardAnchors(cardWidth, cardHeight),
          if (isPlaying && !isFake && spectatorsEnabled)
            Positioned(
              right: 8,
              bottom: 8,
              child: InkWell(
                onTap: () => onSpectate(table),
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.remove_red_eye_rounded,
                        size: 13,
                        color: Color(0xFFE5C57A),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'IZLE',
                        style: TextStyle(
                          color: Color(0xFFE5C57A),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          fontSize: 10.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!(isPlaying && !isFake))
            Positioned(
              right: 10,
              top: 8,
              child: _tableStatusIcons(),
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
      );
        },
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
        return Positioned(left: 48, right: 48, bottom: 18, child: child);
      }
      return Positioned(left: 48, right: 48, top: 10, child: child);
    }

    switch (seatIndex) {
      case 0:
        return Positioned(left: 48, right: 48, bottom: 28, child: child);
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
                size: 24,
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
      child: const _JoinSeatButton(),
    );
  }

  Widget _tableMetaColumn() {
    final entryCoin = (table['entry_coin'] as int?) ?? 0;
    final roundCount = (table['round_count'] as int?) ?? 1;
    final potAmount = (table['pot_amount'] as int?) ?? 0;
    final turnSeconds = (table['turn_seconds'] as int?) ?? 20;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x770B1512),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x44E7C06A), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metaItem(
            icon: Icons.monetization_on_rounded,
            text: Format.coin(entryCoin),
            highlight: true,
          ),
          const SizedBox(height: 4),
          _metaItem(icon: Icons.flag_rounded, text: '$roundCount'),
          const SizedBox(height: 4),
          _metaItem(
            icon: Icons.soup_kitchen_rounded,
            text: Format.coin(potAmount),
            accentColor: const Color(0xFFFFB347),
          ),
        ],
      ),
    );
  }

  Widget _tableStatusIcons() {
    final turnSeconds = (table['turn_seconds'] as int?) ?? 20;
    final isFastTable = turnSeconds == 15;
    final spectatorsEnabled = (table['spectators_enabled'] as bool?) ?? true;
    final chatEnabled = (table['chat_enabled'] as bool?) ?? true;
    final showSpectatorOff = !spectatorsEnabled;
    final showChatOff = !chatEnabled;
    final hasStatusGroup = isFastTable || showSpectatorOff || showChatOff;

    if (!hasStatusGroup) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x770B1512),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x44E7C06A), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFastTable) _metaIconOnly(Icons.flash_on_rounded),
          if (isFastTable && (showSpectatorOff || showChatOff))
            const SizedBox(height: 4),
          if (showSpectatorOff) _metaStruckIcon(Icons.visibility_rounded),
          if (showSpectatorOff && showChatOff) const SizedBox(height: 4),
          if (showChatOff) _metaIconOnly(Icons.sms_failed_rounded),
        ],
      ),
    );
  }

  Widget _metaItem({
    required IconData icon,
    required String text,
    bool highlight = false,
    Color? accentColor,
  }) {
    final baseColor =
        accentColor ?? (highlight ? const Color(0xFFE7C06A) : Colors.white70);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: baseColor,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: accentColor ?? (highlight ? const Color(0xFFE7C06A) : Colors.white),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _metaIconOnly(IconData icon) {
    return Icon(icon, size: 14, color: const Color(0xFFE7C06A));
  }

  Widget _metaStruckIcon(IconData icon) {
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFE7C06A)),
          Transform.rotate(
            angle: 0.75,
            child: Container(
              width: 1.6,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFFE7C06A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _decorativeDiscardAnchors(double cardWidth, double cardHeight) {
    final sideInset = (cardWidth * 0.28).clamp(28.0, 64.0);
    final topOffset = (cardHeight * 0.25).clamp(34.0, 52.0);
    final bottomOffset = (cardHeight * 0.24).clamp(32.0, 50.0);
    return [
      Positioned(
        left: sideInset,
        top: topOffset,
        child: const IgnorePointer(child: _LobbyDiscardDecor(rotation: 0)),
      ),
      Positioned(
        right: sideInset,
        top: topOffset,
        child: const IgnorePointer(child: _LobbyDiscardDecor(rotation: 0)),
      ),
      Positioned(
        left: sideInset,
        bottom: bottomOffset,
        child: const IgnorePointer(child: _LobbyDiscardDecor(rotation: 0)),
      ),
      Positioned(
        right: sideInset,
        bottom: bottomOffset,
        child: const IgnorePointer(child: _LobbyDiscardDecor(rotation: 0)),
      ),
    ];
  }
}

class _LobbyDiscardDecor extends StatelessWidget {
  final double rotation;

  const _LobbyDiscardDecor({required this.rotation});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotation,
      child: CustomPaint(
        size: const Size(22, 30),
        painter: const _LobbyPremiumDiscardPainter(),
      ),
    );
  }
}

class _LobbyPremiumDiscardPainter extends CustomPainter {
  const _LobbyPremiumDiscardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x6A1E2D26), Color(0x32101814)],
      ).createShader(rect);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xA9896235);
    final gloss = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x22FFF1C8), Color(0x00FFF1C8)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.5));

    canvas.drawRRect(outer, body);
    canvas.drawRRect(outer, gloss);
    canvas.drawRRect(outer, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _JoinSeatButton extends StatefulWidget {
  const _JoinSeatButton();

  @override
  State<_JoinSeatButton> createState() => _JoinSeatButtonState();
}

class _JoinSeatButtonState extends State<_JoinSeatButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.25, -0.25),
              radius: 1.05,
              colors: [Color(0xFFFFE08F), Color(0xFFC48722)],
            ),
            border: Border.all(color: const Color(0xFFFFF2C7), width: 1.35),
            boxShadow: [
              BoxShadow(
                color: const Color(0x703A2200),
                blurRadius: 8 + (t * 3),
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: const Color(0x88E1A63E).withOpacity(0.45 + (t * 0.25)),
                blurRadius: 10 + (t * 3),
                spreadRadius: 0.35,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x66FFF4D6), width: 1),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -1 + (t * 2)),
                child: const Icon(
                  Icons.login_rounded,
                  size: 19,
                  color: Color(0xFF4E3000),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
