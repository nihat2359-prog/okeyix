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
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
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
    Color bg;
    Color border;
    Color textColor;

    switch (type) {
      case AuthButtonType.apple:
        bg = const Color(0xFF0A0A0A);
        border = Colors.white.withOpacity(0.12);
        textColor = Colors.white;
        break;

      case AuthButtonType.google:
        bg = const Color(0xFF0F2A20);
        border = const Color(0xFFE7C66A).withOpacity(0.5);
        textColor = const Color(0xFFE7C66A);
        break;

      case AuthButtonType.guest:
        bg = const Color(0xFF0F2A20);
        border = const Color(0xFFE7C66A).withOpacity(0.35);
        textColor = const Color(0xFFE7C66A);
        break;
    }

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ButtonStyle(
          elevation: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) return 2;
            return 6;
          }),
          backgroundColor: MaterialStateProperty.all(Colors.transparent),
          shadowColor: MaterialStateProperty.all(Colors.black.withOpacity(0.6)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          overlayColor: MaterialStateProperty.all(
            Colors.white.withOpacity(0.04),
          ),
          padding: MaterialStateProperty.all(EdgeInsets.zero),
        ),

        child: Ink(
          decoration: BoxDecoration(
            color: bg, // 🔥 ANA YÜZEY
            borderRadius: BorderRadius.circular(10),

            border: Border.all(color: border, width: 1),

            /// 🔥 DERİNLİK (çok önemli)
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),

          child: Stack(
            children: [
              /// 🔥 ÜST IŞIK (çizgi değil, yüzey)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.06),
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
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          icon,
                          const SizedBox(width: 10),
                          Text(
                            text,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
