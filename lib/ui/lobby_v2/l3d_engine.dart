import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Minimal real-time 3D renderer for the lobby, drawn with Canvas.drawVertices.
///
/// Scene = objects made of triangles. Each frame: transform to camera space,
/// back-face cull, light every vertex (ambient + directional + point lights,
/// Blinn-Phong specular, emissive), apply distance fog, then paint objects
/// far-to-near. Objects are authored bottom-up so their own faces need no
/// per-triangle sort while the camera stays above the tables.

class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  static const zero = V3(0, 0, 0);
  static const up = V3(0, 1, 0);
  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  V3 operator -() => V3(-x, -y, -z);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get n {
    final l = length;
    return l == 0 ? this : V3(x / l, y / l, z / l);
  }

  V3 rotY(double a) {
    final c = math.cos(a), s = math.sin(a);
    return V3(x * c + z * s, y, -x * s + z * c);
  }
}

class Material3 {
  final Color color;
  final double gloss, shininess, emissive, alpha;
  final bool twoSided;
  const Material3(
    this.color, {
    this.gloss = .15,
    this.shininess = 24,
    this.emissive = 0,
    this.alpha = 1,
    this.twoSided = false,
  });
}

class Face3 {
  final V3 a, b, c, normal;
  final Material3 m;
  Face3(this.a, this.b, this.c, this.m) : normal = (b - a).cross(c - a).n;
}

/// Paint layers: floor, then decals/shadows on it, then solid objects.
enum Layer3 { floor, decal, solid }

class Obj3 {
  final List<Face3> faces;
  final V3 center;
  final Layer3 layer;
  const Obj3(this.faces, this.center, {this.layer = Layer3.solid});
}

class DirLight {
  final V3 dir; // from surface toward the light
  final Color color;
  final double intensity;
  DirLight(V3 dir, this.color, this.intensity) : dir = dir.n;
}

class PointLight3 {
  final V3 pos;
  final Color color;
  final double intensity, range;
  const PointLight3(this.pos, this.color, this.intensity, {this.range = 2.2});
}

/// Builds faces with outward-facing normals for culling and lighting.
class Mesh3 {
  final faces = <Face3>[];

  void tri(V3 a, V3 b, V3 c, Material3 m) => faces.add(Face3(a, b, c, m));

  /// Quad with [outward] hint; winding flips so the normal faces it.
  void quad(V3 a, V3 b, V3 c, V3 d, Material3 m, {V3? outward}) {
    final n = (b - a).cross(c - a);
    if (outward != null && n.dot(outward) < 0) {
      tri(a, c, b, m);
      tri(a, d, c, m);
    } else {
      tri(a, b, c, m);
      tri(a, c, d, m);
    }
  }

  /// Vertical extrusion of a convex XZ outline between [y0] and [y1].
  /// [origin] and [rotY] place it in the world. Top is a centre fan so point
  /// lights can pool light across it.
  void prism(
    List<Offset> outline,
    double y0,
    double y1,
    Material3 side, {
    Material3? top,
    V3 origin = V3.zero,
    double rotY = 0,
    bool bottom = false,
    double topInset = 0,
  }) {
    V3 at(Offset p, double y) => V3(p.dx, y, p.dy).rotY(rotY) + origin;
    var cx = 0.0, cz = 0.0;
    for (final p in outline) {
      cx += p.dx;
      cz += p.dy;
    }
    final c = Offset(cx / outline.length, cz / outline.length);
    final centreTop = at(c, y1);
    for (var i = 0; i < outline.length; i++) {
      final p = outline[i], q = outline[(i + 1) % outline.length];
      final mid = (p + q) / 2 - c;
      final out = V3(mid.dx, 0, mid.dy).rotY(rotY);
      final pt = topInset == 0 ? p : c + (p - c) * (1 - topInset);
      final qt = topInset == 0 ? q : c + (q - c) * (1 - topInset);
      quad(at(p, y0), at(q, y0), at(qt, y1), at(pt, y1), side, outward: out);
      final tp = at(pt, y1), tq = at(qt, y1);
      final n = (tq - tp).cross(centreTop - tp);
      n.y >= 0 ? tri(tp, tq, centreTop, top ?? side) : tri(tp, centreTop, tq, top ?? side);
      if (bottom) {
        final b0 = at(p, y0), b1 = at(q, y0), bc = at(c, y0);
        final nb = (b1 - b0).cross(bc - b0);
        nb.y <= 0 ? tri(b0, b1, bc, side) : tri(b0, bc, b1, side);
      }
    }
  }

