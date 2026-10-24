import 'dart:math' as math;

/// Local, deterministic geometry for the studio's interactive sample viewer.
/// Deliberately independent of Flutter and of any generation provider.
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x, y, z;
  Vec3 operator +(Vec3 b) => Vec3(x + b.x, y + b.y, z + b.z);
  Vec3 operator -(Vec3 b) => Vec3(x - b.x, y - b.y, z - b.z);
  Vec3 cross(Vec3 b) =>
      Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 rotate(double yaw, double pitch) {
    final xx = x * math.cos(yaw) + z * math.sin(yaw);
    final zz = -x * math.sin(yaw) + z * math.cos(yaw);
    return Vec3(
      xx,
      y * math.cos(pitch) - zz * math.sin(pitch),
      y * math.sin(pitch) + zz * math.cos(pitch),
    );
  }
}

class MeshFace {
  const MeshFace(this.points, this.color);
  final List<Vec3> points;
  final int color;
}

enum SampleModel { sentinel, crystal, bonsai, vessel, chest, portal }

String sampleName(SampleModel model) => switch (model) {
  SampleModel.sentinel => 'Scout Sentinel',
  SampleModel.crystal => 'Astral Crystal',
  SampleModel.bonsai => 'Little Bonsai',
  SampleModel.vessel => 'Orbit Vessel',
  SampleModel.chest => 'Forgotten Treasure',
  SampleModel.portal => 'Ancient Gateway',
};

SampleModel sampleForTitle(String title) {
  final value = title.toLowerCase();
  if (value.contains('mač') || value.contains('kristal')) {
    return SampleModel.crystal;
  }
  if (value.contains('bor') || value.contains('stena')) {
    return SampleModel.bonsai;
  }
  if (value.contains('vaza') || value.contains('fenjer')) {
    return SampleModel.vessel;
  }
  if (value.contains('sanduk') || value.contains('kontejner')) {
    return SampleModel.chest;
  }
  if (value.contains('kapija') ||
      value.contains('stub') ||
      value.contains('oltar')) {
    return SampleModel.portal;
  }
  return SampleModel.sentinel;
}

class SampleScene {
  SampleScene(SampleModel model) {
    switch (model) {
      case SampleModel.sentinel:
        _robot();
      case SampleModel.crystal:
        _crystal();
      case SampleModel.bonsai:
        _bonsai();
      case SampleModel.vessel:
        _vessel();
      case SampleModel.chest:
        _chest();
      case SampleModel.portal:
        _portal();
    }
  }
  final List<MeshFace> faces = [];
  static const ivory = 0xc9d5ca, dark = 0x323d3b, lime = 0xc1f45c;

  void box(double x, double y, double z, double w, double h, double d, int c) {
    final p = [
      for (final o in [
        (-1, -1, -1),
        (1, -1, -1),
        (1, 1, -1),
        (-1, 1, -1),
        (-1, -1, 1),
        (1, -1, 1),
        (1, 1, 1),
        (-1, 1, 1),
      ])
        Vec3(x + o.$1 * w / 2, y + o.$2 * h / 2, z + o.$3 * d / 2),
    ];
    for (final f in [
      [0, 3, 2, 1],
      [4, 5, 6, 7],
      [0, 4, 7, 3],
      [1, 2, 6, 5],
      [3, 7, 6, 2],
      [0, 1, 5, 4],
    ]) {
      faces.add(MeshFace(f.map((i) => p[i]).toList(), c));
    }
  }

  void orb(
    double x,
    double y,
    double z,
    double rx,
    double ry,
    double rz,
    int c, {
    int rings = 8,
    int segments = 12,
  }) {
    Vec3 point(int i, int j) {
      final a = math.pi * i / rings, b = 2 * math.pi * j / segments;
      return Vec3(
        x + rx * math.sin(a) * math.cos(b),
        y + ry * math.cos(a),
        z + rz * math.sin(a) * math.sin(b),
      );
    }

    for (var i = 0; i < rings; i++) {
      for (var j = 0; j < segments; j++) {
        faces.add(
          MeshFace(
            [
              point(i, j),
              point(i + 1, j),
              point(i + 1, j + 1),
              point(i, j + 1),
            ].reversed.toList(),
            c,
          ),
        );
      }
    }
  }

