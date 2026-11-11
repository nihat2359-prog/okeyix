import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/ui/bot_badge.dart';
import 'package:okeyix/ui/lobby/lobby_avatar.dart';
import 'l3d_engine.dart';
import 'l3d_theme.dart';

const _spacing = 3.3; // world units between tables
const _pitch = .80; // camera downward angle (rad)

// ───────────────────────────── models ─────────────────────────────

class _TableModel {
  final Map<String, dynamic> data;
  final int seats;
  final List<Map<String, dynamic>?> players;
  final bool canJoin, canWatch, playing, starting, ghost;
  _TableModel(this.data, {required bool canSpectateAll, this.ghost = false})
      : seats = ((data['max_players'] as num?)?.toInt() ?? 2) >= 4 ? 4 : 2,
        players = _players(data),
        playing = data['status'] == 'playing',
        starting = data['status'] == 'start',
        canJoin = !ghost && _players(data).any((p) => p == null) && data['status'] == 'waiting',
        canWatch = !ghost &&
            _players(data).every((p) => p != null) &&
            data['status'] == 'playing' &&
            data['is_fake'] != true &&
            data['spectators_enabled'] != false &&
            canSpectateAll;

  static List<Map<String, dynamic>?> _players(Map<String, dynamic> t) {
    final count = ((t['max_players'] as num?)?.toInt() ?? 2) >= 4 ? 4 : 2;
    final list = ((t['_players'] as List?) ?? const []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
    return List.generate(count, (s) {
      for (final p in list) {
        if (p['seat_index'] == s) return p;
      }
      return null;
    });
  }

  String get id => data['id'].toString();
  (String, Color) get status => ghost
      ? ('', L3d.soft)
      : starting
      ? ('BAŞLIYOR', L3d.amber)
      : playing
      ? ('OYUNDA', L3d.coral)
      : canJoin
      ? ('YER VAR', L3d.green)
      : ('DOLU', L3d.soft);
}

/// Seat positions relative to the table centre (x, z) and the direction the
/// chair faces (toward the table).
List<V3> _seatOffsets(int seats) => seats >= 4
    ? const [V3(0, 0, -1.02), V3(1.28, 0, 0), V3(0, 0, 1.02), V3(-1.28, 0, 0)]
    : const [V3(-1.28, 0, 0), V3(1.28, 0, 0)];

// ───────────────────────────── geometry ─────────────────────────────

const _walnut = Material3(Color(0xFF4A2E1C), gloss: .35, shininess: 40);
const _walnutDark = Material3(Color(0xFF2C1A10), gloss: .25, shininess: 30);
const _felt = Material3(Color(0xFF0F7A64), gloss: .04, shininess: 8);
const _feltGhost = Material3(Color(0xFF39445E), gloss: .05);
const _chrome = Material3(Color(0xFFA9B1C2), gloss: .9, shininess: 70);
const _tileMat = Material3(Color(0xFFF6F0DF), gloss: .45, shininess: 50);
const _rackMat = Material3(Color(0xFF7A4B26), gloss: .3, shininess: 30);
const _leather = Material3(Color(0xFF2A3355), gloss: .35, shininess: 30);
const _brass = Material3(Color(0xFFD3A75A), gloss: .9, shininess: 80);
const _bulb = Material3(Color(0xFFFFE6B0), emissive: 2.4, twoSided: true);
const _shadow = Material3(Color(0xFF000000), alpha: .5, twoSided: true, emissive: 0);
const _pips = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF222222), Color(0xFFFFB300)];

