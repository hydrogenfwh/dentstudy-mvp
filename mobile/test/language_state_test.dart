import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dentstudy/app/language_selector.dart';
import 'package:dentstudy/app/language_state.dart';

void main() {
  setUp(() => setAppLanguage('zh'));

  test('translates owned application labels when English is selected', () {
    setAppLanguage('en');

    expect(tr('登录 / 注册'), 'Sign in / Register');
    expect(tr('今日'), 'Today');
    expect(tr('连续学习 12 天'), '12-day learning streak');
    expect(tr('玻璃质感'), 'Glass effect');
    expect(tr('每日签到'), 'Daily check-in');
    expect(tr('搜索题目'), 'Search questions');
    expect(tr('我的石头小金库'), 'My token wallet');
    expect(tr('当前 88 颗'), 'Current balance: 88 tokens');
    expect(tr('使用 345 颗兑换'), 'Redeem with 345 tokens');
    expect(tr('口腔颌面外科学'), 'Oral and Maxillofacial Surgery');
    expect(tr('18231 道可练 · 17 个学科'), '18231 questions · 17 subjects');
    expect(tr('本机 21327 题 · 执医可练 17117 题；断网可答题'),
        '21327 questions on this device · 17117 available for Medical practitioner exam · available offline');
    expect(tr('还没有错题'), 'No incorrect yet');
    expect(tr('首月 ¥1；之后每月 ¥6.9，手动续费，不自动扣款'),
        'First month ¥1; ¥6.9 per month thereafter. Manual renewal; no automatic charge.');
    expect(tr('每月 ¥6.9，手动续费，不自动扣款'),
        '¥6.9 per month. Manual renewal; no automatic charge.');
  });

  test('leaves question-bank and user-authored text in its source language',
      () {
    setAppLanguage('en');

    expect(tr('牙髓炎最常见的致病菌是什么？'), '牙髓炎最常见的致病菌是什么？');
    expect(tr('同学你好，明天一起复习吗？'), '同学你好，明天一起复习吗？');
  });

  test('returns the source text in Chinese mode', () {
    expect(tr('登录 / 注册'), '登录 / 注册');
  });

  testWidgets('language selector exposes both choices before sign-in',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LanguageSelector(
                value: 'zh', onChanged: (value) => selected = value))));

    await tester.tap(find.text('English'));
    expect(selected, 'en');
  });
}
