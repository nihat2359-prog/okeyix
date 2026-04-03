import 'package:flutter/material.dart';

class LobbyRightPanel extends StatelessWidget {
  final bool open;
  final VoidCallback onClose;

  final Widget panelContent;

  const LobbyRightPanel({
    super.key,
    required this.open,
    required this.onClose,
    required this.panelContent,
  });

  @override
  Widget build(BuildContext context) {
    if (!open) {
      return const SizedBox();
    }
    return Positioned.fill(
      child: Stack(
        children: [
          /// BACKDROP
          IgnorePointer(
            ignoring: !open,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: open ? 1 : 0,
              child: GestureDetector(
                onTap: onClose,
                child: Container(color: const Color(0x7A000000)),
              ),
            ),
          ),

          /// PANEL
          Align(
            alignment: Alignment.centerRight,
            child: IgnorePointer(
              ignoring: !open,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                offset: open ? Offset.zero : const Offset(1.2, 0),

                child: SafeArea(
                  child: Container(
                    width: 660,
                    margin: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                    padding: const EdgeInsets.all(14),

                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),

                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xEE13291F), Color(0xEE0C1712)],
                      ),

                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8A000000),
                          blurRadius: 24,
                          offset: Offset(-3, 8),
                        ),
                      ],
                    ),

                    child: panelContent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
