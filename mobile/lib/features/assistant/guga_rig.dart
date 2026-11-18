import 'dart:math' as math;
import 'dart:ui';

enum GugaPose { idle, pet, sleep, praise, thinking, answer, drag }

/// Preserve proportions while matching pet's height and sleeping Guga's
/// head-to-toe length to the standing stage height.
Rect gugaArtworkRect(Size image, Rect stage, GugaPose pose) {
  final scale =
      math.min(stage.width / image.width, stage.height / image.height);
  var width = image.width * scale;
  var height = image.height * scale;
  final adjustment = switch (pose) {
    GugaPose.pet => stage.height / height,
    GugaPose.sleep => stage.height / width,
    _ => 1.0,
  };
  width *= adjustment;
  height *= adjustment;
  return Rect.fromCenter(center: stage.center, width: width, height: height);
}

/// Parameters for a small, periodic 2D skeletal rig. Angles are radians;
/// translations are relative to the illustration. No time-dependent random
/// values are used, so the last frame always joins the first frame exactly.
class GugaRigFrame {
  final double rootAngle, rootY, headAngle, leftWing, rightWing, breathing;
  final double leftFoot, rightFoot, footLift, softFlanks;
  const GugaRigFrame(
      {this.rootAngle = 0,
      this.rootY = 0,
      this.headAngle = 0,
      this.leftWing = 0,
      this.rightWing = 0,
      this.breathing = 0,
      this.leftFoot = 0,
      this.rightFoot = 0,
      this.footLift = 0,
      this.softFlanks = 0});

  static GugaRigFrame sample(GugaPose pose, double progress,
      {bool reduced = false}) {
    if (reduced) return const GugaRigFrame();
    final t = progress * 2 * math.pi;
    final slow = math.sin(t);
    final follow = math.sin(t - .55);
    final twice = math.sin(2 * t);
    switch (pose) {
      case GugaPose.idle:
        return GugaRigFrame(
            rootAngle: .014 * slow,
            rootY: -.003 * (1 - math.cos(t)),
            headAngle: -.012 * follow,
            rightWing: .085 * math.sin(2 * t),
            breathing: .005 * slow);
      case GugaPose.pet:
        return GugaRigFrame(
            rootAngle: .017 * slow,
            headAngle: -.025 * follow,
            leftWing: .025 * slow,
            rightWing: -.025 * slow,
            breathing: .005 * slow);
      case GugaPose.sleep:
        return GugaRigFrame(breathing: .014 * slow);
      case GugaPose.praise:
        // A single beat drives both independently drawn wings and feet.
        final (beat, airborne) = _praiseBeat(progress);
        final landing = _praiseLanding(progress);
        return GugaRigFrame(
            rootY: _praiseBounce(progress),
            leftWing: .24 * beat,
            rightWing: .24 * beat,
            leftFoot: .16 * beat,
            rightFoot: -.16 * beat,
            footLift: -.008 * airborne,
            softFlanks: .10 * landing);
      case GugaPose.thinking:
        return GugaRigFrame(
            rootAngle: .009 * slow,
            headAngle: .025 * follow,
            leftWing: .018 * slow,
            rightWing: -.018 * slow,
            breathing: .004 * slow);
      case GugaPose.answer:
        return GugaRigFrame(
            rootAngle: .012 * slow,
            headAngle: .016 * follow,
            leftWing: .045 * slow,
            rightWing: -.04 * follow);
      case GugaPose.drag:
        return GugaRigFrame(
            rootAngle: .045 * slow,
            rootY: .006 * twice,
            headAngle: -.024 * follow,
            leftWing: .09 * twice,
            rightWing: -.09 * twice);
    }
  }
}

// Whole-character anticipation, a jump, landing and a smaller settling bounce.
// Hermite tangents carry velocity across the jump and landing; the torso
// itself is never scaled.
double _praiseBounce(double progress) {
  const keys = <(double, double, double)>[
    (0, 0, 0),
    (.12, .005, 0),
    (.25, -.026, -.20),
    (.40, -.045, 0),
    (.57, 0, .15),
    (.63, .005, 0),
    (.76, -.022, 0),
    (.89, 0, .04),
    (1, 0, 0),
  ];
  final p = progress.clamp(0.0, 1.0);
  for (var i = 1; i < keys.length; i++) {
    final (end, to, endVelocity) = keys[i];
    if (p <= end) {
      final (start, from, startVelocity) = keys[i - 1];
      final span = end - start;
      final u = (p - start) / span;
      final u2 = u * u, u3 = u2 * u;
      return (2 * u3 - 3 * u2 + 1) * from +
          (u3 - 2 * u2 + u) * span * startVelocity +
          (-2 * u3 + 3 * u2) * to +
          (u3 - u2) * span * endVelocity;
    }
  }
  return 0;
}

