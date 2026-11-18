import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/shared.dart';

String get stoneName => tr('羟基磷灰石');

const _stonePraises = [
  '恭喜',
  '真棒',
  '真厉害',
  '再接再厉',
  '今天也在发光',
];

String randomStonePraise([Random? random]) => tr(
    _stonePraises[(random ?? Random()).nextInt(_stonePraises.length)]);

class StoneCoinIcon extends StatelessWidget {
  final double size;

  const StoneCoinIcon({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) => Image.asset('assets/hydroxyapatite.png',
      width: size, height: size, fit: BoxFit.contain, semanticLabel: stoneName);
}

/// One consistent, compact celebration for every positive stone reward.
class StoneRewardNotice extends StatelessWidget {
  final int amount;
  final String praise;
  final bool floating;

  const StoneRewardNotice({
    super.key,
    required this.amount,
    required this.praise,
    this.floating = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: true,
      label: '$praise，获得 $amount 颗$stoneName',
      child: Container(
          width: floating ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
              color: const Color(0xfffff6d9),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: const Color(0xffd9a42a).withAlpha(110))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.local_florist_outlined,
                color: Color(0xffc98d1f), size: 20, semanticLabel: '恭喜'),
            const SizedBox(width: 5),
            const StoneCoinIcon(size: 25),
            const SizedBox(width: 7),
            Flexible(
                child: Text(usesEnglish ? '$praise · +$amount!' : '$praise，+$amount！',
                    style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14))),
          ])));
}
