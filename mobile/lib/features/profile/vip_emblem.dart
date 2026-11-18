import 'package:flutter/material.dart';

/// The supplied black-and-gold tooth is rendered directly, without an extra
/// circular plate, border or shadow. Its transparent source keeps it crisp at
/// both the small avatar corner size and the larger membership entry size.
class VipEmblem extends StatelessWidget {
  final double size;
  final String semanticLabel;
  const VipEmblem(
      {super.key, required this.size, this.semanticLabel = 'VIP 会员标识'});

  @override
  Widget build(BuildContext context) => Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
          width: size,
          height: size,
          child: Image.asset('assets/vip-tooth-gold.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true)));
}
