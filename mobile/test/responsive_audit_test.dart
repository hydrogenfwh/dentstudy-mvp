import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/practice/deep_session.dart';
import 'package:dentstudy/features/practice/practice_request.dart';
import 'package:dentstudy/features/practice/session_journal.dart';
import 'package:dentstudy/models.dart';
import 'package:dentstudy/store.dart';

Question _longQuestion(int index, {required bool illustrated}) => Question({
      'id': 'practice-layout-$index',
      'stem': index == 0 ? '长题干。' * 20 : '下一道题的题干',
      'subject': '口腔修复学',
      'chapter': '需要换行显示的章节标题',
      'type': '多选题',
      'modes': ['考研'],
      'answer': 'AC',
      'options': {
        'A': '第一项的长内容。' * 12,
        'B': '第二项的内容',
        'C': '第三项的内容',
      },
      'explanation': '需要滚动才能完整阅读的解析。' * 35,
      'reference': '界面回归测试',
      'tags': <String>[],
      if (index == 0 && illustrated) ...{
        'sharedStem': '共用题干',
        'sharedStemImages': ['assets/hydroxyapatite.png'],
        'stemImages': ['assets/hydroxyapatite.png'],
        'optionImages': {
          'B': ['assets/hydroxyapatite.png'],
        },
        'explanationImages': ['assets/hydroxyapatite.png'],
      },
    });

Future<SessionJournal> _openDeepPractice(WidgetTester tester,
    {bool illustrated = false}) async {
  SharedPreferences.setMockInitialValues({});
  final store = StudyStore()
    ..prefs = await SharedPreferences.getInstance()
    ..questions = [
      _longQuestion(0, illustrated: illustrated),
      _longQuestion(1, illustrated: illustrated),
    ];
  final journal = SessionJournal(store, PracticeRequest(store.questions));
  await journal.open();
  journal.ticker?.cancel();
  addTearDown(() => WidgetsBinding.instance.removeObserver(journal));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, platform: TargetPlatform.iOS),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: StudySession(questions: store.questions, journal: journal),
  ));
  await tester.pumpAndSettle();
  return journal;
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    for (final mode in ['考研', '执医']) {
      testWidgets('five guest tabs fit $size in $mode with 130 percent text',
          (tester) async {
        final originalErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          FlutterError.dumpErrorToConsole(details, forceReport: true);
          originalErrorHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalErrorHandler);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        app.store
          ..prefs = await SharedPreferences.getInstance()
          ..token = ''
          ..userId = 'guest'
          ..email = ''
          ..mode = mode
          ..glassEnabled = false
          ..xiaochiEnabled = false
          ..events = []
          ..pending = []
          ..sessions = []
          ..drafts = {}
          ..dailyPlan = null
          ..activeSessionId = null
          ..questions = List.generate(
              60,
              (index) => Question({
                    'id': 'responsive-$index',
                    'stem': '布局回归题 $index',
                    'subject': '口腔修复学',
                    'chapter': '第一章',
                    'modes': ['考研', '执医'],
                    'type': 'A1',
                    'options': {'A': '甲', 'B': '乙'},
                    'answer': 'A',
                    'explanation': '仅用于布局回归',
                    'isDemo': false,
                  }));
        for (var tab = 0; tab < 5; tab++) {
          await tester.pumpWidget(MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: child!),
              home: Home(key: ValueKey('$mode-$tab'), initialTab: tab)));
          await tester.pumpAndSettle();
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(tester.takeException(), isNull,
              reason: '$mode / tab $tab / $size');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      });
    }
  }

  testWidgets(
      'long illustrated practice at 200% text shows selection and resets scroll on next',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    final journal = await _openDeepPractice(tester, illustrated: true);
    await tester.runAsync(() => precacheImage(
          const AssetImage('assets/hydroxyapatite.png'),
          tester.element(find.byType(StudySession)),
        ));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2').hitTestable(), findsOneWidget);

    final picked = find.text('第二项的内容');
    await tester.scrollUntilVisible(picked.hitTestable(), 260);
    await tester.pumpAndSettle();
    await tester.tap(picked);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is Image && widget.semanticLabel == '题目配图'),
        findsWidgets);
    final submit = find.text('确认作答 · 查看解析');
    await tester.scrollUntilVisible(submit.hitTestable(), 240);
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getCenter(submit).dy, lessThan(568 - 34));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(picked.hitTestable(), -180);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('所选答案错误')), findsOneWidget);

    final next = find.text('标记做错并继续');
    await tester.scrollUntilVisible(next.hitTestable(), 260);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2').hitTestable(), findsOneWidget);
    expect(find.text('下一道题的题干').hitTestable(), findsOneWidget);
    expect(journal.store.learning.attempts.single['correct'], isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await journal.close();
  });

  testWidgets('practice note remains editable with landscape keyboard insets',
      (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(left: 30, right: 30);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    final journal = await _openDeepPractice(tester);
    final note = find.byTooltip('题目笔记');
    await tester.scrollUntilVisible(note.hitTestable(), 225);
    await tester.pumpAndSettle();
    expect(tester.getSize(note).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(note).height, greaterThanOrEqualTo(48));
    await tester.tap(note);
    await tester.pumpAndSettle();

    final field = find.byType(TextFormField);
    await tester.enterText(field, '保留这条笔记');
    tester.view.viewInsets = const FakeViewPadding(bottom: 132);
    await tester.pumpAndSettle();
    final save = find.text('保存');
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(save).dy, lessThan(320 - 132));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(journal.store.learning.states['practice-layout-0']?.note, '保留这条笔记');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await journal.close();
  });
}
