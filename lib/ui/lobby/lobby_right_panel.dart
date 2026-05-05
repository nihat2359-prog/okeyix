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
    final media = MediaQuery.of(context).size;
    final panelWidth = media.width * 0.46;
    final effectiveWidth = panelWidth.clamp(340.0, 660.0).toDouble();
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
                    width: effectiveWidth,
                    height: media.height - 16,
                    margin: const EdgeInsets.fromLTRB(0, 8, 10, 8),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),

                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: const Color(0xFF0F2F2A).withOpacity(0.90),
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

                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Spacer(),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: onClose,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0x1FFFFFFF),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0x66D4B46A),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFFE6D5A6),
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: panelContent),
                      ],
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
