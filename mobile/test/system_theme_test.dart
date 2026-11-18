import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/app/theme_surfaces.dart';
import 'package:dentstudy/features/practice/session_summary.dart';
import 'package:dentstudy/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first >= second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  testWidgets('system brightness updates the library, answers and summary',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 932);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({'webWelcomeCompleted': true});
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..xiaochiEnabled = false
      ..themeColorKey = 'custom'
      ..customPrimaryKey = 'forest'
      ..customBackgroundKey = 'rose'
      ..dailyNewLimit = 1
      ..questions = [
        for (var i = 0; i < 50; i++)
          Question({
            'id': 'system-theme-$i',
            'stem': '系统深色测试题 $i',
            'subject': '口腔修复学',
            'chapter': '深色测试章节',
            'type': 'A1',
            'answer': 'A',
            'options': {'A': '正确选项', 'B': '错误选项'},
            'modes': ['考研'],
            'isDemo': false,
            'tags': <String>[],
            'explanation': '练习解析',
            'reference': '测试题',
          }),
      ];
    await tester.pumpWidget(const DentStudy());
    await tester.pumpAndSettle();

    Future<void> open(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await open(find.text('题库'));
    final track = find.byKey(const ValueKey('library-track-考研'));
    final dark = Theme.of(tester.element(track));
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor.computeLuminance(), lessThan(.05));
    expect(_contrast(dark.colorScheme.onSurface, dark.cardTheme.color!),
        greaterThan(4.5));

    await open(track);
    await open(find.text('口腔修复学'));
    await open(find.text('深色测试章节'));
    await open(find.text('开始练习'));
    await open(find.text('速刷'));
    await open(find.text('错误选项'));

    final incorrect = find.text('回答错误');
    final resultTheme = Theme.of(tester.element(incorrect));
    expect(resultTheme.brightness, Brightness.dark);
    expect(
        _contrast(tester.widget<Text>(incorrect).style!.color!,
            resultTheme.cardTheme.color!),
        greaterThan(4.5));
    expect(find.text('练习解析'), findsOneWidget);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(incorrect)).brightness, Brightness.light);
    expect(app.store.learning.attempts, hasLength(1));

    await open(find.text('完成速刷'));
    expect(find.text('完成 1 题'), findsOneWidget);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await app.store.setGlassEnabled(true);
    await tester.pumpAndSettle();
    final summary = find.byType(SessionSummary);
    expect(Theme.of(tester.element(summary)).brightness, Brightness.dark);
    final summarySurface =
        find.descendant(of: summary, matching: find.byType(StudySurface));
    expect(summarySurface, findsOneWidget);
    expect(tester.widget<StudySurface>(summarySurface).glass, isTrue);
    expect(tester.widget<StudyBackdrop>(find.byType(StudyBackdrop)).background,
        app.studyBackground(Brightness.dark));

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    final light = Theme.of(tester.element(summary));
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.primary, app.themeColors['forest']);
    expect(tester.widget<StudyBackdrop>(find.byType(StudyBackdrop)).background,
        Color.lerp(Colors.white, app.themeColors['rose'], .045));
    expect(tester.takeException(), isNull);
    await open(find.text('返回今日'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
