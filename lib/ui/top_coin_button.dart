import 'package:flutter/material.dart';

class TopCoinButton extends StatelessWidget {
  final VoidCallback onTap;

  const TopCoinButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [Color(0xFFD4AF37), Color(0xFFFFE08A)],
          ),
          boxShadow: const [BoxShadow(color: Color(0x33D4AF37), blurRadius: 8)],
        ),
        child: Row(
          children: const [
            Icon(Icons.add, size: 16, color: Colors.black),
            SizedBox(width: 6),
            Text(
              "Coin Al",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
