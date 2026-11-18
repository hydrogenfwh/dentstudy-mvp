import 'dart:convert';

import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/practice/practice_widgets.dart';
import 'package:dentstudy/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('章节速刷、错题回看、末题结算和题本订正', (tester) async {
    // Exercise native preferences under a test-only namespace.
    SharedPreferences.setPrefix('dentstudy.practiceTest.');
    final prefs = await SharedPreferences.getInstance();
    final questions = List.generate(
        50,
        (i) => Question({
              'id': 'qa-$i',
              'stem': '练习流程测试题 $i',
              'subject': '口腔修复学',
              'chapter': '测试章节',
              'modes': ['考研'],
              'type': i == 0 ? '简答题' : 'A1',
              'answer': i == 0 ? null : 'A',
              'options': i == 0 ? <String, String>{} : {'A': '甲', 'B': '乙'},
              'explanation': '流程测试解析 $i',
              'warning': '',
              'reference': '软件测试',
              'isDemo': false,
              'tags': <String>[],
            }));
    app.store
      ..prefs = prefs
      ..questions = questions
      ..dailyNewLimit = 2
      ..xiaochiEnabled = false;
    // Start with the real home, chapter picker, store and native persistence.
    await tester.pumpWidget(const DentStudy());
    await tester.pumpAndSettle();
    Future<void> tapText(String label) async {
      final target = find.text(label).first;
      if (target.evaluate().isEmpty) {
        final lists = find.byType(ListView).hitTestable();
        await tester.scrollUntilVisible(target, 180,
            scrollable: find
                .descendant(of: lists.last, matching: find.byType(Scrollable))
                .first);
      }
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> choose(String letter) async {
      final target = find.widgetWithText(PracticeOption, letter);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-track-考研')));
    await tester.pumpAndSettle();
    await tapText('口腔修复学');
    await tapText('测试章节');
    await tapText('开始练习');
    await tapText('速刷');
    expect(find.text('1 / 2'), findsOneWidget);
    await choose('B');
    expect(app.store.learning.states['qa-1']?.wrong, true);
    await tapText('继续下一题');
    await tapText('上一题');
    expect(find.text('流程测试解析 1'), findsOneWidget);
    await tapText('回到当前题');
    await choose('A');
    expect(find.text('完成 2 题'), findsOneWidget);
    expect(find.textContaining('50%'), findsWidgets);
    expect(app.store.learning.attempts.length, 2);
    await tapText('返回今日');
    await tester.tap(find.byIcon(Icons.bookmarks_outlined));
    await tester.pumpAndSettle();
    await tapText('练习 1 题 · 预计 2 分钟');
    await choose('A');
    await tapText('确认作答 · 查看解析');
    await tapText('完全掌握');
    expect(find.text('完成 1 题'), findsOneWidget);
    final saved = jsonDecode(prefs.getString('account:guest')!) as Map;
    expect(
        (saved['events'] as List)
            .where((e) => e['kind'] == 'review')
            .map((e) => e['questionId']),
        ['qa-1', 'qa-2', 'qa-1']);
    expect(saved['sessions'], hasLength(2));
    expect(saved['drafts'], isEmpty);
  });
}
