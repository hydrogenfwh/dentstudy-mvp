import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app/shared.dart' show teal;

class UserAvatar extends StatelessWidget {
  final String value;
  final double radius;
  final bool vip;
  const UserAvatar(
      {super.key, required this.value, this.radius = 22, this.vip = false});

  @override
  Widget build(BuildContext context) => SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: _avatar()),
        if (vip)
          Positioned(
              right: -2,
              bottom: -2,
              child: Semantics(
                  label: 'VIP 金牙标识',
                  child: Container(
                      width: radius.clamp(15, 23).toDouble(),
                      height: radius.clamp(15, 23).toDouble(),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFFC94C),
                          border: Border.all(color: Colors.white, width: 1.5),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x667A5813),
                                blurRadius: 4,
                                offset: Offset(0, 1))
                          ]),
                      child: Text('🦷',
                          style: TextStyle(
                              fontSize: radius.clamp(10, 15).toDouble(),
                              height: 1)))))
      ]));

  Widget _avatar() {
    if (value.startsWith('data:image/png;base64,')) {
      try {
        final bytes = base64Decode(value.split(',').last);
        return ClipOval(
            child: Image.memory(bytes,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback()));
      } catch (_) {/* Fall back if cached image data cannot be decoded. */}
    }
    return _fallback();
  }

  Widget _fallback() => CircleAvatar(
      radius: radius,
      backgroundColor: teal.withAlpha(20),
      child: Icon(
          switch (value) {
            'tooth' => Icons.health_and_safety_outlined,
            'science' => Icons.science_outlined,
            'leaf' => Icons.eco_outlined,
            'star' => Icons.star_outline,
            'smile' => Icons.sentiment_satisfied_alt_outlined,
            _ => Icons.auto_stories_outlined,
          },
          color: teal,
          size: radius));
}
