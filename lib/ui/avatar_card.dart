import 'dart:math';
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'avatar_preset.dart';
import '../models/player_model.dart';
import 'periodic_ui_builder.dart';

enum AvatarPosition { bottom, top, left, right }

class AvatarCard extends StatelessWidget {
  final PlayerModel player;
  final AvatarPosition position;
  final double progress;
  final double Function()? progressReader;
  final bool animateProgress;
  final bool showRating;
  final bool showRatingProgress;
  final VoidCallback? onTap;
  const AvatarCard({
    super.key,
    required this.player,
    required this.position,
    required this.progress,
    this.progressReader,
    this.animateProgress = false,
    this.showRating = true,
    this.showRatingProgress = true,
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
        onTap: onTap, // ğŸ”¥ burada yakalanÄ±yor
        borderRadius: BorderRadius.circular(16), // kart radius ile uyumlu olsun
        child: content,
      ),
    );
  }

  Widget _buildHorizontal() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: _panelDecoration(isVertical: false),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: _panelDecoration(isVertical: true),
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
    final alignStart = crossAxis == CrossAxisAlignment.start;
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
              color: const Color(0xFFF4EBD7),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCoinBubble(),
            if (showRating) ...[
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: alignStart
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRatingBubble(),
                  if (showRatingProgress) ...[
                    const SizedBox(height: 4),
                    _buildRatingProgress(),
                  ],
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCoinBubble() {
    return _buildStatBubble(
      icon: Icons.monetization_on_rounded,
      labelWidget: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: player.coins.toDouble()),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Text(
            Format.coin(value.round()),
            style: TextStyle(
              fontSize: 10.5,
              color: const Color(0xFFE7C77B),
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          );
        },
      ),
      active: player.isActive,
      colors: const [Color(0xFF20382F), Color(0xFF12231E)],
      textColor: const Color(0xFFE7C77B),
    );
  }

  Widget _buildRatingBubble() {
    return _buildStatBubble(
      icon: Icons.star_rounded,
      labelWidget: Text(
        Format.rating(player.rating),
        style: const TextStyle(
          fontSize: 10.5,
          color: Color(0xFFE7C77B),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.1,
        ),
      ),
      active: player.isActive,
      colors: const [Color(0xFF20382F), Color(0xFF12231E)],
      textColor: const Color(0xFFE7C77B),
    );
  }

  Widget _buildStatBubble({
    required IconData icon,
    required Widget labelWidget,
    required bool active,
    required List<Color> colors,
    required Color textColor,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: active ? colors : [colors[0].withOpacity(0.92), colors[1]],
        ),
        border: Border.all(
          color: active ? const Color(0x99D9C18A) : const Color(0x556D806F),
          width: 0.8,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: colors[1].withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                ),
              ]
            : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 11, color: textColor),
          const SizedBox(width: 3),
          DefaultTextStyle.merge(
            style: const TextStyle(height: 1.0),
            child: labelWidget,
          ),
        ],
      ),
    );
  }

  Widget _buildRatingProgress() {
    final progress = Format.ratingProgress(player.rating).clamp(0.0, 1.0);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 92),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: const Color(0x664A5C53),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF2D48B), Color(0xFFE0B54F)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66E7C77B),
                      blurRadius: 6,
                      spreadRadius: 0.4,
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

  Widget _buildAvatarWithTimer() {
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: PeriodicUiBuilder(
              interval: const Duration(milliseconds: 33),
              enabled:
                  animateProgress && player.isActive && progressReader != null,
              builder: (_) {
                final current = progressReader?.call() ?? progress;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (player.isActive)
                      CustomPaint(
                        size: const Size(72, 72),
                        painter: _ActiveTurnGlowPainter(current),
                      ),
                    CustomPaint(
                      size: const Size(70, 70),
                      painter: _CircleTimerPainter(current),
                    ),
                  ],
                );
              },
            ),
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
    final status = player.avatarStatus; // ğŸ”¥ bunu modelden al

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

    // ğŸ”¥ STACK Ä°LE WRAP
    return Stack(
      children: [
        ClipOval(child: image),

        // ğŸ”¥ PENDING BADGE
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
                Icons.schedule, // â³
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

  BoxDecoration _panelDecoration({required bool isVertical}) {
    final active = player.isActive;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(isVertical ? 20 : 24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: active
            ? const [Color(0xEE19392F), Color(0xEE0B201B)]
            : const [Color(0xE51A2B28), Color(0xE50C1918)],
      ),
      border: Border.all(
        color: active ? const Color(0xB8CDB27C) : const Color(0x667D8878),
        width: active ? 1.2 : 0.9,
      ),
      boxShadow: [
        const BoxShadow(
          color: Color(0x66000000),
          blurRadius: 9,
          offset: Offset(0, 3),
        ),
        if (active)
          const BoxShadow(
            color: Color(0x3355C29B),
            blurRadius: 11,
            spreadRadius: 0.4,
          ),
      ],
    );
  }
}

class _ActiveTurnGlowPainter extends CustomPainter {
  final double progress;
  _ActiveTurnGlowPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final wave = (sin((1 - progress) * 2 * pi) + 1) / 2;
    final baseRadius = size.width / 2 - 5;

    final outer = Paint()
      ..color = const Color(0x665BC7A1).withOpacity(0.20 + (wave * 0.16))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 + (wave * 1.4);

    final inner = Paint()
      ..color = const Color(0x99CBB47B).withOpacity(0.32 + (wave * 0.18))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawCircle(center, baseRadius, outer);
    canvas.drawCircle(center, baseRadius - 2.6, inner);
  }

  @override
  bool shouldRepaint(covariant _ActiveTurnGlowPainter oldDelegate) {
    return oldDelegate.progress != progress;
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
