import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'guga_rig.dart';
export 'guga_rig.dart' show GugaPose;

/// A 2D puppet: head, torso and wings have separate joint influences; the
/// raised idle wing is an actual independent layer rather than a face warp.
class GugaAvatar extends StatefulWidget {
  final GugaPose pose;
  final Animation<double> motion;
  final bool reducedMotion;

  /// Keeps the wider sleeping pose inside the host's viewport when needed.
  final double sleepNudge;
  final VoidCallback? onPoseReady;
  const GugaAvatar(
      {super.key,
      required this.pose,
      required this.motion,
      this.reducedMotion = false,
      this.sleepNudge = 0,
      this.onPoseReady});

  @override
  State<GugaAvatar> createState() => _GugaAvatarState();
}

class _GugaAvatarState extends State<GugaAvatar> {
  final _images = <String, ui.Image>{};
  final _loading = <String>{};
  String? _displayed;
  GugaPose _displayedPose = GugaPose.idle;
  bool _failed = false;
  static const _keys = [
    'idle-body',
    'idle-wing',
    'pet',
    'sleep-mouth',
    'praise-rig-body-v1',
    'thinking',
    'answer',
    'drag'
  ];
  static String _key(GugaPose pose) => switch (pose) {
        GugaPose.idle => 'idle-body',
        GugaPose.sleep => 'sleep-mouth',
        GugaPose.praise => 'praise-rig-body-v1',
        _ => pose.name,
      };

  @override
  void initState() {
    super.initState();
    for (final key in _keys) {
      _load(key);
    }
  }

  @override
  void didUpdateWidget(covariant GugaAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pose != widget.pose) _presentWhenReady();
  }

  void _presentWhenReady() {
    final key = _key(widget.pose);
    if (!_images.containsKey(key) ||
        ((widget.pose == GugaPose.idle || widget.pose == GugaPose.praise) &&
            !_images.containsKey('idle-wing'))) return;
    if (_displayed == key) return;
    if (_displayed != key) {
      setState(() {
        _displayed = key;
        _displayedPose = widget.pose;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _displayed == _key(widget.pose))
        widget.onPoseReady?.call();
    });
  }

  Future<void> _load(String key) async {
    if (_images.containsKey(key) || !_loading.add(key)) return;
    ui.Codec? codec;
    try {
      final data = await rootBundle.load('assets/guga/guga-$key.png');
      codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          targetWidth: 512);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      _images[key] = frame.image;
      _presentWhenReady();
    } catch (_) {
      if (mounted && key == _key(widget.pose)) setState(() => _failed = true);
    } finally {
      codec?.dispose();
      _loading.remove(key);
    }
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _images[_displayed];
    final ready = _displayed == _key(widget.pose);
    return Semantics(
        image: true,
        label: '咕嘎，口腔备考搭子',
        child: Stack(fit: StackFit.expand, children: [
          if (image != null)
            CustomPaint(
                key: ValueKey(
                    'guga-rendered-${ready ? widget.pose.name : _displayed}'),
                painter: _GugaPainter(
                    image: image,
                    pose: _displayedPose,
                    wing: _images['idle-wing'],
                    motion: widget.motion,
                    reduced: widget.reducedMotion,
                    sleepNudge: widget.sleepNudge)),
          if (_failed && image == null)
            const Center(child: Icon(Icons.broken_image_outlined)),
        ]));
  }
}

class _GugaPainter extends CustomPainter {
  final ui.Image image;
  final GugaPose pose;
  final ui.Image? wing;
  final Animation<double> motion;
  final bool reduced;
  final double sleepNudge;
  _GugaPainter(
      {required this.image,
      required this.pose,
      required this.wing,
      required this.motion,
      required this.reduced,
      required this.sleepNudge})
      : super(repaint: reduced ? null : motion);

  static const cols = 32, rows = 36;
  static final rest = [
    for (var y = 0; y <= rows; y++)
      for (var x = 0; x <= cols; x++) Offset(x / cols, y / rows)
  ];
  static final indices = Uint16List.fromList([
    for (var y = 0; y < rows; y++)
      for (var x = 0; x < cols; x++) ...[
        y * (cols + 1) + x,
        (y + 1) * (cols + 1) + x,
        y * (cols + 1) + x + 1,
        y * (cols + 1) + x + 1,
        (y + 1) * (cols + 1) + x,
        (y + 1) * (cols + 1) + x + 1,
      ]
  ]);

