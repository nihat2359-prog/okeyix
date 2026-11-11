import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Palette and shared building blocks for the 3D lobby.
abstract final class L3d {
  static const night = Color(0xFF060914);
  static const navy = Color(0xFF0C1430);
  static const cyan = Color(0xFF4DE3FF);
  static const amber = Color(0xFFFFB547);
  static const green = Color(0xFF3BF0A0);
  static const coral = Color(0xFFFF6B5A);
  static const white = Color(0xFFF5F8FF);
  static const soft = Color(0xFFAAB6D3);

  static const shadow = [Shadow(color: Color(0xCC000000), offset: Offset(0, 1.5), blurRadius: 4)];

  /// Turkish-aware upper case (i → İ, ı → I); String.toUpperCase is not.
  static String upper(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  /// Camera with perspective; [depth] > 0 brings content toward the viewer.
  static Matrix4 camera({double rotX = 0, double rotY = 0, double depth = 0, double fov = .0012}) =>
      Matrix4.identity()
        ..setEntry(3, 2, fov)
        ..rotateX(rotX)
        ..rotateY(rotY)
        ..multiply(Matrix4.translationValues(0, 0, -depth));

  static const desaturate = ColorFilter.matrix(<double>[
    0.33, 0.50, 0.17, 0, -10, //
    0.33, 0.50, 0.17, 0, -10, //
    0.33, 0.50, 0.17, 0, -4, //
    0, 0, 0, 1, 0,
  ]);
}

/// League artwork and accent colour.
class L3dLeagueArt {
  final String background, trophy;
  final Color tint;
  const L3dLeagueArt(this.background, this.trophy, this.tint);

  static const _d = 'assets/images/lobby/leagues';
  static const ordered = [
    L3dLeagueArt('$_d/acemiler_arka_plan.png', '$_d/acemiler_kupa.png', Color(0xFFFF9A52)),
    L3dLeagueArt('$_d/ciraklar_arka_plan.png', '$_d/ciraklar_kupa.png', Color(0xFF6CC8FF)),
    L3dLeagueArt('$_d/kalfalar_arka_plan.png', '$_d/kalfalar_kupa.png', Color(0xFFFFD34D)),
    L3dLeagueArt('$_d/ustalar_arka_plan.png', '$_d/ustalar_kupa.png', Color(0xFFC08CFF)),
    L3dLeagueArt('$_d/sampiyonlar_arka_plan.png', '$_d/sampiyonlar_kupa.png', Color(0xFF3BF0A0)),
  ];

  /// Matches by name first so a reordered league table keeps its artwork.
  static L3dLeagueArt of(Map<String, dynamic>? league, int index) {
    final name = (league?['name']?.toString() ?? '').toLowerCase();
    const keys = [
      ['acemi'],
      ['çırak', 'cirak', 'çirak'],
      ['kalfa'],
      ['usta'],
      ['şampiyon', 'sampiyon'],
    ];
    for (var i = 0; i < keys.length; i++) {
      if (keys[i].any(name.contains)) return ordered[i];
    }
    return ordered[index.clamp(0, ordered.length - 1)];
  }
}

/// Frosted glass panel with a thin light rim.
class L3dGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final bool blur;
  const L3dGlass({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.blur = true,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (tint ?? Colors.white).withValues(alpha: .16),
            const Color(0x1A0A1024),
            const Color(0x660A1024),
          ],
          stops: const [0, .45, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .16), width: 1),
      ),
      child: child,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: blur
            ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14), child: body)
            : body,
      ),
    );
  }
}

/// Extruded 3D slab: coloured side face below a glossy top face. The top face
/// sinks onto the side face while pressed.
class L3dSlab extends StatefulWidget {
  final Widget child;
  final Color color;
  final double radius, depth;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  const L3dSlab({
    super.key,
    required this.child,
    required this.color,
    required this.onTap,
    this.radius = 14,
    this.depth = 5,
    this.semanticLabel,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<L3dSlab> createState() => _L3dSlabState();
}

class _L3dSlabState extends State<L3dSlab> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final base = enabled ? widget.color : const Color(0xFF59607A);
    final hsl = HSLColor.fromColor(base);
    final top = hsl.withLightness((hsl.lightness + .14).clamp(0, 1)).toColor();
    final side = hsl.withLightness((hsl.lightness - .22).clamp(0, 1)).toColor();
    final sink = _down ? widget.depth - 1 : 0.0;
    final r = BorderRadius.circular(widget.radius);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.depth),
          child: Stack(clipBehavior: Clip.none, fit: StackFit.passthrough, children: [
            // Side face + contact shadow.
            Positioned.fill(
              top: widget.depth,
              bottom: -widget.depth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: r,
                  color: side,
                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 5))],
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              transform: Matrix4.translationValues(0, sink, 0),
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [top, base],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .35), width: 1),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: r,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
                ),
              ),
              child: widget.child,
            ),
          ]),
        ),
      ),
    );
  }
}

/// Square 3D icon tile used in the dock and HUD.
class L3dTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final double size;
  final int badge;
  final bool showLabel;
  const L3dTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.size = 38,
    this.badge = 0,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        L3dSlab(
          color: color,
          onTap: onTap,
          radius: size * .3,
          depth: size * .11,
          semanticLabel: label,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * .58, color: Colors.white, shadows: L3d.shadow),
          ),
        ),
        if (badge > 0) Positioned(right: -6, top: -6, child: L3dBadge(count: badge)),
      ]),
      if (showLabel) ...[
        const SizedBox(height: 2),
        SizedBox(
          height: 11,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                style: const TextStyle(color: L3d.soft, fontSize: 9.5, fontWeight: FontWeight.w800, shadows: L3d.shadow)),
          ),
        ),
      ],
    ]),
  );
}

class L3dBadge extends StatelessWidget {
  final int count;
  const L3dBadge({super.key, required this.count});
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFF7A6B), Color(0xFFE02F3E)]),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white, width: 1.4),
      boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 4, offset: Offset(0, 2))],
    ),
    child: Text(count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, height: 1)),
  );
}

/// Single-line label that shrinks rather than overflows.
class L3dFit extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Alignment alignment;
  const L3dFit(this.text, {super.key, required this.style, this.alignment = Alignment.center});
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: alignment,
    child: Text(text, maxLines: 1, softWrap: false, style: style),
  );
}

/// Shares the lobby camera position (carousel page) with parallax layers.
class L3dCameraScope extends StatefulWidget {
  final Widget child;
  const L3dCameraScope({super.key, required this.child});

  static ValueNotifier<double>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_L3dCamera>()?.notifier;

  @override
  State<L3dCameraScope> createState() => _L3dCameraScopeState();
}

class _L3dCameraScopeState extends State<L3dCameraScope> {
  final _camera = ValueNotifier<double>(0);
  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _L3dCamera(notifier: _camera, child: widget.child);
}

class _L3dCamera extends InheritedNotifier<ValueNotifier<double>> {
  const _L3dCamera({required super.notifier, required super.child});
}