  /// Axis-aligned (then Y-rotated) box.
  void box(V3 centre, V3 size, Material3 m, {Material3? top, double rotY = 0}) {
    final hx = size.x / 2, hz = size.z / 2;
    prism(
      [Offset(-hx, -hz), Offset(hx, -hz), Offset(hx, hz), Offset(-hx, hz)],
      centre.y - size.y / 2,
      centre.y + size.y / 2,
      m,
      top: top,
      origin: V3(centre.x, 0, centre.z),
      rotY: rotY,
    );
  }

  void cylinder(V3 base, double r, double h, Material3 m, {Material3? top, int seg = 18, double topScale = 1}) {
    prism(
      [for (var i = 0; i < seg; i++) Offset(math.cos(i / seg * math.pi * 2) * r, math.sin(i / seg * math.pi * 2) * r)],
      base.y,
      base.y + h,
      m,
      top: top,
      origin: V3(base.x, 0, base.z),
      topInset: 1 - topScale,
    );
  }

  /// Surface of revolution around the Y axis from (radius, y) [profile]
  /// points listed bottom to top.
  void lathe(V3 base, List<Offset> profile, Material3 m, {int seg = 22}) {
    for (var i = 0; i < profile.length - 1; i++) {
      final p0 = profile[i], p1 = profile[i + 1];
      for (var s = 0; s < seg; s++) {
        final a0 = s / seg * math.pi * 2, a1 = (s + 1) / seg * math.pi * 2;
        V3 at(Offset p, double a) => base + V3(math.cos(a) * p.dx, p.dy, math.sin(a) * p.dx);
        final mid = (a0 + a1) / 2;
        final out = V3(math.cos(mid), (p0.dx - p1.dx) * 2, math.sin(mid));
        if (p0.dx < .0001 && p1.dx < .0001) continue;
        quad(at(p0, a0), at(p0, a1), at(p1, a1), at(p1, a0), m, outward: out);
      }
    }
  }

  /// Flat disc on the floor (shadow / glow decal).
  void disc(V3 centre, double rx, double rz, Material3 m, {int seg = 24}) {
    for (var i = 0; i < seg; i++) {
      final a0 = i / seg * math.pi * 2, a1 = (i + 1) / seg * math.pi * 2;
      tri(centre, centre + V3(math.cos(a1) * rx, 0, math.sin(a1) * rz), centre + V3(math.cos(a0) * rx, 0, math.sin(a0) * rz), m);
    }
  }

  Obj3 build(V3 centre, {Layer3 layer = Layer3.solid}) => Obj3(List.of(faces), centre, layer: layer);
}

/// Rounded-rectangle outline for prisms.
List<Offset> roundedRect(double w, double d, double r, {int corner = 5}) {
  final pts = <Offset>[];
  final hx = w / 2 - r, hz = d / 2 - r;
  for (final (cx, cz, start) in [(hx, hz, 0.0), (-hx, hz, .5), (-hx, -hz, 1.0), (hx, -hz, 1.5)]) {
    for (var i = 0; i <= corner; i++) {
      final a = (start + i / corner * .5) * math.pi;
      pts.add(Offset(cx + math.cos(a) * r, cz + math.sin(a) * r));
    }
  }
  return pts;
}

class Camera3 {
  final V3 eye, target;
  final double fovY;
  final Offset principal;
  late final V3 f, r, u;
  Camera3({required this.eye, required this.target, required this.principal, this.fovY = .9}) {
    f = (target - eye).n;
    r = f.cross(V3.up).n;
    u = r.cross(f);
  }

  double focal(Size s) => s.height * .5 / math.tan(fovY / 2);

  /// Screen point and pixels-per-unit at that depth, or null when behind.
  (Offset, double)? project(V3 p, Size s) {
    final v = p - eye;
    final z = v.dot(f);
    if (z < .05) return null;
    final k = focal(s) / z;
    return (Offset(principal.dx + v.dot(r) * k, principal.dy - v.dot(u) * k), k);
  }
}

class Scene3 {
  final List<Obj3> objects;
  final List<DirLight> dirLights;
  final List<PointLight3> pointLights;
  final Color ambient, fog;
  final double fogStart, fogEnd;
  const Scene3({
    required this.objects,
    required this.dirLights,
    required this.pointLights,
    this.ambient = const Color(0xFF1C2340),
    this.fog = const Color(0xFF0A0F22),
    this.fogStart = 5,
    this.fogEnd = 15,
  });
}

