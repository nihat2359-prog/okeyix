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
          height: 78,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double sidePadding = 12;
              const double centerReserve = 88;
              final double innerWidth =
                  constraints.maxWidth - (sidePadding * 2);
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
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          height: 62,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xE5272726),
                                Color(0xED111719),
                                Color(0xF2080C10),
                              ],
                            ),
                            border: Border.all(
                              color: const Color(0x667F7459),
                              width: 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x3A000000),
                                blurRadius: 12,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 1,
                                left: 20,
                                right: 20,
                                child: Container(
                                  height: 1,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Color(0x88FFE4A0),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(top: -1, child: center),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