  void ring(
    double x,
    double y,
    double z,
    double radius,
    double height,
    int c, {
    double? top,
    int segments = 12,
  }) {
    for (var i = 0; i < segments; i++) {
      final a = i * math.pi * 2 / segments;
      final b = (i + 1) * math.pi * 2 / segments;
      final r = top ?? radius;
      faces.add(
        MeshFace(
          [
            Vec3(
              x + radius * math.cos(a),
              y - height / 2,
              z + radius * math.sin(a),
            ),
            Vec3(
              x + radius * math.cos(b),
              y - height / 2,
              z + radius * math.sin(b),
            ),
            Vec3(x + r * math.cos(b), y + height / 2, z + r * math.sin(b)),
            Vec3(x + r * math.cos(a), y + height / 2, z + r * math.sin(a)),
          ].reversed.toList(),
          c,
        ),
      );
      faces.add(
        MeshFace(
          [
            Vec3(x, y + height / 2, z),
            Vec3(x + r * math.cos(a), y + height / 2, z + r * math.sin(a)),
            Vec3(x + r * math.cos(b), y + height / 2, z + r * math.sin(b)),
          ].reversed.toList(),
          c,
        ),
      );
    }
  }

  void _robot() {
    // Articulated armor, exposed joints, backpack and luminous visor.
    box(0, .35, -.29, .69, .94, .34, dark);
    box(0, .53, -.48, .46, .6, .16, 0x65725d);
    orb(0, .32, 0, .49, .65, .3, dark);
    orb(0, .62, .06, .54, .45, .32, ivory);
    box(0, .62, .335, .35, .24, .055, dark);
    box(0, .62, .37, .19, .055, .025, lime);
    for (var i = 0; i < 4; i++) {
      box(0, .08 + i * .08, .285, .37, .034, .035, 0x768279);
    }
    orb(0, -.33, 0, .35, .23, .26, ivory);
    ring(0, .98, 0, .145, .18, dark);
    orb(0, 1.32, .015, .33, .38, .3, ivory, rings: 10, segments: 16);
    orb(0, 1.34, .205, .285, .21, .15, 0x202e2c, rings: 6, segments: 16);
    box(0, 1.37, .35, .38, .045, .023, lime);
    box(0, 1.08, .23, .19, .1, .1, 0x6a756d);
    box(-.25, 1.69, -.03, .035, .26, .035, dark);
    orb(-.25, 1.83, -.03, .042, .042, .042, lime, rings: 4, segments: 6);
    for (final side in [-1.0, 1.0]) {
      orb(side * .59, .76, 0, .235, .255, .25, ivory);
      box(side * .63, .78, .22, .12, .17, .06, 0xe2a56b);
      orb(side * .66, .35, 0, .145, .33, .14, dark);
      orb(side * .68, .06, .025, .16, .15, .16, 0x65736b);
      orb(side * .71, -.2, .07, .19, .29, .19, ivory);
      box(side * .72, -.17, .235, .12, .2, .05, 0x859887);
      orb(side * .73, -.53, .1, .13, .13, .13, dark);
      for (var f = 0; f < 3; f++) {
        box(side * .73 + (f - 1) * .07, -.68, .17, .052, .2, .09, ivory);
      }
      orb(side * .235, -.66, 0, .205, .34, .22, ivory);
      box(side * .235, -.7, .21, .16, .29, .06, 0x859887);
      orb(side * .235, -.99, .02, .15, .16, .16, dark);
      orb(side * .235, -1.04, .16, .14, .15, .1, 0xe2a56b);
      orb(side * .235, -1.34, 0, .18, .33, .19, ivory);
      box(side * .235, -1.34, .175, .08, .34, .04, dark);
      box(side * .235, -1.68, .11, .32, .19, .49, dark);
      box(side * .235, -1.62, .19, .32, .15, .36, ivory);
    }
  }

  void _crystal() {
    const colors = [0x96dfd1, 0x64bfb4, 0xc4f9e5, 0x4c9c9f, 0x9cc9ed, 0x779abf];
    for (var k = 0; k < 5; k++) {
      final x = (k - 2) * .32, y = k == 2 ? .25 : -.2;
      final h = k == 2 ? 2.8 : 1.3 + (k % 2) * .5;
      final z = k.isEven ? 0.0 : .3;
      for (var i = 0; i < 6; i++) {
        Vec3 p(int j, double yy) => Vec3(
          x + .27 * math.cos(j * math.pi / 3),
          yy,
          z + .27 * math.sin(j * math.pi / 3),
        );
        faces.add(
          MeshFace([
            p(i, y - h / 2),
            p(i + 1, y - h / 2),
            p(i + 1, y + h / 3),
            p(i, y + h / 3),
          ], colors[i]),
        );
        faces.add(
          MeshFace([
            p(i, y + h / 3),
            p(i + 1, y + h / 3),
            Vec3(x, y + h / 2 + .25, z),
          ], colors[(i + 2) % 6]),
        );
      }
    }
    orb(0, -1.35, 0, 1, .23, .65, 0x444b52, rings: 4, segments: 9);
  }

