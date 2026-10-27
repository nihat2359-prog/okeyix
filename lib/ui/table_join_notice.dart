import 'dart:math' as math;
import 'package:flutter/material.dart';

class TableJoinNotice extends StatelessWidget {
  const TableJoinNotice({super.key, required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableWidth = media.size.width - media.viewPadding.horizontal;
    final width = math.min(240.0, availableWidth * .6);
    final title = names.length == 1 ? names.first : '${names.length} oyuncu';
    return Positioned(
      bottom: media.viewPadding.bottom + 8,
      left: media.viewPadding.left + (availableWidth - width) / 2,
      width: width,
      child: IgnorePointer(
        child: Semantics(
          liveRegion: true,
          label: '${names.join(', ')} masaya katıldı',
          excludeSemantics: true,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: media.disableAnimations ? Duration.zero : const Duration(milliseconds: 160),
            builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
            child: Container(
              key: const ValueKey('table-join-notice'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xF02A3039), Color(0xF010151D)],
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0x668F8062), width: .8),
                boxShadow: const [BoxShadow(color: Color(0x44000000),
                  blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0x20E4C98D),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.person_add_alt_1_rounded,
                    color: Color(0xFFE4C98D), size: 17),
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFF0E9DA),
                        fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    const Text('Masaya katıldı', maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xFFB3BDC8), fontSize: 10)),
                  ],
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
