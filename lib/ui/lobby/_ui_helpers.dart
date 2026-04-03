import 'package:flutter/material.dart';

Widget lobbyBgOrb(Color color, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, Color(0x00000000)]),
    ),
  );
}

Widget lobbyGlassIcon({
  required IconData icon,
  String? badgeValue,
  required VoidCallback onTap,
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: const Color(0x22111111),
            border: Border.all(color: const Color(0x3355B98E)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),

      if (badgeValue != null)
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badgeValue,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget lobbyGlassIconGold({
  required IconData icon,
  String? badgeValue,
  required VoidCallback onTap,
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),

            /// GOLD GRADIENT
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFE27A), Color(0xFFD6A73C), Color(0xFFB8860B)],
            ),

            /// GOLD BORDER
            border: Border.all(color: const Color(0xFFFFF1A8), width: 1.2),

            /// SHADOW
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: Color(0x55FFD76A),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),

          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),

              /// INNER GOLD LIGHT
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                radius: 1.2,
                colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            child: Icon(icon, size: 22, color: const Color(0xFF3A2A00)),
          ),
        ),
      ),

      /// BADGE
      if (badgeValue != null)
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x88000000), blurRadius: 4),
              ],
            ),
            child: Text(
              badgeValue,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget lobbyStoreIcon({String? badgeValue, required VoidCallback onTap}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: const Color(0x22111111),
            border: Border.all(color: const Color(0x3355B98E)),
          ),

          /// EMOJI ICON
          child: Center(
            child: Image.asset(
              "assets/images/lobby/store.png",
              width: 24,
              height: 24,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),

      if (badgeValue != null)
        Positioned(
          right: -3,
          top: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x88000000), blurRadius: 4),
              ],
            ),
            child: Text(
              badgeValue,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget lobbyHeroButton({
  required String label,
  required IconData icon,
  required Color colorA,
  required Color colorB,
  required Color iconColor,
  required VoidCallback onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(colors: [colorA, colorB]),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget lobbySideMenuButton({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  bool danger = false,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: danger ? const Color(0x33FF4A4A) : const Color(0x22111111),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

Widget lobbyAssetIcon({
  required String asset,
  String? badgeValue,
  required VoidCallback onTap,
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Image.asset(
              asset,
              width: 36,
              height: 36,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),

      if (badgeValue != null)
        Positioned(
          right: -3,
          top: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x88000000), blurRadius: 4),
              ],
            ),
            child: Text(
              badgeValue,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget lobbyAssetIconCreateTable({
  required String asset,
  String? badgeValue,
  required VoidCallback onTap,
}) {
  return Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.center,
    children: [
      /// GLOW
      Positioned.fill(
        child: IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                radius: 0.9,
                colors: [Color(0x44E7B95A), Color(0x00E7B95A)],
              ),
            ),
          ),
        ),
      ),

      /// BUTTON
      InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: 1,
          child: SizedBox(
            width: 130,
            height: 56,
            child: Center(
              child: Image.asset(
                asset,
                width: 128,
                height: 56,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),

      /// BADGE
      if (badgeValue != null)
        Positioned(
          right: -3,
          top: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x88000000), blurRadius: 4),
              ],
            ),
            child: Text(
              badgeValue,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget lobbyDockIcon({
  required String asset,
  String? badgeValue,
  required VoidCallback onTap,
}) {
  return Stack(
    clipBehavior: Clip.none,
    children: [
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,

          child: Image.asset(
            asset,
            width: 32,
            height: 32,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),

      if (badgeValue != null)
        Positioned(
          right: -3,
          top: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(color: Color(0x88000000), blurRadius: 4),
              ],
            ),
            child: Text(
              badgeValue,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
    ],
  );
}
