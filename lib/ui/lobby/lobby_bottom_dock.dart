import 'package:flutter/material.dart';

class LobbyBottomDock extends StatelessWidget {
  final Widget left;
  final Widget center;
  final Widget right;

  const LobbyBottomDock({
    super.key,
    required this.left,
    required this.center,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 70,
        width: double.infinity,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Color(0x22FFFFFF), // istediğin renk
              width: 1,
            ),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            /// LEFT
            Positioned(left: 16, child: left),

            /// CENTER
            center,

            /// RIGHT
            Positioned(right: 16, child: right),
          ],
        ),
      ),
    );
  }
}
