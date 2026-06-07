import 'package:flutter/material.dart';

class LobbyRightPanel extends StatelessWidget {
  final bool open;
  final VoidCallback onClose;

  final Widget panelContent;
  final double widthFactor;
  final double minWidth;
  final double maxWidth;

  const LobbyRightPanel({
    super.key,
    required this.open,
    required this.onClose,
    required this.panelContent,
    this.widthFactor = 0.46,
    this.minWidth = 340,
    this.maxWidth = 660,
  });

  @override
  Widget build(BuildContext context) {
    if (!open) {
      return const SizedBox();
    }
    final mq = MediaQuery.of(context);
    final media = mq.size;
    final keyboardInset = mq.viewInsets.bottom;
    final panelWidth = media.width * widthFactor;
    final effectiveWidth = panelWidth.clamp(minWidth, maxWidth).toDouble();
    final effectiveHeight = (media.height - 16 - keyboardInset).clamp(
      260.0,
      media.height - 16,
    );
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
          AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: Align(
              alignment: Alignment.centerRight,
              child: IgnorePointer(
                ignoring: !open,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  offset: open ? Offset.zero : const Offset(1.2, 0),
                  child: SafeArea(
                    child: Container(
                      width: effectiveWidth,
                      height: effectiveHeight.toDouble(),
                      margin: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        color: const Color(0xFF12171D).withOpacity(0.84),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xDD1F252D), Color(0xDD12161C)],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x8A000000),
                            blurRadius: 24,
                            offset: Offset(-3, 8),
                          ),
                        ],
                      ),
                      child: Column(children: [Expanded(child: panelContent)]),
                    ),
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
