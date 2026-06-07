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
          height: 88,
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
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          height: 66,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x2A1A2521), Color(0x30101513)],
                            ),
                            border: Border.all(
                              color: const Color(0x33FFEBC6),
                              width: 1.0,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1AFFD76A),
                                blurRadius: 10,
                                spreadRadius: 0,
                              ),
                              BoxShadow(
                                color: Color(0x59000000),
                                blurRadius: 12,
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
                    top: -1,
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
