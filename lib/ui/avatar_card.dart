import 'dart:math';
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'avatar_preset.dart';
import '../models/player_model.dart';

enum AvatarPosition { bottom, top, left, right }

class AvatarCard extends StatelessWidget {
  final PlayerModel player;
  final AvatarPosition position;
  final double progress;
  final VoidCallback? onTap;
  const AvatarCard({
    super.key,
    required this.player,
    required this.position,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;

    switch (position) {
      case AvatarPosition.bottom:
      case AvatarPosition.top:
        content = _buildHorizontal();
        break;
      case AvatarPosition.left:
      case AvatarPosition.right:
        content = _buildVertical();
        break;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, // 🔥 burada yakalanıyor
        borderRadius: BorderRadius.circular(16), // kart radius ile uyumlu olsun
        child: content,
      ),
    );
  }

  Widget _buildHorizontal() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _decoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAvatarWithTimer(),
          const SizedBox(width: 10),
          _buildInfo(crossAxis: CrossAxisAlignment.start),
        ],
      ),
    );
  }

  Widget _buildVertical() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: _decoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAvatarWithTimer(),
          const SizedBox(height: 6),
          _buildInfo(crossAxis: CrossAxisAlignment.center),
        ],
      ),
    );
  }

  Widget _buildInfo({required CrossAxisAlignment crossAxis}) {
    return Column(
      crossAxisAlignment: crossAxis,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 80),
          child: Text(
            player.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          Format.coin(player.coins),
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFD4AF37),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          'R: ${Format.rating(player.rating)}',
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFFBBD0E4),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarWithTimer() {
    double ratio = (player.remainingTime / 15).clamp(0.0, 1.0);

    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // GOLD TIMER RING
          CustomPaint(
            size: const Size(70, 70),
            painter: _CircleTimerPainter(progress),
          ),

          // AVATAR
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: player.isActive
                  ? [
                      const BoxShadow(
                        color: Color(0x55D4AF37),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
            child: ClipOval(
              child: SizedBox(width: 54, height: 54, child: _avatarImage()),
            ),
          ),
          if (player.isDoubleMode)
            Positioned(
              right: -2,
              top: -2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE53935), Color(0xFFB71C1C)],
                  ),
                  border: Border.all(color: const Color(0x55FFFFFF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66200000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 10, color: Colors.white),
                      SizedBox(width: 2),
                      Text(
                        'ÇİFTE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatarImage() {
    final raw = player.avatarPath.trim();
    final status = player.avatarStatus; // 🔥 bunu modelden al

    Widget image;

    if (raw.startsWith('assets/')) {
      image = Image.asset(raw, width: 54, height: 54, fit: BoxFit.cover);
    } else if (raw.startsWith('http')) {
      image = Image.network(
        raw,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => _avatarTextFallback(),
      );
    } else if (isKnownAvatarPreset(raw)) {
      final img = avatarPresetByRef(raw);
      image = Image.asset(
        img.imageUrl,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
      );
    } else {
      image = _avatarTextFallback();
    }

    // 🔥 STACK İLE WRAP
    return Stack(
      children: [
        ClipOval(child: image),

        // 🔥 PENDING BADGE
        if (status == 'pending')
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE9C46A), width: 1),
              ),
              child: const Icon(
                Icons.schedule, // ⏳
                size: 12,
                color: Color(0xFFE9C46A),
              ),
            ),
          ),
      ],
    );
  }

  Widget _avatarTextFallback() {
    return Container(
      color: const Color(0xFF263229),
      alignment: Alignment.center,
      child: Text(
        player.name.isEmpty ? '?' : player.name[0].toUpperCase(),
        style: const TextStyle(
          color: Color(0xFFE7D9B4),
          fontWeight: FontWeight.w900,
          fontSize: 24,
        ),
      ),
    );
  }

  BoxDecoration _decoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: const LinearGradient(
        colors: [Color(0xCC141A20), Color(0xAA0F141A)],
      ),
      border: Border.all(
        color: player.isActive
            ? const Color(0x55D4AF37)
            : const Color(0x22FFFFFF),
      ),
      boxShadow: player.isActive
          ? [
              const BoxShadow(
                color: Color(0x33D4AF37),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ]
          : [],
    );
  }
}

class _CircleTimerPainter extends CustomPainter {
  final double progress;

  _CircleTimerPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final ringColor = _ringColor(progress);
    final ringGlow = Color.lerp(ringColor, Colors.white, 0.35) ?? ringColor;

    final backgroundPaint = Paint()
      ..color = ringColor.withAlpha(55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: [ringColor, ringGlow],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    // Background ring
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2,
      backgroundPaint,
    );

    // Progress ring
    double sweepAngle = 2 * pi * progress;

    canvas.drawArc(rect, -pi / 2, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _CircleTimerPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }

  Color _ringColor(double value) {
    final p = value.clamp(0.0, 1.0);
    if (p >= 0.5) {
      final t = (p - 0.5) / 0.5;
      return Color.lerp(const Color(0xFFF2C94C), const Color(0xFF32D074), t) ??
          const Color(0xFF32D074);
    }
    final t = p / 0.5;
    return Color.lerp(const Color(0xFFE64B3C), const Color(0xFFF2C94C), t) ??
        const Color(0xFFE64B3C);
  }
}
