import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum DafeiyuPose {
  hungry('01-hungry-bowl-approved-master.png'),
  happy('02-happy-bowl.png'),
  wave('03-wave.png'),
  thinking('04-thinking.png'),
  pout('05-pout.png'),
  drowsy('06-sleepy.png'),
  sleep('07-prone-sleep-approved.png'),
  praise('08-praise.png');

  const DafeiyuPose(this.file);
  final String file;
  String get asset => 'assets/dafeiyu/runtime/$file';
}

/// Lightweight linear-blend skinning of approved PNG artwork, not a layered
/// Live2D/Spine model. Pose changes use separate approved drawings.
class DafeiyuRig {
  static const columns = 24, rows = 36;
  static const parents = [-1, 0, 1, 2, 2, 1, 1, 0];
  final DafeiyuPose pose;
  late final List<Offset> joints;
  late final List<List<double>> weights;
  DafeiyuRig(this.pose) {
    joints = pose == DafeiyuPose.sleep
        ? const [
            Offset(.65, .70),
            Offset(.61, .65),
            Offset(.40, .60),
            Offset(.19, .66),
            Offset(.72, .64),
            Offset(.33, .69),
            Offset(.48, .70),
            Offset(.86, .46)
          ]
        : const [
            Offset(.50, .82),
            Offset(.50, .67),
            Offset(.50, .52),
            Offset(.22, .55),
            Offset(.78, .55),
            Offset(.39, .59),
            Offset(.63, .59),
            Offset(.50, .89)
          ];
    weights = [for (final p in rest) _weights(p)];
  }
  static final rest = [
    for (var y = 0; y <= rows; y++)
      for (var x = 0; x <= columns; x++) Offset(x / columns, y / rows)
  ];
  static final indices = Uint16List.fromList([
    for (var y = 0; y < rows; y++)
      for (var x = 0; x < columns; x++) ...[
        y * (columns + 1) + x,
        (y + 1) * (columns + 1) + x,
        y * (columns + 1) + x + 1,
        y * (columns + 1) + x + 1,
        (y + 1) * (columns + 1) + x,
        (y + 1) * (columns + 1) + x + 1,
      ]
  ]);
  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _g(Offset p, double x, double y, double sx, double sy) =>
      math.exp(-math.pow((p.dx - x) / sx, 2) - math.pow((p.dy - y) / sy, 2));
  List<double> _weights(Offset p) {
    final x = p.dx, y = p.dy;
    double head, leftHair, rightHair, leftArm = 0, rightArm = 0, feet;
    if (pose == DafeiyuPose.sleep) {
      head = .94 * _g(p, .38, .58, .40, .21);
      leftHair = .8 * _g(p, .14, .70, .20, .14);
      rightHair = .6 * _g(p, .72, .68, .15, .13);
      feet = .8 * _g(p, .87, .46, .13, .13);
    } else {
      head = .98 * (1 - _smooth(.48, .57, y));
      leftHair = .95 *
          (1 - _smooth(.19, .31, x)) *
          _smooth(.45, .54, y) *
          (1 - _smooth(.77, .88, y));
      rightHair = .95 *
          _smooth(.69, .81, x) *
          _smooth(.45, .54, y) *
          (1 - _smooth(.77, .88, y));
      if (pose == DafeiyuPose.wave || pose == DafeiyuPose.praise) {
        leftArm =
            .9 * _g(p, .31, pose == DafeiyuPose.praise ? .52 : .53, .085, .07);
      }
      if (pose == DafeiyuPose.praise)
        rightArm = .9 * _g(p, .74, .51, .085, .075);
      feet = .95 * _smooth(.83, .91, y);
    }
    final w = [
      .06,
      math.max(
          .05, 1 - head - leftHair - rightHair - leftArm - rightArm - feet),
      head,
      leftHair,
      rightHair,
      leftArm,
      rightArm,
      feet
    ];
    final sum = w.reduce((a, b) => a + b);
    return [for (final value in w) value / sum];
  }

