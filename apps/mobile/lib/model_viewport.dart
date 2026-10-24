import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'mesh_scene.dart';

enum ViewportMaterial { studio, clay, wireframe }

class ModelViewport extends StatefulWidget {
  const ModelViewport({
    super.key,
    this.model = SampleModel.sentinel,
    this.interactive = true,
    this.material = ViewportMaterial.studio,
    this.showGrid = false,
    this.resetKey = 0,
  });
  final SampleModel model;
  final bool interactive, showGrid;
  final ViewportMaterial material;
  final int resetKey;
  @override
  State<ModelViewport> createState() => _ModelViewportState();
}

class _ModelViewportState extends State<ModelViewport> {
  late SampleScene scene = SampleScene(widget.model);
  double yaw = -.38, pitch = -.08, zoom = 1, startZoom = 1;
  Offset pan = Offset.zero;
  @override
  void didUpdateWidget(ModelViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) scene = SampleScene(widget.model);
    if (oldWidget.resetKey != widget.resetKey ||
        oldWidget.model != widget.model) {
      yaw = -.38;
      pitch = -.08;
      zoom = 1;
      pan = Offset.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget canvas = RepaintBoundary(
      child: CustomPaint(
        painter: ScenePainter(
          scene,
          yaw: yaw,
          pitch: pitch,
          zoom: zoom,
          pan: pan,
          material: widget.material,
          grid: widget.showGrid,
        ),
        size: Size.infinite,
      ),
    );
    if (!widget.interactive) return canvas;
    canvas = Listener(
      onPointerMove: (event) {
        if (event.buttons == kSecondaryMouseButton) {
          setState(
            () => pan = Offset(
              (pan.dx + event.delta.dx).clamp(-220, 220),
              (pan.dy + event.delta.dy).clamp(-220, 220),
            ),
          );
        }
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          setState(
            () => zoom = (zoom * math.exp(-event.scrollDelta.dy * .001)).clamp(
              .45,
              2.4,
            ),
          );
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => setState(() {
          yaw = -.38;
          pitch = -.08;
          zoom = 1;
          pan = Offset.zero;
        }),
        onScaleStart: (_) => startZoom = zoom,
        onScaleUpdate: (e) => setState(() {
          if (e.pointerCount > 1) {
            zoom = (startZoom * e.scale).clamp(.45, 2.4);
          } else {
            yaw += e.focalPointDelta.dx * .009;
            pitch = (pitch + e.focalPointDelta.dy * .006).clamp(-.9, .9);
          }
        }),
        child: canvas,
      ),
    );
    return Semantics(
      label:
          'Interaktivni 3D pregled. Prevuci za rotaciju, skroluj za zum, dvoklik za reset.',
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: canvas),
    );
  }
}

class ScenePainter extends CustomPainter {
  ScenePainter(
    this.scene, {
    this.yaw = -.38,
    this.pitch = -.08,
    this.zoom = 1,
    this.pan = Offset.zero,
    this.material = ViewportMaterial.studio,
    this.grid = false,
  });
  final SampleScene scene;
  final double yaw, pitch, zoom;
  final Offset pan;
  final ViewportMaterial material;
  final bool grid;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(size.width / 3.4, size.height / 4.5);
    final center = Offset(size.width * .5, size.height * .5) + pan;
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, scale * 1.83),
        width: scale * 1.7 * zoom,
        height: scale * .17 * zoom,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: .36)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    if (grid) {
      final paint = Paint()
        ..color = const Color(0xff43483d).withValues(alpha: .35)
        ..strokeWidth = .6;
      for (var i = -7; i <= 7; i++) {
        final start = center + Offset(i * scale * .45, scale * 1.8);
        canvas.drawLine(
          start + Offset(-scale, 0),
          start + Offset(scale, -scale * 1.2),
          paint,
        );
        canvas.drawLine(
          center + Offset(-scale * 3, scale * (1.8 - i * .1)),
          center + Offset(scale * 3, scale * (1.8 - i * .1)),
          paint,
        );
      }
    }
    for (final face in projectScene(
      scene,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
    )) {
      final path = Path();
      for (var i = 0; i < face.points.length; i++) {
        final p =
            center +
            Offset(face.points[i].$1 * scale, face.points[i].$2 * scale);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      final base = material == ViewportMaterial.clay
          ? const Color(0xffd4d1c8)
          : Color(0xff000000 | face.color);
      final c = Color.fromARGB(
        255,
        (base.r * 255 * face.light).round(),
        (base.g * 255 * face.light).round(),
        (base.b * 255 * face.light).round(),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = material == ViewportMaterial.wireframe
              ? const Color(0xff1b2118)
              : c,
      );
      if (material == ViewportMaterial.wireframe) {
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xffc1f45c).withValues(alpha: .65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(ScenePainter old) =>
      old.scene != scene ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.material != material ||
      old.grid != grid;
}