  void _bonsai() {
    ring(0, -1.2, 0, .54, .55, 0xc4a383, top: .75);
    ring(0, -.89, 0, .78, .12, 0xe0c1a0);
    ring(0, -.82, 0, .69, .035, 0x48423a);
    ring(.08, -.1, 0, .15, 1.5, 0x816a4e, top: .08);
    box(-.27, .3, 0, .68, .12, .12, 0x816a4e);
    box(.31, .65, 0, .7, .1, .1, 0x816a4e);
    orb(-.55, .53, 0, .76, .34, .56, 0x819c5b, rings: 5, segments: 9);
    orb(.49, .85, 0, .72, .32, .52, 0xa6b86a, rings: 5, segments: 9);
    orb(0, 1.24, 0, .63, .33, .48, 0xbed085, rings: 5, segments: 9);
  }

  void _vessel() {
    for (var i = 0; i < 24; i++) {
      final y = -1.25 + i * .1;
      double radius(double t) =>
          .29 + .48 * math.pow(math.sin((t + 1.25) / 2.5 * math.pi), 2);
      ring(
        0,
        y,
        0,
        radius(y),
        .1,
        i % 5 == 0 ? 0xd8a375 : 0xc8b59d,
        top: radius(y + .1),
        segments: 24,
      );
    }
    ring(0, 1.18, 0, .31, .1, 0xe8d1ae, top: .35, segments: 24);
  }

  void _chest() {
    box(0, -.35, 0, 1.95, 1.15, 1.15, 0x8b6245);
    for (var i = 0; i < 5; i++) {
      box(0, -.81 + i * .23, .587, 1.9, .025, .018, 0x543e2e);
    }
    orb(0, .23, 0, .97, .56, .57, 0xa77b50, rings: 8, segments: 12);
    for (final x in [-.74, .74]) {
      box(x, -.35, .61, .14, 1.22, .1, 0xcbb273);
      box(x, .25, .55, .14, .6, .13, 0xcbb273);
      box(x, -.94, 0, .18, .16, 1.3, 0xcbb273);
    }
    box(0, -.05, .65, .27, .35, .12, 0xe0c57a);
    box(0, -.05, .72, .06, .14, .02, 0x3b3934);
  }

  void _portal() {
    const stone = 0x9ca69a;
    box(0, -1.42, 0, 2.5, .25, 1.1, 0x6c786e);
    for (final x in [-.87, .87]) {
      for (var i = 0; i < 5; i++) {
        box(x, -1.13 + i * .42, 0, .52, .4, .72, i.isEven ? stone : 0x7e8f82);
      }
      box(x, 1, 0, .7, .2, .85, 0xb1baaa);
    }
    for (var i = 0; i < 7; i++) {
      final a = math.pi * i / 6;
      box(.86 * math.cos(a), .9 + .7 * math.sin(a), 0, .42, .42, .7, stone);
    }
    box(0, 1.59, .4, .25, .29, .1, lime);
  }
}

class ProjectedFace {
  ProjectedFace(this.points, this.depth, this.color, this.light);
  final List<(double, double)> points;
  final double depth, light;
  final int color;
}

List<ProjectedFace> projectScene(
  SampleScene scene, {
  double yaw = -.38,
  double pitch = -.08,
  double zoom = 1,
}) {
  final result = <ProjectedFace>[];
  for (final face in scene.faces) {
    final p = face.points.map((p) => p.rotate(yaw, pitch)).toList();
    final normal = (p[1] - p[0]).cross(p[2] - p[0]);
    final light = normal.length < .00001
        ? .65
        : (.63 +
                  (-normal.x * .35 + normal.y * .65 + normal.z * .55) /
                      normal.length *
                      .35)
              .clamp(.28, 1.0);
    result.add(
      ProjectedFace(
        [
          for (final v in p)
            (v.x * zoom * 5 / (5 - v.z), -v.y * zoom * 5 / (5 - v.z)),
        ],
        p.fold<double>(0, (v, p) => v + p.z) / p.length,
        face.color,
        light,
      ),
    );
  }
  result.sort((a, b) => a.depth.compareTo(b.depth));
  return result;
}