(double, double) _praiseBeat(double progress) {
  final p = progress.clamp(0.0, 1.0);
  if (p >= .12 && p <= .57) {
    final u = (p - .12) / .45;
    final envelope = math.sin(math.pi * u);
    return (math.sin(4 * math.pi * u) * envelope, envelope);
  }
  if (p >= .63 && p <= .89) {
    final u = (p - .63) / .26;
    final envelope = math.sin(math.pi * u);
    return (math.sin(2 * math.pi * u) * envelope, envelope);
  }
  return (0, 0);
}

double _praiseLanding(double progress) {
  double pulse(double center, double radius) {
    final x = ((progress - center).abs() / radius).clamp(0.0, 1.0);
    return (1 - x) * (1 - x) * (1 + 2 * x);
  }

  return pulse(.61, .09) + .5 * pulse(.91, .07);
}

/// Rotate in image pixels, not normalised UV coordinates; this keeps the face
/// rigid even when the image and screen have different aspect ratios.
Offset gugaRotate(Offset p, Offset pivot, double angle, double aspect) {
  final dx = (p.dx - pivot.dx) * aspect;
  final dy = p.dy - pivot.dy;
  final c = math.cos(angle), s = math.sin(angle);
  return Offset(
      pivot.dx + (dx * c - dy * s) / aspect, pivot.dy + dx * s + dy * c);
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

Offset gugaSkinPoint(
    Offset p, GugaPose pose, GugaRigFrame frame, double aspect) {
  if (pose == GugaPose.sleep) {
    final dx = (p.dx - .65) / .24, dy = (p.dy - .58) / .30;
    final weight = math.exp(-dx * dx - dy * dy);
    return Offset(p.dx, p.dy - frame.breathing * weight);
  }
  // The head is a rigid bone above the collar, with a short smooth neck
  // blend. Wing weights start below it, so they never pull the face or hood.
  final headWeight = 1 - _smooth(.44, .52, p.dy);
  final head = gugaRotate(p, const Offset(.5, .47), frame.headAngle, aspect);
  var result = Offset.lerp(p, head, headWeight)!;
  if (pose == GugaPose.praise) {
    // Keep the face and the white belly rigid. Only the outside of the suit
    // near the hips yields subtly after landing.
    final flank = (1 - _smooth(.30, .36, p.dx)) + _smooth(.64, .70, p.dx);
    final vertical = _smooth(.58, .68, p.dy) * (1 - _smooth(.81, .86, p.dy));
    return result +
        Offset((p.dx - .5) * frame.softFlanks * flank * vertical, 0);
  }
  final belowShoulder = _smooth(.47, .57, p.dy);
  // These illustrations share a single mesh. Restrict the wing bones to the
  // outer shoulder region, excluding the belly and the whole lower body.
  final fixedTorso = pose == GugaPose.answer ||
      pose == GugaPose.drag ||
      pose == GugaPose.praise;
  final localWing = fixedTorso ? 1 - _smooth(.60, .70, p.dy) : 1.0;
  final leftWeight =
      (1 - _smooth(fixedTorso ? .20 : .28, fixedTorso ? .30 : .43, p.dx)) *
          belowShoulder *
          localWing;
  final rightWeight =
      _smooth(fixedTorso ? .70 : .57, fixedTorso ? .80 : .72, p.dx) *
          belowShoulder *
          localWing;
  // Skin wing tips continuously into the original image. Cutting the flat
  // artwork into separate moving pieces left visible seams beside the hair.
  // The outer mask excludes the face, belly and lower body.
  final l = gugaRotate(p, const Offset(.35, .50), frame.leftWing, aspect);
  // Idle's raised wing is a separate drawn layer, not part of this mesh.
  final r = gugaRotate(p, const Offset(.65, .50),
      pose == GugaPose.idle ? 0 : frame.rightWing, aspect);
  result += (l - p) * leftWeight + (r - p) * rightWeight;
  final dx = (p.dx - .5) / .22, dy = (p.dy - .69) / .22;
  final belly = math.exp(-dx * dx - dy * dy);
  result += Offset((p.dx - .5) * frame.breathing * belly,
      (p.dy - .69) * frame.breathing * belly);
  return result;
}