  static Rect _fit(ui.Image img, Rect stage) {
    final scale = math.min(stage.width / img.width, stage.height / img.height);
    return Rect.fromCenter(
        center: stage.center,
        width: img.width * scale,
        height: img.height * scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const aspect = 1145 / 1374;
    final width = math.min(size.width * 1.25, size.height * aspect);
    final stage = Rect.fromCenter(
        center: size.center(Offset.zero), width: width, height: width / aspect);
    _drawPose(canvas, stage, image, pose, 1);
  }

  // Draw the same clean cutout as two independent shoulder layers, mirroring
  // the artwork (and therefore the rotation) for the left side.
  void _drawPraiseWing(Canvas canvas, Rect stage, double angle,
      {required bool left}) {
    if (wing == null) return;
    canvas.save();
    if (left) {
      canvas.translate(stage.center.dx * 2, 0);
      canvas.scale(-1, 1);
    }
    final pivot = Offset(
        stage.left + stage.width * .651, stage.top + stage.height * .515);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.drawImageRect(
        wing!,
        Rect.fromLTWH(0, 0, wing!.width.toDouble(), wing!.height.toDouble()),
        _fit(wing!, stage),
        Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  // The feet are isolated below the body and pivot independently. Their
  // upper edges stay underneath the body, hiding the ankle join.
  void _drawPraiseFoot(
      Canvas canvas, ui.Image art, Rect dest, double angle, double lift,
      {required bool left}) {
    final centerX = dest.left + dest.width * (left ? .39 : .61);
    final ankleY = dest.top + dest.height * .855;
    canvas.save();
    canvas.translate(centerX, ankleY + lift * dest.height);
    canvas.rotate(angle);
    canvas.translate(-centerX, -ankleY);
    canvas.clipRect(Rect.fromLTRB(
        left ? dest.left : dest.center.dx,
        dest.top + dest.height * .835,
        left ? dest.center.dx : dest.right,
        dest.bottom));
    canvas.drawImageRect(
        art,
        Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
        dest,
        Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  void _drawPose(Canvas canvas, Rect stage, ui.Image art, GugaPose action,
      double opacity) {
    if (opacity <= 0) return;
    if (action == GugaPose.sleep) stage = stage.shift(Offset(sleepNudge, 0));
    final frame = GugaRigFrame.sample(action, motion.value, reduced: reduced);
    final dest = gugaArtworkRect(
        Size(art.width.toDouble(), art.height.toDouble()), stage, action);
    final aspect = dest.width / dest.height;
    canvas.saveLayer(stage.inflate(stage.width * .18),
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    // Parent/root bone affects all child parts identically.
    final root = Offset(stage.center.dx, stage.top + stage.height * .86);
    canvas.translate(root.dx, root.dy + frame.rootY * stage.height);
    canvas.rotate(frame.rootAngle);
    canvas.translate(-root.dx, -root.dy);
    if (action == GugaPose.praise) {
      _drawPraiseWing(canvas, stage, frame.leftWing, left: true);
      _drawPraiseWing(canvas, stage, frame.rightWing, left: false);
      _drawPraiseFoot(canvas, art, dest, frame.leftFoot, frame.footLift,
          left: true);
      _drawPraiseFoot(canvas, art, dest, frame.rightFoot, frame.footLift,
          left: false);
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(
          dest.left, dest.top, dest.right, dest.top + dest.height * .855));
    }
    final positions = <Offset>[], tex = <Offset>[];
    for (final p in rest) {
      final q = gugaSkinPoint(p, action, frame, aspect);
      positions.add(
          Offset(dest.left + q.dx * dest.width, dest.top + q.dy * dest.height));
      tex.add(Offset(p.dx * art.width, p.dy * art.height));
    }
    final shader = ui.ImageShader(art, ui.TileMode.clamp, ui.TileMode.clamp,
        Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    final mesh = ui.Vertices(ui.VertexMode.triangles, positions,
        textureCoordinates: tex, indices: indices);
    canvas.drawVertices(
        mesh,
        BlendMode.src,
        Paint()
          ..shader = shader
          ..filterQuality = FilterQuality.medium);
    mesh.dispose();
    if (action == GugaPose.praise) canvas.restore();
    if (action == GugaPose.idle && wing != null) {
      final pivot = Offset(
          stage.left + stage.width * .651, stage.top + stage.height * .515);
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(frame.rightWing);
      canvas.translate(-pivot.dx, -pivot.dy);
      canvas.drawImageRect(
          wing!,
          Rect.fromLTWH(0, 0, wing!.width.toDouble(), wing!.height.toDouble()),
          _fit(wing!, stage),
          Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    }
    canvas.restore();
    if (action == GugaPose.sleep) {
      final t = reduced ? 0.0 : motion.value;
      final painter = TextPainter(
          text: TextSpan(
              text: 'Zzz',
              style: TextStyle(
                  color: Colors.blueGrey.withValues(
                      alpha: opacity * (.45 + .3 * math.sin(t * math.pi))),
                  fontSize: math.max(9, stage.width * .10),
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr)
        ..layout();
      painter.paint(
          canvas,
          Offset(stage.left + stage.width * .18,
              stage.top + stage.height * (.22 - .025 * math.sin(t * math.pi))));
    }
  }

  @override
  bool shouldRepaint(covariant _GugaPainter old) =>
      old.image != image ||
      old.pose != pose ||
      old.wing != wing ||
      old.motion != motion ||
      old.reduced != reduced ||
      old.sleepNudge != sleepNudge;
}
