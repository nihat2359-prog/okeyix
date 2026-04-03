import 'package:flutter/material.dart';

class QuickChatMenu extends StatelessWidget {
  final Function(String) onSelect;

  const QuickChatMenu({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final messages = [
      "Tebrikler",
      "Hızlı oyna",
      "İyi hamle",
      "Bekliyorum",
      "Teşekkürler",
      "__CHAT__",
    ];

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: messages.map((text) {
          final isChat = text == "__CHAT__";

          return GestureDetector(
            onTap: () => onSelect(text),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xEE1A222A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x44FFFFFF)),
              ),
              child: Text(
                isChat ? "Sohbet Aç" : text,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
