import 'package:flutter/material.dart';

/// A shared, non-interactive upper-right unread marker for both entry points.
class UnreadDot extends StatelessWidget {
  final Widget child;
  final bool visible;
  final Key? dotKey;
  const UnreadDot(
      {super.key, required this.child, required this.visible, this.dotKey});

  @override
  Widget build(BuildContext context) =>
      Stack(clipBehavior: Clip.none, children: [
        child,
        if (visible)
          Positioned(
              top: -3,
              right: -3,
              child: IgnorePointer(
                  child: Semantics(
                      label: '有未读消息',
                      child: Container(
                          key: dotKey,
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle)))))
      ]);
}