List<Obj3> _buildTable(V3 c, _TableModel t, Color accent, bool focused) {
  final objs = <Obj3>[];

  // Floor decals: contact shadow and status ring.
  final decal = Mesh3()..disc(c + const V3(0, .002, 0), 1.0, .72, _shadow);
  final ringColor = t.ghost ? L3d.soft : t.status.$2;
  final ring = Material3(ringColor, emissive: focused ? 1.6 : .9, alpha: focused ? .9 : .55, twoSided: true);
  for (var i = 0; i < 40; i++) {
    final a0 = i / 40 * math.pi * 2, a1 = (i + 1) / 40 * math.pi * 2;
    V3 p(double a, double r) => c + V3(math.cos(a) * r * 1.42, .004, math.sin(a) * r);
    decal.quad(p(a0, 1.0), p(a1, 1.0), p(a1, 1.06), p(a0, 1.06), ring);
  }
  for (final o in _seatOffsets(t.seats)) {
    decal.disc(c + o + const V3(0, .003, 0), .32, .32, _shadow);
  }
  objs.add(decal.build(c, layer: Layer3.decal));

  // Table: pedestal, slab, felt, chips, racks, tiles (bottom-up order).
  final m = Mesh3()
    ..cylinder(c, .46, .04, _chrome, seg: 22)
    ..cylinder(c + const V3(0, .04, 0), .11, .64, _chrome, seg: 14)
    ..prism(roundedRect(1.78, 1.2, .2), .68, .74, _walnutDark, origin: c, top: _walnut)
    ..prism(roundedRect(1.78, 1.2, .2), .74, .79, _walnut, origin: c, topInset: .02)
    ..prism(roundedRect(1.46, .9, .13), .79, .80, t.ghost ? _feltGhost : _felt, origin: c);
  if (!t.ghost) {
    const chipColors = [Color(0xFFD32F2F), Color(0xFF1565C0), Color(0xFFFFC107)];
    for (var i = 0; i < 3; i++) {
      m.cylinder(c + V3(.40 + i * .06, .80, .20 + (i.isEven ? .02 : -.03)), .05, .025 + i * .012,
          Material3(chipColors[i], gloss: .6, shininess: 50),
          top: Material3(Color.lerp(chipColors[i], Colors.white, .25)!, gloss: .6, shininess: 50), seg: 14);
    }
    // Racks along occupied edges, tiles standing on them facing the player.
    final edges = t.seats >= 4
        ? const [(V3(0, 0, -.36), 0.0), (V3(.62, 0, 0), math.pi / 2), (V3(0, 0, .36), math.pi), (V3(-.62, 0, 0), -math.pi / 2)]
        : const [(V3(-.62, 0, 0), -math.pi / 2), (V3(.62, 0, 0), math.pi / 2)];
    for (var e = 0; e < edges.length; e++) {
      final (off, rot) = edges[e];
      final rc = c + off + const V3(0, .825, 0);
      m.box(rc, const V3(.62, .05, .09), _rackMat, rotY: rot);
      for (var i = 0; i < 8; i++) {
        final local = V3(-.27 + i * .077, 0, .0);
        final tc = c + off + local.rotY(rot) + const V3(0, .885, 0);
        m.box(tc, const V3(.062, .075, .022), _tileMat, rotY: rot);
        // Coloured number pip on the tile's outward face.
        final out = const V3(0, 0, -1).rotY(rot);
        final side = const V3(1, 0, 0).rotY(rot);
        final f = tc + out * .0115;
        final pip = Material3(_pips[(i + e) % 4], emissive: .25);
        m.quad(f + side * -.014 + const V3(0, .004, 0), f + side * .014 + const V3(0, .004, 0),
            f + side * .014 + const V3(0, .03, 0), f + side * -.014 + const V3(0, .03, 0), pip, outward: out);
      }
    }
  }
  objs.add(m.build(c + const V3(0, .6, 0)));

  // Chairs, each its own object so they sort against the table.
  final offsets = _seatOffsets(t.seats);
  for (var s = 0; s < offsets.length; s++) {
    final pos = c + offsets[s];
    final facing = math.atan2(-offsets[s].x, -offsets[s].z);
    final occupied = t.players[s] != null;
    final seatMat = !t.ghost && !occupied && t.canJoin
        ? const Material3(Color(0xFF1F8F62), gloss: .4, shininess: 30, emissive: .35)
        : _leather;
    final back = V3(0, 0, -.22).rotY(facing);
    final ch = Mesh3()
      ..cylinder(pos, .19, .03, _chrome, seg: 16)
      ..cylinder(pos + const V3(0, .03, 0), .035, .34, _chrome, seg: 10)
      ..prism(roundedRect(.44, .42, .1), .37, .44, seatMat, origin: pos, rotY: facing)
      ..box(pos + back * .85 + const V3(0, .62, 0), const V3(.42, .36, .07), seatMat, rotY: facing);
    objs.add(ch.build(pos + const V3(0, .5, 0) + back * .3));
  }

  // Pendant lamp.
  final lamp = Mesh3()
    ..cylinder(c + const V3(0, 2.5, 0), .008, 2.5, _chrome, seg: 6)
    ..lathe(c + const V3(0, 2.18, 0), const [
      Offset(.30, 0),
      Offset(.27, .05),
      Offset(.15, .22),
      Offset(.05, .30),
      Offset(.0, .32),
    ], _brass, seg: 20)
    ..disc(c + const V3(0, 2.182, 0), .27, .27, _bulb, seg: 20);
  objs.add(lamp.build(c + const V3(0, 2.3, 0)));
  return objs;
}

