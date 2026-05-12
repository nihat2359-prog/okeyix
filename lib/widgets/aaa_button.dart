import 'package:flutter/material.dart';

class DockActionButton extends StatefulWidget {
  final String text;
  final Widget icon;
  final VoidCallback? onTap;

  const DockActionButton({
    super.key,
    required this.text,
    required this.icon,
    this.onTap,
  });

  @override
  State<DockActionButton> createState() => _DockActionButtonState();
}

class _DockActionButtonState extends State<DockActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;

    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
      onTapCancel: disabled ? null : () => setState(() => _pressed = false),
      onTap: widget.onTap,

      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 100),

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(3),

          /// 🔥 GOLD FRAME
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFE7A8), Color(0xFFE7C66A), Color(0xFFB9932F)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: _pressed
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.9),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.7),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: const Color(0xFFE7C66A).withOpacity(0.25),
                      blurRadius: 14,
                    ),
                  ],
          ),

          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),

              /// 🔥 ANA YÜZEY
              gradient: LinearGradient(
                colors: _pressed
                    ? [const Color(0xFF0F2A20), const Color(0xFF1A4D39)]
                    : [const Color(0xFF1F5A43), const Color(0xFF0F2A20)],
              ),
            ),

            child: Stack(
              children: [
                /// 🔥 ÜST BEVEL (ince değil, geniş)
                if (!_pressed)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.18),
                              Colors.transparent,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                  ),

                /// 🔥 ALT GÖLGE (depth)
                if (!_pressed)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.5),
                              Colors.transparent,
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                        ),
                      ),
                    ),
                  ),

                /// 🔥 CONTENT
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.icon,
                      const SizedBox(width: 10),
                      Text(
                        widget.text,
                        style: const TextStyle(
                          color: Color(0xFFE7C66A),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
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
  }
}

enum AuthButtonType { apple, google, guest }

class AuthButton extends StatelessWidget {
  final Widget icon;
  final String text;
  final VoidCallback? onTap;
  final AuthButtonType type;
  final bool loading;

  const AuthButton({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
    required this.type,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    List<Color> bg;
    Color border;
    Color textColor;

    switch (type) {
      case AuthButtonType.apple:
        bg = [const Color(0xFF2A2D34), const Color(0xFF171A20)];
        border = Colors.white.withOpacity(0.18);
        textColor = Colors.white;
        break;

      case AuthButtonType.google:
        bg = [const Color(0xFFFFFFFF), const Color(0xFFF8FAFF)];
        border = const Color(0xFF4285F4).withOpacity(0.45);
        textColor = const Color(0xFF22304A);
        break;

      case AuthButtonType.guest:
        bg = [const Color(0xFF2B313A), const Color(0xFF1C212A)];
        border = const Color(0xFFE7C66A).withOpacity(0.35);
        textColor = const Color(0xFFE7ECF3);
        break;
    }

    return SizedBox(
      height: 58,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ButtonStyle(
          elevation: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) return 2.0;
            return 4.0;
          }),
          backgroundColor: MaterialStateProperty.all(Colors.transparent),
          shadowColor: MaterialStateProperty.all(Colors.black.withOpacity(0.35)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          overlayColor: MaterialStateProperty.all(
            Colors.white.withOpacity(0.12),
          ),
          padding: MaterialStateProperty.all(EdgeInsets.zero),
        ),

        child: Ink(
          decoration: BoxDecoration(
            // color: bg, // 🔥 ANA YÜZEY
            borderRadius: BorderRadius.circular(14),

            border: Border.all(color: border, width: 1),

            /// 🔥 DERİNLİK (çok önemli)
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: bg,
            ),
          ),

          child: Stack(
            children: [
              /// 🔥 ÜST IŞIK (çizgi değil, yüzey)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.12),
                          Colors.transparent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),

              /// 🔥 CONTENT
              Center(
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFE7C66A),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            icon,
                            const SizedBox(width: 10),
                            Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PremiumCoinButton extends StatefulWidget {
  const PremiumCoinButton({super.key});

  @override
  State<PremiumCoinButton> createState() => _PremiumCoinButtonState();
}

class _PremiumCoinButtonState extends State<PremiumCoinButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;

        final glow = 0.4 + (t * 0.6);
        final floatY = -2 + (t * 4); // yukarı aşağı
        final scale = 0.95 + (t * 0.1); // nefes efekti

        return Stack(
          alignment: Alignment.center,
          children: [
            /// 🔥 GLOW
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE7C66A).withOpacity(glow * 0.6),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),

            /// 🔥 BUTTON
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF3E3212), // çok koyu edge
                    Color(0xFF0F2A1E), // mid gold
                    Color(0xFF071A12), // highlight
                    Color(0xFFB8962E), // geri dönüş
                  ],
                  stops: [0.0, 0.35, 0.55, 1.0],
                ),
                border: Border.all(
                  color: Color(0xFFFFE9A0), // sıcak highlight
                  width: 2.2,
                ),
              ),

              child: Center(
                child: Transform.translate(
                  offset: Offset(0, floatY),
                  child: Transform.scale(
                    scale: scale,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        /// 💰 COIN
                        Image.asset("assets/images/lobby/store.png", width: 32),

                        /// ✨ SHIMMER (ince ışık sweep)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.25,
                              child: Transform.translate(
                                offset: Offset(20 * (t - 0.5), 0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Colors.white.withOpacity(0.8),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.3, 0.5, 0.7],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
