import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'lobby_metal_surface.dart';

/// Presentation only: league rules and table creation stay with the caller.
class CreateTableScene extends StatefulWidget {
  final String leagueName;
  final List<int> stakes;
  final int selectedIndex, turnSeconds;
  final bool spectator, chat, canCreate;
  final String Function(int) formatStake;
  final ValueChanged<int> onStake, onSpeed;
  final VoidCallback onSpectator, onChat, onCreate, onClose;
  const CreateTableScene({
    super.key,
    required this.leagueName,
    required this.stakes,
    required this.selectedIndex,
    required this.turnSeconds,
    required this.spectator,
    required this.chat,
    required this.canCreate,
    required this.formatStake,
    required this.onStake,
    required this.onSpeed,
    required this.onSpectator,
    required this.onChat,
    required this.onCreate,
    required this.onClose,
  });
  @override
  State<CreateTableScene> createState() => _CreateTableSceneState();
}

class _CreateTableSceneState extends State<CreateTableScene> {
  static const gold = Color(0xFFE8CC8D);
  Widget _choice(
    String key,
    String label,
    IconData icon,
    bool active,
    VoidCallback action,
  ) => Expanded(
    child: Semantics(
      selected: active,
      child: InkWell(
        key: ValueKey(key),
        onTap: action,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active ? gold : const Color(0xFF7D9B8C),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? const Color(0xFFF2E7CD)
                            : const Color(0xFF9BAFA3),
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  active ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 11,
                  color: active ? gold : const Color(0xFF668174),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _chips() => LayoutBuilder(
    builder: (context, bounds) {
      final count = widget.stakes.length;
      if (count == 0) return const SizedBox.shrink();
      final gap = bounds.maxWidth < 500 ? 4.0 : 8.0;
      final width = math.max(
        1.0,
        (bounds.maxWidth - gap * (count - 1)) / count,
      );
      final diameter = math
          .min(width, math.max(1.0, bounds.maxHeight - 6))
          .clamp(1.0, 112.0);
      double tokenDiameter(int index) =>
          diameter * (count == 1 ? 1 : .72 + .28 * index / (count - 1));
      return Row(
        children: [
          for (var index = 0; index < count; index++) ...[
            if (index > 0) SizedBox(width: gap),
            Expanded(
              child: Semantics(
                selected: index == widget.selectedIndex,
                button: true,
                label: '${widget.stakes[index]} coin',
                child: InkWell(
                  key: ValueKey('stake-$index'),
                  onTap: () => widget.onStake(index),
                  borderRadius: BorderRadius.circular(70),
                  child: Center(
                    child: SizedBox(
                      width: tokenDiameter(index),
                      height: tokenDiameter(index),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _EntryToken(index == widget.selectedIndex),
                          child: Center(
                            child: FractionallySizedBox(
                              widthFactor: .68,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  widget.formatStake(widget.stakes[index]),
                                  style: TextStyle(
                                    color: index == widget.selectedIndex
                                        ? const Color(0xFF3F2A0C)
                                        : gold,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: LayoutBuilder(
      builder: (context, bounds) => Center(
        child: SizedBox(
          width: math.min(bounds.maxWidth, 940),
          height: math.min(bounds.maxHeight, 430),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: LobbyMetalSurface(
              radius: 22,
              surfaceOpacity: 2.4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  children: [
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          const SizedBox(width: 44),
                          const Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'MASANI KUR',
                                style: TextStyle(
                                  color: gold,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('create-close'),
                            tooltip: 'Kapat',
                            onPressed: widget.onClose,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFFBBCABB),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 20,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.leagueName,
                          style: const TextStyle(
                            color: Color(0xFFBECEBA),
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: _chips()),
                    SizedBox(
                      height: 22,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'GİRİŞ  ',
                              style: TextStyle(
                                color: Color(0xFF9EB5A1),
                                fontSize: 10,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              widget.formatStake(
                                widget.stakes[widget.selectedIndex],
                              ),
                              key: const ValueKey('preview-stake'),
                              style: const TextStyle(
                                color: gold,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              '  ·  ',
                              style: TextStyle(color: Color(0xFF778C76)),
                            ),
                            Text(
                              '2 OYUNCU · ${widget.turnSeconds} SN',
                              style: const TextStyle(
                                color: Color(0xFFB4C5B2),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: Row(
                        children: [
                          _choice(
                            'speed-fast',
                            'Hızlı · 15 sn',
                            Icons.bolt_rounded,
                            widget.turnSeconds == 15,
                            () => widget.onSpeed(15),
                          ),
                          _choice(
                            'speed-normal',
                            'Normal · 20 sn',
                            Icons.hourglass_bottom_rounded,
                            widget.turnSeconds == 20,
                            () => widget.onSpeed(20),
                          ),
                          const SizedBox(
                            height: 18,
                            child: VerticalDivider(
                              width: 14,
                              color: Color(0xFF4F6650),
                            ),
                          ),
                          _choice(
                            'setting-spectator',
                            'Seyirci',
                            Icons.visibility_outlined,
                            widget.spectator,
                            widget.onSpectator,
                          ),
                          _choice(
                            'setting-chat',
                            'Sohbet',
                            Icons.chat_bubble_outline_rounded,
                            widget.chat,
                            widget.onChat,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 46,
                      width: math.min(300, bounds.maxWidth * .65),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          gradient: widget.canCreate
                              ? const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFF5DEAB),
                                    Color(0xFFD5B268),
                                    Color(0xFFBD9140),
                                  ],
                                )
                              : null,
                          color: widget.canCreate
                              ? null
                              : const Color(0xFF415047),
                          border: Border.all(
                            color: widget.canCreate
                                ? const Color(0xFFF0D79B)
                                : const Color(0xFF5A6B5B),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              offset: Offset(0, 3),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: TextButton(
                          key: const ValueKey('create-confirm'),
                          onPressed: widget.canCreate ? widget.onCreate : null,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF35280F),
                            disabledForegroundColor: const Color(0xFFB6C1B2),
                            shape: const StadiumBorder(),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.canCreate
                                  ? 'MASAYI OLUŞTUR'
                                  : 'YETERSİZ BAKİYE',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                              ),
                            ),
                          ),
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
    ),
  );
}

/// Bevel, edge thickness and directional highlights; no animated glow.
class _EntryToken extends CustomPainter {
  final bool selected;
  const _EntryToken(this.selected);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 3);
    final r = size.width * .44;
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, r * .95),
        width: r * 1.8,
        height: r * .25,
      ),
      Paint()..color = const Color(0x55000000),
    );
    canvas.drawCircle(
      center + const Offset(0, 5),
      r,
      Paint()
        ..color = selected ? const Color(0xFF805424) : const Color(0xFF10161E),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3DFAD), Color(0xFFB4863E), Color(0xFF745020)],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    final stripe = Paint()
      ..color = selected ? const Color(0xFFFFE8B8) : const Color(0xFF88A28A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .1;
    for (var i = 0; i < 10; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * .9),
        i * math.pi / 5,
        .15,
        false,
        stripe,
      );
    }
    final face = Rect.fromCircle(center: center, radius: r * .77);
    canvas.drawCircle(
      center,
      r * .77,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? const [Color(0xFFFFE7AD), Color(0xFFD6AD58)]
              : const [Color(0xFF303944), Color(0xFF111A24)],
        ).createShader(face),
    );
    canvas.drawCircle(
      center,
      r * .72,
      Paint()
        ..color = selected ? const Color(0xFFB28A45) : const Color(0xFF678166)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r * .98),
      math.pi * 1.05,
      math.pi * .65,
      false,
      Paint()
        ..color = const Color(0xDDFFF0CB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _EntryToken oldDelegate) =>
      oldDelegate.selected != selected;
}