Obj3 _buildFloor(double x0, double x1) {
  final m = Mesh3();
  const a = Material3(Color(0xFF161D38), gloss: .55, shininess: 60);
  const b = Material3(Color(0xFF111730), gloss: .55, shininess: 60);
  for (var x = x0.floor(); x < x1; x++) {
    for (var z = -10; z < 6; z++) {
      final mat = (x + z).isEven ? a : b;
      final p = V3(x.toDouble(), 0, z.toDouble());
      m.quad(p, p + const V3(1, 0, 0), p + const V3(1, 0, 1), p + const V3(0, 0, 1), mat, outward: V3.up);
    }
  }
  return m.build(V3((x0 + x1) / 2, 0, -2), layer: Layer3.floor);
}

// ───────────────────────────── widget ─────────────────────────────

/// The lobby as a real 3D lounge. Tables stand on the floor in a row; the
/// camera glides between them. Interaction lives in widgets anchored to
/// projected 3D points so hit-testing stays exact.
class L3dRoom extends StatefulWidget {
  final List<Map<String, dynamic>> tables;
  final bool loading, locked, canSpectateAll;
  final Map<String, dynamic>? lockedLeague;
  final String leagueName;
  final int userCoin, userRating;
  final Color accent;
  final Set<String> blockedUserIds;
  final Function(Map<String, dynamic>) onJoin, onSpectate, onUserTap;
  final VoidCallback onCreate, onStore;
  final Future<void> Function() onRefresh;

  /// Screen insets reserved for other UI (league wall on the left, dock below).
  final EdgeInsets viewInsets;

  const L3dRoom({
    super.key,
    required this.tables,
    required this.loading,
    required this.locked,
    required this.lockedLeague,
    required this.leagueName,
    required this.userCoin,
    required this.userRating,
    required this.accent,
    required this.blockedUserIds,
    required this.onJoin,
    required this.onSpectate,
    required this.onUserTap,
    required this.onCreate,
    required this.onStore,
    required this.onRefresh,
    required this.viewInsets,
    this.canSpectateAll = true,
  });

  @override
  State<L3dRoom> createState() => _L3dRoomState();
}