class Scene3Painter extends CustomPainter {
  final Scene3 scene;
  final Camera3 camera;
  Scene3Painter(this.scene, this.camera, {super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final cam = camera;
    final focal = cam.focal(size);
    final nearLights = scene.pointLights.where((l) => (l.pos - cam.target).length < 9).toList();

    final ordered = [...scene.objects]..sort((a, b) {
      final la = a.layer.index, lb = b.layer.index;
      if (la != lb) return la - lb;
      return (b.center - cam.eye).length.compareTo((a.center - cam.eye).length);
    });

    final pos = <double>[];
    final col = <int>[];
    final ar = scene.ambient.r, ag = scene.ambient.g, ab = scene.ambient.b;
    final fr = scene.fog.r, fg = scene.fog.g, fb = scene.fog.b;

    for (final obj in ordered) {
      // Skip objects far outside the view.
      final oc = obj.center - cam.eye;
      if (oc.dot(cam.f) < -2) continue;
      for (final face in obj.faces) {
        final m = face.m;
        var n = face.normal;
        final toEye = cam.eye - face.a;
        if (n.dot(toEye) <= 0) {
          if (!m.twoSided) continue;
          n = -n;
        }
        final verts = [face.a, face.b, face.c];
        final screen = List<Offset?>.filled(3, null);
        var behind = false;
        for (var i = 0; i < 3; i++) {
          final v = verts[i] - cam.eye;
          final z = v.dot(cam.f);
          if (z < .05) {
            behind = true;
            break;
          }
          final k = focal / z;
          screen[i] = Offset(cam.principal.dx + v.dot(cam.r) * k, cam.principal.dy - v.dot(cam.u) * k);
        }
        if (behind) continue;
        final br = m.color.r, bg = m.color.g, bb = m.color.b;
        for (var i = 0; i < 3; i++) {
          final p = verts[i];
          final view = (cam.eye - p).n;
          var r = ar * br, g = ag * bg, b = ab * bb;
          for (final l in scene.dirLights) {
            final d = math.max(0.0, n.dot(l.dir)) * l.intensity;
            final h = (l.dir + view).n;
            final s = math.pow(math.max(0.0, n.dot(h)), m.shininess) * m.gloss * l.intensity;
            r += br * l.color.r * d + l.color.r * s;
            g += bg * l.color.g * d + l.color.g * s;
            b += bb * l.color.b * d + l.color.b * s;
          }
          for (final l in nearLights) {
            final lv = l.pos - p;
            final dist = lv.length;
            final ld = lv * (1 / dist);
            final att = l.intensity / (1 + (dist / l.range) * (dist / l.range) * 3);
            final d = math.max(0.0, n.dot(ld)) * att;
            final h = (ld + view).n;
            final s = math.pow(math.max(0.0, n.dot(h)), m.shininess) * m.gloss * att;
            r += br * l.color.r * d + l.color.r * s;
            g += bg * l.color.g * d + l.color.g * s;
            b += bb * l.color.b * d + l.color.b * s;
          }
          r += br * m.emissive;
          g += bg * m.emissive;
          b += bb * m.emissive;
          // Soft filmic roll-off keeps highlights from clipping harshly.
          r = r / (1 + r * .35) * 1.35;
          g = g / (1 + g * .35) * 1.35;
          b = b / (1 + b * .35) * 1.35;
          final z = (p - cam.eye).dot(cam.f);
          final t = ((z - scene.fogStart) / (scene.fogEnd - scene.fogStart)).clamp(0.0, 1.0);
          r = r + (fr - r) * t;
          g = g + (fg - g) * t;
          b = b + (fb - b) * t;
          final s = screen[i]!;
          pos
            ..add(s.dx)
            ..add(s.dy);
          col.add(Color.from(alpha: m.alpha, red: r.clamp(0.0, 1.0), green: g.clamp(0.0, 1.0), blue: b.clamp(0.0, 1.0)).toARGB32());
        }
      }
    }
    if (pos.isEmpty) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.fromList(pos),
      colors: Int32List.fromList(col),
    );
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }

  @override
  bool shouldRepaint(Scene3Painter old) => old.scene != scene || old.camera != camera;
}
