import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:dentstudy/features/assistant/guga_rig.dart';

void main() {
  test('pet height and sleep length match the standing character', () {
    const stage = Rect.fromLTWH(0, 0, 114.5, 137.4);
    final idle = gugaArtworkRect(const Size(533, 640), stage, GugaPose.idle);
    final pet = gugaArtworkRect(const Size(585, 640), stage, GugaPose.pet);
    final sleep = gugaArtworkRect(const Size(640, 320), stage, GugaPose.sleep);
    expect(pet.height, closeTo(idle.height, .001));
    expect(sleep.width, closeTo(idle.height, .001));
    expect(sleep.width / sleep.height, closeTo(2, .0001));
  });
  test('every motion joins its loop without a position or angle jump', () {
    for (final pose in GugaPose.values) {
      final start = GugaRigFrame.sample(pose, 0);
      final end = GugaRigFrame.sample(pose, 1);
      for (final pair in [
        [start.rootAngle, end.rootAngle],
        [start.rootY, end.rootY],
        [start.headAngle, end.headAngle],
        [start.leftWing, end.leftWing],
        [start.rightWing, end.rightWing],
        [start.breathing, end.breathing],
        [start.leftFoot, end.leftFoot],
        [start.rightFoot, end.rightFoot],
        [start.footLift, end.footLift],
        [start.softFlanks, end.softFlanks],
      ]) {
        expect(pair[0], closeTo(pair[1], 1e-10), reason: pose.name);
      }
    }
  });

  test('idle wing cannot deform the face or torso mesh', () {
    const p = Offset(.65, .66);
    const face = Offset(.63, .25);
    const still = GugaRigFrame();
    const waving = GugaRigFrame(rightWing: .3);
    for (final point in [p, face]) {
      expect(gugaSkinPoint(point, GugaPose.idle, waving, .83),
          gugaSkinPoint(point, GugaPose.idle, still, .83));
    }
  });

  test('head remains rigid and independent of both wing bones', () {
    const a = Offset(.36, .22), b = Offset(.64, .22);
    const frame = GugaRigFrame(headAngle: .08, leftWing: .4, rightWing: -.4);
    final x = gugaSkinPoint(a, GugaPose.drag, frame, 1);
    final y = gugaSkinPoint(b, GugaPose.drag, frame, 1);
    expect((x - y).distance, closeTo((a - b).distance, 1e-10));
    expect(x,
        gugaSkinPoint(a, GugaPose.drag, const GugaRigFrame(headAngle: .08), 1));
  });

  test('answer, praise and drag keep the belly and lower body fixed', () {
    for (final pose in [GugaPose.answer, GugaPose.drag, GugaPose.praise]) {
      for (var step = 0; step <= 20; step++) {
        final frame = GugaRigFrame.sample(pose, step / 20);
        expect(frame.breathing, 0,
            reason: '${pose.name} must not scale the torso');
        for (final y in [.70, .75, .82, .90, 1.0]) {
          for (final x in (pose == GugaPose.praise
              ? [.36, .40, .50, .60, .64]
              : [.30, .35, .50, .65, .70])) {
            final point = Offset(x, y);
            expect(gugaSkinPoint(point, pose, frame, .87), point,
                reason: '${pose.name} at $point, phase $step');
          }
        }
        for (final y in [.52, .55, .60, .65, .69]) {
          for (final x in (pose == GugaPose.praise
              ? [.36, .40, .50, .60, .64]
              : [.30, .35, .40, .50, .60, .65, .70])) {
            final point = Offset(x, y);
            expect(gugaSkinPoint(point, pose, frame, .87), point,
                reason: '${pose.name} belly at $point, phase $step');
          }
        }
      }
    }
  });

  test('answer and drag still move wings', () {
    for (final pose in [GugaPose.answer, GugaPose.drag]) {
      final moving = GugaRigFrame.sample(pose, .125);
      const point = Offset(.23, .58);
      expect(gugaSkinPoint(point, pose, moving, .87), isNot(point),
          reason: pose.name);
    }
  });

  test('praise wing bones do not influence the face or body', () {
    const still = GugaRigFrame();
    const flapping = GugaRigFrame(leftWing: .09, rightWing: -.09);
    for (final point in [
      const Offset(.30, .42),
      const Offset(.30, .58),
      const Offset(.5, .7),
      const Offset(.70, .42)
    ]) {
      expect(gugaSkinPoint(point, GugaPose.praise, flapping, .86),
          gugaSkinPoint(point, GugaPose.praise, still, .86));
    }
  });

  test('praise wing bones never deform the shared body artwork', () {
    const point = Offset(.17, .42);
    expect(
        gugaSkinPoint(
            point, GugaPose.praise, const GugaRigFrame(leftWing: .09), .86),
        gugaSkinPoint(point, GugaPose.praise, const GugaRigFrame(), .86));
  });

  test('praise jumps and settles without scaling', () {
    expect(
        GugaRigFrame.sample(GugaPose.praise, .40).rootY, closeTo(-.045, 1e-9));
    expect(GugaRigFrame.sample(GugaPose.praise, .63).rootY, greaterThan(0));
    expect(
        GugaRigFrame.sample(GugaPose.praise, .76).rootY, closeTo(-.022, 1e-9));
    expect(GugaRigFrame.sample(GugaPose.praise, 1).rootY, 0);
  });

  test('praise synchronizes both hands and feet without shaking the head', () {
    final inFlight = GugaRigFrame.sample(GugaPose.praise, .20);
    final grounded = GugaRigFrame.sample(GugaPose.praise, .02);
    expect(inFlight.rootY, lessThan(0));
    expect(inFlight.headAngle, 0);
    expect(inFlight.rootAngle, 0);
    expect(inFlight.leftWing, isNot(0));
    expect(inFlight.leftWing, inFlight.rightWing);
    expect(inFlight.leftFoot, -inFlight.rightFoot);
    expect(inFlight.leftWing.sign, inFlight.leftFoot.sign);
    expect(grounded.leftWing, 0);
    expect(grounded.rightFoot, 0);
  });

  test('landing gently yields the dark flank without resizing the belly', () {
    final landing = GugaRigFrame.sample(GugaPose.praise, .61);
    final still = GugaRigFrame.sample(GugaPose.praise, .02);
    const flank = Offset(.30, .75), belly = Offset(.50, .75);
    expect(gugaSkinPoint(flank, GugaPose.praise, landing, .86).dx,
        lessThan(gugaSkinPoint(flank, GugaPose.praise, still, .86).dx));
    expect(gugaSkinPoint(belly, GugaPose.praise, landing, .86),
        gugaSkinPoint(belly, GugaPose.praise, still, .86));
  });

  test('reduced motion stops every bone', () {
    for (final pose in GugaPose.values) {
      final frame = GugaRigFrame.sample(pose, .37, reduced: true);
      expect([
        frame.rootAngle,
        frame.rootY,
        frame.headAngle,
        frame.leftWing,
        frame.rightWing,
        frame.breathing
      ], everyElement(0));
    }
  });
}