  static List<double> _around(Offset p, double angle,
      {double sx = 1, double sy = 1, double dy = 0}) {
    final c = math.cos(angle), s = math.sin(angle);
    final a = c * sx, b = s * sx * 2 / 3, e = -s * sy * 3 / 2, d = c * sy;
    return [
      a,
      b,
      e,
      d,
      p.dx - a * p.dx - e * p.dy,
      p.dy - b * p.dx - d * p.dy + dy
    ];
  }

  static List<double> _mul(List<double> a, List<double> b) => [
        a[0] * b[0] + a[2] * b[1],
        a[1] * b[0] + a[3] * b[1],
        a[0] * b[2] + a[2] * b[3],
        a[1] * b[2] + a[3] * b[3],
        a[0] * b[4] + a[2] * b[5] + a[4],
        a[1] * b[4] + a[3] * b[5] + a[5]
      ];
  List<Offset> vertices(double phase, {double intensity = 1.2}) {
    final amp = intensity.clamp(0.0, 2.0), secondary = math.min(amp, 1.5);
    final p = phase * math.pi * 2, w = math.sin(p);
    final sleeping = pose == DafeiyuPose.sleep;
    final body = amp * (sleeping ? .45 : 1);
    final playful = [DafeiyuPose.happy, DafeiyuPose.pout, DafeiyuPose.praise]
        .contains(pose);
    final hop = playful ? math.max(0.0, math.sin(2 * p)) : 0.0;
    var angle = .018 * math.sin(p);
    if (pose == DafeiyuPose.thinking) angle = .030 * math.sin(p);
    if (pose == DafeiyuPose.drowsy) angle = .034 * math.sin(p);
    if (sleeping) angle = .004 * math.sin(p);
    final local = [
      _around(joints[0], (pose == DafeiyuPose.pout ? .014 : .005) * w * body,
          sx: 1 + .008 * w * body,
          sy: 1 - .012 * w * body,
          dy: (-.0075 * w - .009 * hop) * body),
      _around(joints[1], sleeping ? 0 : .012 * math.sin(p + .3) * secondary),
      _around(joints[2], angle * secondary,
          sy: 1 + (sleeping ? .001 : .006) * w * secondary,
          dy: -.003 * w * secondary),
      _around(joints[3], .024 * math.sin(p + .4) * secondary),
      _around(joints[4], -.024 * math.sin(p + 1) * secondary),
      _around(
          joints[5],
          (pose == DafeiyuPose.wave
                  ? .070 * math.sin(2 * p)
                  : pose == DafeiyuPose.praise
                      ? .050 * math.sin(2 * p)
                      : 0) *
              secondary),
      _around(
          joints[6],
          (pose == DafeiyuPose.praise ? -.050 * math.sin(2 * p) : 0) *
              secondary),
      _around(joints[7],
          pose == DafeiyuPose.happy ? .012 * math.sin(p) * secondary : 0),
    ];
    final world = <List<double>>[];
    for (var b = 0; b < 8; b++) {
      world.add(parents[b] < 0 ? local[b] : _mul(world[parents[b]], local[b]));
    }
    return [
      for (var i = 0; i < rest.length; i++) _skin(rest[i], weights[i], world)
    ];
  }

  static Offset _skin(
      Offset p, List<double> weights, List<List<double>> world) {
    var x = 0.0, y = 0.0;
    for (var b = 0; b < 8; b++) {
      final m = world[b], w = weights[b];
      x += (m[0] * p.dx + m[2] * p.dy + m[4]) * w;
      y += (m[1] * p.dx + m[3] * p.dy + m[5]) * w;
    }
    return Offset(x, y);
  }
}

class DafeiyuAvatar extends StatefulWidget {
  final DafeiyuPose pose;
  final Animation<double> motion;
  final bool reducedMotion;
  final ValueChanged<DafeiyuPose>? onPoseReady;
  const DafeiyuAvatar(
      {super.key,
      required this.pose,
      required this.motion,
      this.reducedMotion = false,
      this.onPoseReady});
  @override
  State<DafeiyuAvatar> createState() => _DafeiyuAvatarState();
}