class _L3dRoomState extends State<L3dRoom> with SingleTickerProviderStateMixin {
  late final AnimationController _cam;
  int _focus = 0;
  List<_TableModel> _models = const [];
  Scene3? _scene;
  Object? _sceneKey;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy controller would first be built in dispose()
    // when the room never laid out.
    _cam = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _cam.dispose();
    super.dispose();
  }

  bool get _placeholder => widget.locked || widget.loading || widget.tables.isEmpty;

  void _rebuildScene() {
    final key = Object.hashAll([
      widget.accent,
      _placeholder,
      _focus,
      for (final t in widget.tables) Object.hash(t['id'], t['status'], t['max_players'], (t['_players'] as List?)?.length),
    ]);
    if (key == _sceneKey && _scene != null) return;
    _sceneKey = key;
    _models = _placeholder
        ? [_TableModel(const {'id': 'placeholder', 'max_players': 4, 'status': 'ghost'}, canSpectateAll: false, ghost: true)]
        : [for (final t in widget.tables) _TableModel(t, canSpectateAll: widget.canSpectateAll)];
    if (_focus >= _models.length) {
      _focus = _models.length - 1;
      // Never notify the camera listeners mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cam.value = _focus.toDouble();
      });
    }
    final objs = <Obj3>[_buildFloor(-7, _models.length * _spacing + 7)];
    final lights = <PointLight3>[];
    for (var i = 0; i < _models.length; i++) {
      final c = V3(i * _spacing, 0, 0);
      objs.addAll(_buildTable(c, _models[i], widget.accent, i == _focus));
      lights.add(PointLight3(c + const V3(0, 1.6, 0), const Color(0xFFFFD49A), _models[i].ghost ? .8 : 1.7, range: 1.5));
    }
    _scene = Scene3(
      objects: objs,
      dirLights: [
        DirLight(const V3(-.4, 1, .7), const Color(0xFFE8ECFF), .55),
        DirLight(const V3(.6, .35, -1), widget.accent, .55),
      ],
      pointLights: lights,
    );
  }

  void _focusOn(int i) {
    final target = i.clamp(0, _models.length - 1);
    setState(() => _focus = target);
    if (MediaQuery.disableAnimationsOf(context)) {
      _cam.value = target.toDouble();
    } else {
      _cam.animateTo(target.toDouble(), duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    _rebuildScene();
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final ins = widget.viewInsets;
      final area = Rect.fromLTRB(ins.left, ins.top, size.width - ins.right, size.height - ins.bottom);
      // Transient zero-size windows: skip 3D rather than divide by ~0.
      if (area.width < 60 || area.height < 60) return const SizedBox.shrink();
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _placeholder
            ? null
            : (d) => _cam.value = (_cam.value - d.delta.dx / (area.width * .55)).clamp(-.3, _models.length - .7),
        onHorizontalDragEnd: _placeholder
            ? null
            : (d) {
                final v = d.primaryVelocity ?? 0;
                final next = v.abs() > 300 ? (_cam.value - v.sign * .5).round() : _cam.value.round();
                _focusOn(next);
              },
        child: AnimatedBuilder(
          animation: _cam,
          builder: (context, _) => _frame(size, area),
        ),
      );
    });
  }

  Widget _frame(Size size, Rect area) {
    final camX = _cam.value * _spacing;
    // Frame the focused table (with chairs) to fill the free area.
    final fov = .9;
    final focal = size.height * .5 / math.tan(fov / 2);
    final dist = math.max(focal * 3.25 / (area.width * .96), focal * 2.55 / (area.height * .92));
    final target = V3(camX, .55, 0);
    final eye = target + V3(0, math.sin(_pitch), math.cos(_pitch)) * dist;
    final camera = Camera3(
      eye: eye,
      target: target,
      fovY: fov,
      principal: Offset(area.center.dx, area.top + area.height * .58),
    );
    final scene = _scene!;
    final kRef = camera.project(target, size)?.$2 ?? 1;

    final overlays = <Widget>[];
    for (var i = 0; i < _models.length; i++) {
      if ((i - _cam.value).abs() > 2.2) continue;
      overlays.addAll(_tableOverlay(i, camera, size, kRef));
    }

    return Stack(fit: StackFit.expand, children: [
      // Skyline beyond the terrace, slow parallax.
      Positioned(
        left: -size.width * .1 - _cam.value * 14,
        width: size.width * 1.25,
        top: 0,
        height: size.height * .62,
        child: Image.asset(
          'assets/images/lobby/lobby.png',
          fit: BoxFit.cover,
          alignment: const Alignment(0, .35),
          color: const Color(0xFF9AA6D6),
          colorBlendMode: BlendMode.modulate,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: size.height * .30,
        height: size.height * .40,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x000A0F22), Color(0xFF0A0F22)],
              stops: [0, .7],
            ),
          ),
        ),
      ),
      Positioned(top: size.height * .62, left: 0, right: 0, bottom: 0, child: const ColoredBox(color: Color(0xFF0A0F22))),
      RepaintBoundary(child: CustomPaint(painter: Scene3Painter(scene, camera))),
      // Lamp bloom.
      for (var i = 0; i < _models.length; i++)
        if ((i - _cam.value).abs() < 2.2) ..._bloom(i, camera, size),
      ...overlays,
      _header(area, size),
      if (_placeholder) _stateCard(area),
    ]);
  }

  List<Widget> _bloom(int i, Camera3 camera, Size size) {
    final p = camera.project(V3(i * _spacing, 2.18, 0), size);
    // Only bloom lamps actually in frame, not above the top edge.
    if (p == null || p.$1.dy < 0) return const [];
    final r = p.$2 * .9;
    return [
      Positioned(
        left: p.$1.dx - r,
        top: p.$1.dy - r * .6,
        width: r * 2,
        height: r * 1.6,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [const Color(0x66FFD49A), const Color(0x00FFD49A)]),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _tableOverlay(int i, Camera3 camera, Size size, double kRef) {
    final t = _models[i];
    final c = V3(i * _spacing, 0, 0);
    final centre = camera.project(c + const V3(0, .85, 0), size);
    if (centre == null) return const [];
    final s = (centre.$2 / kRef).clamp(.35, 1.6);
    final focused = i == _focus && (_cam.value - i).abs() < .08;

    // Hit area = projected bounds of the table top.
    final pts = [
      for (final (dx, dz) in const [(-.95, -.65), (.95, -.65), (.95, .65), (-.95, .65)])
        camera.project(c + V3(dx, .8, dz), size)?.$1,
      camera.project(c + const V3(0, 0, .6), size)?.$1,
    ].whereType<Offset>().toList();
    final out = <Widget>[];
    if (pts.isNotEmpty && !t.ghost) {
      var l = pts.first.dx, r = l, tp = pts.first.dy, b = tp;
      for (final p in pts) {
        l = math.min(l, p.dx);
        r = math.max(r, p.dx);
        tp = math.min(tp, p.dy);
        b = math.max(b, p.dy);
      }
      out.add(Positioned(
        left: l,
        top: tp,
        width: r - l,
        height: b - tp,
        child: Semantics(
          button: true,
          label: 'Masa ${i + 1}',
          child: GestureDetector(
            key: ValueKey('v2-table-${t.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: focused
                ? (t.canJoin ? () => widget.onJoin(t.data) : t.canWatch ? () => widget.onSpectate(t.data) : null)
                : () => _focusOn(i),
          ),
        ),
      ));
    }

    if (!t.ghost) {
      // Players and free seats float above their chairs.
      final offsets = _seatOffsets(t.seats);
      for (var sIdx = 0; sIdx < offsets.length; sIdx++) {
        final head = camera.project(c + offsets[sIdx] + const V3(0, .92, 0), size);
        if (head == null) continue;
        final hs = (head.$2 / kRef).clamp(.35, 1.6);
        final size0 = 40 * hs;
        final player = t.players[sIdx];
        out.add(Positioned(
          left: head.$1.dx - size0 / 2,
          top: head.$1.dy - size0 / 2,
          width: size0,
          height: size0 * 1.25,
          child: IgnorePointer(
            ignoring: !focused,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              child: _Seat(
                key: ValueKey('seat-${t.id}-$sIdx'),
                player: player,
                canJoin: t.canJoin,
                blocked: player != null &&
                    (player['blocked'] == true || widget.blockedUserIds.contains(player['user_id']?.toString())),
                onTap: player != null
                    ? () => widget.onUserTap(player)
                    : t.canJoin
                    ? () => widget.onJoin(t.data)
                    : null,
              ),
            ),
          ),
        ));
      }

      // Stake readout hovering over the felt.
      final hover = camera.project(c + const V3(0, .82, 0), size);
      if (hover != null) {
        final entry = (t.data['entry_coin'] as num?)?.toInt() ?? 0;
        final pot = (t.data['pot_amount'] as num?)?.toInt() ?? 0;
        final round = (t.data['round_count'] as num?)?.toInt() ?? 0;
        final (statusText, statusColor) = t.status;
        // Sized to the felt's projected width; content scales down to fit.
        final w = 150 * s;
        out.add(Positioned(
          left: hover.$1.dx - w / 2,
          top: hover.$1.dy - 20 * s,
          width: w,
          child: IgnorePointer(
            ignoring: !focused,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _Readout(
                  title: 'MASA ${i + 1}',
                  entry: Format.coin(entry),
                  detail: focused ? (round > 0 ? '$statusText · $round. el' : statusText) : statusText,
                  pot: pot > 0 ? 'Ödül ${Format.coin(pot)}' : null,
                  color: statusColor,
                  watch: focused && t.canWatch
                      ? _Watch(key: ValueKey('spectate-${t.id}'), onTap: () => widget.onSpectate(t.data))
                      : null,
                ),
              ),
            ),
          ),
        ));
      }
    }
    return out;
  }

  Widget _header(Rect area, Size size) {
    final free = widget.tables.where((t) => t['status'] == 'waiting').length;
    return Positioned(
      left: area.left + 4,
      right: size.width - area.right + 4,
      top: area.top,
      height: 40,
      child: Row(children: [
        Container(
          width: 4,
          height: 28,
          decoration: BoxDecoration(
            color: widget.accent,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [BoxShadow(color: widget.accent, blurRadius: 10)],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Flexible(
              child: L3dFit(
                widget.leagueName.isEmpty ? 'OKEY SALONU' : '${L3d.upper(widget.leagueName)} SALONU',
                alignment: Alignment.centerLeft,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2, shadows: L3d.shadow),
              ),
            ),
            Flexible(
              child: L3dFit(
                widget.locked
                    ? 'Giriş şartları tamamlanmadı'
                    : widget.loading
                    ? 'Masalar hazırlanıyor…'
                    : widget.tables.isEmpty
                    ? 'Salon şu an sessiz'
                    : '${widget.tables.length} masa · $free masada yer var · kaydırarak gez',
                alignment: Alignment.centerLeft,
                style: const TextStyle(color: L3d.soft, fontSize: 10.5, fontWeight: FontWeight.w700, shadows: L3d.shadow),
              ),
            ),
          ]),
        ),
        if (!widget.locked) ...[
          Semantics(
            button: true,
            label: 'Masaları yenile',
            child: GestureDetector(
              key: const ValueKey('v2-salon-refresh'),
              onTap: widget.loading ? null : () => widget.onRefresh(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x66111A38),
                  border: Border.all(color: Colors.white.withValues(alpha: .25)),
                ),
                child: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        L3dSlab(
          key: const ValueKey('v2-salon-create'),
          color: const Color(0xFF7B61FF),
          onTap: widget.onCreate,
          radius: 12,
          depth: 4,
          semanticLabel: 'Masa aç',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_circle_rounded, size: 18, color: Colors.white, shadows: L3d.shadow),
            SizedBox(width: 5),
            Text('MASA AÇ', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: .8, shadows: L3d.shadow)),
          ]),
        ),
      ]),
    );
  }

  Widget _stateCard(Rect area) {
    final Widget card;
    if (widget.loading) {
      card = const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: L3d.cyan));
    } else if (widget.locked) {
      final league = widget.lockedLeague;
      final minCoin = (league?['min_coin'] as num?)?.toInt() ?? 0;
      final minRating = (league?['min_rating'] as num?)?.toInt() ?? 0;
      final needCoin = widget.userCoin < minCoin;
      Widget need(IconData icon, String text, bool met) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(met ? Icons.check_circle_rounded : icon, size: 15, color: met ? L3d.green : L3d.amber),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: met ? const Color(0xFFBFF5DC) : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]);
      card = L3dGlass(
        tint: L3d.coral,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: SizedBox(
          width: 230,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_rounded, color: L3d.coral, size: 26, shadows: L3d.shadow),
            const SizedBox(height: 4),
            Text('${L3d.upper((league?['name'] ?? 'Bu lig').toString())} KİLİTLİ',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: .8, shadows: L3d.shadow)),
            const SizedBox(height: 8),
            need(Icons.monetization_on_rounded, '${Format.coin(minCoin)} coin', !needCoin),
            const SizedBox(height: 4),
            need(Icons.star_rounded, 'Seviye ${Format.ratingLevel(minRating)}', widget.userRating >= minRating),
            if (needCoin) ...[
              const SizedBox(height: 10),
              L3dSlab(
                key: const ValueKey('v2-locked-store'),
                color: const Color(0xFFFFA726),
                onTap: widget.onStore,
                radius: 11,
                depth: 4,
                semanticLabel: 'Coin al',
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: const Text('COIN AL',
                    style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: .6, shadows: L3d.shadow)),
              ),
            ],
          ]),
        ),
      );
    } else {
      card = L3dGlass(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Salon şu an sessiz.',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, shadows: L3d.shadow)),
          const SizedBox(height: 3),
          const Text('İlk masayı sen kur ya da Hızlı Oyna ile eşleş.',
              style: TextStyle(color: L3d.soft, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          L3dSlab(
            color: const Color(0xFF7B61FF),
            onTap: widget.onCreate,
            radius: 11,
            depth: 4,
            semanticLabel: 'İlk masayı kur',
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: const Text('İLK MASAYI KUR',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .6, shadows: L3d.shadow)),
          ),
        ]),
      );
    }
    return Positioned.fromRect(
      rect: Rect.fromLTRB(area.left, area.top + 44, area.right, area.bottom),
      child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: card)),
    );
  }
}

