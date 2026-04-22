import 'package:flutter/material.dart';

class GiftExplosionWidget extends StatefulWidget {
  final String senderName;
  final String emoji;
  final String giftName;
  final VoidCallback onClose;
  final VoidCallback? onTapUser;
  const GiftExplosionWidget({
    super.key,
    required this.senderName,
    required this.emoji,
    required this.giftName,
    required this.onClose,
    this.onTapUser,
  });

  @override
  State<GiftExplosionWidget> createState() => _GiftExplosionWidgetState();
}

class _GiftExplosionWidgetState extends State<GiftExplosionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _c.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value.clamp(0.0, 1.0);
        final t = Curves.easeOutBack.transform(v).clamp(0.0, 1.0);

        return Transform.translate(
          offset: Offset(120 * (1 - t), 0),
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Stack(
              children: [
                // 💥 SOFT GLOW (DAHA PREMIUM)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Transform.scale(
                      scale: 1.1 + (v * 0.8),
                      child: Opacity(
                        opacity: (1 - v).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.amber.withOpacity(0.5),
                                Colors.orange.withOpacity(0.25),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 🎁 GLASS CARD
                Container(
                  width: 130,
                  height: 130,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),

                    // 🔥 GLASS EFFECT
                    color: Colors.black.withOpacity(0.55),

                    border: Border.all(
                      color: Colors.amber.withOpacity(0.35),
                      width: 1,
                    ),

                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.15),
                        blurRadius: 16,
                      ),
                    ],
                  ),

                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ❌ CLOSE
                      Align(
                        alignment: Alignment.topRight,
                        child: GestureDetector(
                          onTap: widget.onClose,
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ),

                      const SizedBox(height: 4),

                      // 🔥 EMOJI (BÜYÜTÜLDÜ)
                      Text(widget.emoji, style: const TextStyle(fontSize: 36)),

                      const SizedBox(height: 8),

                      // 👤 USER (AAA UX)
                      InkWell(
                        onTap: widget.onTapUser,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.senderName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(width: 4),

                              // 🔥 PROFİL İKONU
                              Icon(
                                Icons.person_outline,
                                size: 14,
                                color: Colors.amber.withOpacity(0.9),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
