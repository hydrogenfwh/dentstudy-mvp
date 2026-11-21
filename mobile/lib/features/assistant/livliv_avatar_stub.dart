import 'package:flutter/material.dart';
import 'dafeiyu_avatar.dart';

// Tests and non-web builds do not create an embedded web player.
class LivLivAvatar extends StatelessWidget {
  final DafeiyuPose pose;
  final String? expression;
  final int interactionSerial;
  final ValueChanged<DafeiyuPose> onPoseReady;
  const LivLivAvatar(
      {super.key,
      required this.pose,
      this.expression,
      required this.interactionSerial,
      required this.onPoseReady});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