class _DafeiyuAvatarState extends State<DafeiyuAvatar> {
  final _images = <DafeiyuPose, ui.Image>{};
  final _loading = <DafeiyuPose>{};
  late DafeiyuRig _rig;
  bool _failed = false;
  DafeiyuPose? _lastLoadedPose;
  @override
  void initState() {
    super.initState();
    _rig = DafeiyuRig(widget.pose);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load(widget.pose);
  }

  @override
  void didUpdateWidget(covariant DafeiyuAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pose != widget.pose) {
      _rig = DafeiyuRig(widget.pose);
      _failed = false;
      _load(widget.pose);
    }
  }

  Future<void> _load(DafeiyuPose pose) async {
    if (_images.containsKey(pose)) {
      _notifyReady(pose);
      return;
    }
    if (!_loading.add(pose)) return;
    ui.Codec? codec;
    try {
      final bytes = await DefaultAssetBundle.of(context).load(pose.asset);
      codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          targetWidth: 256);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _images[pose] = frame.image;
        _lastLoadedPose = pose;
      });
      _notifyReady(pose);
    } catch (_) {
      if (mounted && pose == widget.pose) setState(() => _failed = true);
    } finally {
      codec?.dispose();
      _loading.remove(pose);
    }
  }

  void _notifyReady(DafeiyuPose pose) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.pose == pose) widget.onPoseReady?.call(pose);
    });
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
    final ready = _images.containsKey(widget.pose);
    final displayedPose = ready ? widget.pose : _lastLoadedPose;
    final image = displayedPose == null ? null : _images[displayedPose];
    return Semantics(
        label: '大肥鱼，口腔备考搭子',
        image: true,
        child: Stack(fit: StackFit.expand, children: [
          if (image != null)
            CustomPaint(
                key: ValueKey('dafeiyu-rendered-${displayedPose!.name}'),
                painter: _RigPainter(
                    image,
                    ready ? _rig : DafeiyuRig(displayedPose),
                    widget.motion,
                    widget.reducedMotion),
                size: Size.infinite)
          else
            const Center(child: Icon(Icons.smart_toy_outlined)),
          if (!ready && !_failed)
            const Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                    width: 15,
                    height: 15,
                    child: Icon(Icons.hourglass_top_rounded, size: 15))),
          if (_failed)
            const Align(
                alignment: Alignment.bottomCenter,
                child: Icon(Icons.broken_image_outlined, size: 16)),
        ]));
  }
}

class _RigPainter extends CustomPainter {
  final ui.Image image;
  final DafeiyuRig rig;
  final Animation<double> motion;
  final bool reduced;
  late final _uv = [
    for (final p in DafeiyuRig.rest)
      Offset(p.dx * image.width, p.dy * image.height)
  ];
  late final _shader = ui.ImageShader(image, TileMode.clamp, TileMode.clamp,
      Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
  _RigPainter(this.image, this.rig, this.motion, this.reduced)
      : super(repaint: reduced ? null : motion);
  @override
  void paint(Canvas canvas, Size size) {
    final points =
        rig.vertices(reduced ? 0 : motion.value, intensity: reduced ? 0 : 1.2);
    final vertices = ui.Vertices(
        ui.VertexMode.triangles,
        [
          for (final p in points)
            Offset((p.dx * .88 + .06) * size.width,
                (p.dy * .88 + .06) * size.height)
        ],
        textureCoordinates: _uv,
        indices: DafeiyuRig.indices);
    canvas.drawVertices(
        vertices,
        BlendMode.src,
        Paint()
          ..shader = _shader
          ..filterQuality = FilterQuality.medium);
    vertices.dispose();
  }

  @override
  bool shouldRepaint(covariant _RigPainter old) =>
      old.image != image ||
      old.rig != rig ||
      old.reduced != reduced ||
      old.motion != motion;
}