// ───────────────────────────── overlay widgets ─────────────────────────────

class _Seat extends StatelessWidget {
  final Map<String, dynamic>? player;
  final bool canJoin, blocked;
  final VoidCallback? onTap;
  const _Seat({super.key, required this.player, required this.canJoin, required this.blocked, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = player;
    final name = p?['username']?.toString() ?? 'Oyuncu';
    return Semantics(
      button: onTap != null,
      label: p == null ? (canJoin ? 'Boş koltuk, otur' : 'Boş koltuk') : name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (p != null)
              Container(
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: [L3d.cyan, Colors.white, L3d.cyan]),
                  boxShadow: [BoxShadow(color: Color(0xAA000000), blurRadius: 8, offset: Offset(0, 5))],
                ),
                child: Stack(alignment: Alignment.bottomCenter, clipBehavior: Clip.none, children: [
                  LobbyAvatar(premium: true, username: name, avatarUrl: p['avatar_url']?.toString(), size: 26, blocked: blocked),
                  if (p['is_bot'] == true) const Positioned(bottom: -4, child: BotBadge()),
                ]),
              )
            else if (canJoin)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5CFFC0), Color(0xFF12A56E)]),
                  border: Border.all(color: Colors.white, width: 2.4),
                  boxShadow: const [BoxShadow(color: Color(0xFF0B6B45), offset: Offset(0, 4)), BoxShadow(color: Color(0x993BF0A0), blurRadius: 16)],
                ),
                child: const Icon(Icons.add_rounded, size: 34, color: Colors.white, shadows: L3d.shadow),
              )
            else
              const SizedBox(height: 52),
            const SizedBox(height: 4),
            if (p != null || canJoin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(color: const Color(0xCC060914), borderRadius: BorderRadius.circular(7)),
                child: Text(
                  p == null ? 'OTUR' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p == null ? L3d.green : Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  final String title, entry, detail;
  final String? pot;
  final Color color;
  final Widget? watch;
  const _Readout({required this.title, required this.entry, required this.detail, required this.color, this.pot, this.watch});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    L3dGlass(
      radius: 12,
      blur: false,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(color: L3d.soft, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
          const SizedBox(width: 6),
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: 6)])),
          const SizedBox(width: 4),
          Text(detail, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 15,
            height: 15,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(center: Alignment(-.35, -.4), colors: [Color(0xFFFFF4C2), Color(0xFFFFC93C), Color(0xFFB7791F)]),
            ),
          ),
          const SizedBox(width: 4),
          Text(entry, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.15, shadows: L3d.shadow)),
          if (pot != null) ...[
            const SizedBox(width: 6),
            Text(pot!, style: const TextStyle(color: Color(0xFFCFF7E4), fontSize: 10, fontWeight: FontWeight.w800)),
          ],
        ]),
      ]),
    ),
    if (watch != null) Padding(padding: const EdgeInsets.only(top: 4), child: watch),
  ]);
}

class _Watch extends StatelessWidget {
  final VoidCallback onTap;
  const _Watch({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => L3dSlab(
    color: const Color(0xFF3D5AFE),
    onTap: onTap,
    radius: 10,
    depth: 3,
    semanticLabel: 'Masayı izle',
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.visibility_rounded, size: 14, color: Colors.white),
      SizedBox(width: 4),
      Text('İZLE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .6)),
    ]),
  );
}
