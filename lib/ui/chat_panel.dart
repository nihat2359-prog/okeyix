import 'dart:ui';
import 'package:flutter/material.dart';

class ChatPanel extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;

  const ChatPanel({super.key, required this.isOpen, required this.onClose});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final List<String> messages = [];
  final TextEditingController controller = TextEditingController();

  void sendMessage(String text) {
    if (text.trim().isEmpty) return;

    setState(() {
      //messages.add(text);
    });

    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      right: widget.isOpen ? 0 : -380,
      top: 0,
      bottom: 0,
      width: 380,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xCC0F141A),
              border: Border(left: BorderSide(color: Color(0x22FFFFFF))),
            ),
            child: Column(
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Chat",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Message container
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x22FFFFFF)),
                      color: const Color(0x221A222A),
                    ),
                    child: ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (_, index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: const Color(0xFF1A222A),
                          ),
                          child: Text(
                            messages[index],
                            style: const TextStyle(color: Colors.white),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Quick messages
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _quick("Seri oynayalım"),
                    _quick("Tebrik ederim"),
                    _quick("Teşekkür ederim"),
                  ],
                ),

                const SizedBox(height: 12),

                // Input row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Mesaj yaz...",
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF1A222A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => sendMessage(controller.text),
                      child: Container(
                        height: 44,
                        width: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFFD4AF37), Color(0xFFFFE08A)],
                          ),
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.black,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quick(String text) {
    return GestureDetector(
      onTap: () => sendMessage(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x22FFFFFF)),
          color: const Color(0x331A222A),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
    );
  }
}
