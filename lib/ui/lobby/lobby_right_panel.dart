import 'dart:math' as math;
import 'package:flutter/material.dart';

class LobbyRightPanel extends StatelessWidget {
  final bool open;
  final VoidCallback onClose;
  final Widget panelContent;
  final double widthFactor, minWidth, maxWidth;
  const LobbyRightPanel({
    super.key,
    required this.open,
    required this.onClose,
    required this.panelContent,
    this.widthFactor = .46,
    this.minWidth = 280,
    this.maxWidth = 350,
  });

  void _close() {
    FocusManager.instance.primaryFocus?.unfocus();
    onClose();
  }

  @override
  Widget build(BuildContext context) {
    if (!open) return const SizedBox.shrink();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('lobby-social-outside'),
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.expand(),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, limits) {
                final width = math.min(
                  limits.maxWidth - 16,
                  (limits.maxWidth * widthFactor).clamp(minWidth, maxWidth),
                );
                final height = math.min(
                  440.0,
                  math.max(0.0, limits.maxHeight - keyboard - 16),
                );
                return Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    key: const ValueKey('lobby-social-panel'),
                    width: width,
                    height: height,
                    margin: const EdgeInsets.only(top: 8, right: 8),
                    padding: EdgeInsets.all(height < 150 ? 4 : 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xF01D252E), Color(0xED0B121B)],
                      ),
                      border: Border.all(
                        color: const Color(0x55C8AC75),
                        width: .7,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: panelContent,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
