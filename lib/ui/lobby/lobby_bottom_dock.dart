import 'dart:ui';

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
    final double systemBottomInset = MediaQuery.of(context).padding.bottom;
    final double bottomGap = systemBottomInset > 0 ? 2 : 8;

    return SafeArea(
      minimum: EdgeInsets.only(bottom: bottomGap),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 96,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double sidePadding = 12;
              const double centerReserve = 112;
              final double innerWidth = constraints.maxWidth - (sidePadding * 2);
              final double sideWidth = ((innerWidth - centerReserve) / 2).clamp(
                56.0,
                innerWidth / 2,
              );

              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          height: 74,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xD1151D1A), Color(0xE00D1210)],
                            ),
                            border: Border.all(
                              color: const Color(0x66D9B97A),
                              width: 1.1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: sidePadding,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: sideWidth,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: left,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  width: sideWidth,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerRight,
                                      child: right,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -4,
                    child: center,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
