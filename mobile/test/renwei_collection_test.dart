import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/library/catalog.dart';
import 'package:dentstudy/features/library/library_page.dart';
import 'package:dentstudy/features/library/material_collection_page.dart';
import 'package:dentstudy/features/practice/batch_session.dart';
import 'package:dentstudy/features/practice/deep_session.dart';
import 'package:dentstudy/features/practice/practice_request.dart';
import 'package:dentstudy/features/practice/session_journal.dart';
import 'package:dentstudy/features/practice/speed_session.dart';
import 'package:dentstudy/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Question fixture(int i, {bool renwei = true, bool multiple = false}) =>
    Question({
      'id': 'renwei-test-$i',
      'subject': '口腔颌面外科学',
      'chapter': '四、牙种植术',
      'chapterByMode': {'执医': '四、牙种植术', '考研': '第五章 口腔种植外科'},
      'stem': '人卫软件测试题 $i',
      'type': multiple ? '多选题' : 'A1',
      'modes': ['执医', '考研'],
      'collection': renwei ? '人卫练习题' : '其他资料',
      'options': {'A': '选项甲', 'B': '选项乙', 'C': '选项丙'},
      'answer': multiple ? 'AC' : 'A',
      'explanation': '原资料未提供解析。',
      'explanationStatus': 'missing',
      'reference': '测试资料',
      'warning': '',
      'tags': <String>[],
      'isDemo': false,
      'sourceType': renwei ? 'user_material' : 'mock',
      'paperId': renwei ? 'test-renwei' : 'test-pending',
      'paperName': renwei ? '人卫练习题' : '未标年份测试资料',
    });

Future<void> prepare(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  app.store.prefs = await SharedPreferences.getInstance();
  app.store.userId = 'guest';
  app.store.token = '';
  app.store.mode = '考研';
  app.store.questions = [
    for (var i = 0; i < 50; i++) fixture(i),
    fixture(50, renwei: false),
  ];
  app.store.events = [];
  app.store.pending = [];
  app.store.sessions = [];
  app.store.drafts = {};
  app.store.activeSessionId = null;
  app.store.glassEnabled = false;
  // Initialize the singleton's persistence queue in this test's async zone.
  await app.store.saveDraft({'id': 'renwei-fixture-setup'});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Renwei entries, scoped chapters and all three multi-choice modes',
      (tester) async {
    await prepare(tester);
    final catalog = QuestionCatalog(app.store.questions, '考研');
    expect(catalog.material('口腔颌面外科学'), hasLength(51));
    expect(catalog.material('口腔颌面外科学').map((q) => q.chapter).toSet(),
        {'第五章 口腔种植外科'});
    expect(
        QuestionCatalog(app.store.questions, '执医')
            .material('口腔颌面外科学')
            .first
            .chapter,
        '四、牙种植术');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryPage(onStart: (_) async {}))));
    await tester.tap(find.byKey(const ValueKey('library-track-考研')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('renwei-entry-考研')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('renwei-entry-考研')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('口腔颌面外科学'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第五章 口腔种植外科'));
    await tester.pumpAndSettle();
    expect(find.text('50 题'), findsOneWidget);
    expect(find.text('开始练习'), findsOneWidget);
    expect(find.byType(MaterialCollectionPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryPage(onStart: (_) async {}))));
    await tester.tap(find.byKey(const ValueKey('library-track-执医')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('真题/模拟题'));
    await tester.pumpAndSettle();
    final pendingY = tester.getTopLeft(find.text('未标年份资料')).dy;
    final renweiY =
        tester.getTopLeft(find.byKey(const ValueKey('renwei-entry-执医'))).dy;
    expect(renweiY, greaterThan(pendingY));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    for (final mode in ['deep', 'batch', 'speed']) {
      await prepare(tester);
      app.store.questions = [fixture(1, multiple: true), fixture(2)];
      final request = PracticeRequest(app.store.questions, mode: mode);
      final journal = SessionJournal(app.store, request);
      await journal.open();
      journal.ticker?.cancel();
      journal.clock.stop();
      final Widget session = switch (mode) {
        'deep' =>
          StudySession(questions: app.store.questions, journal: journal),
        'batch' => BatchStudySession(
            questions: app.store.questions, store: app.store, journal: journal),
        _ => SpeedStudySession(
            questions: app.store.questions,
            store: app.store,
            review: false,
            journal: journal),
      };
      await tester.pumpWidget(MaterialApp(home: session));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选项丙'));
      await tester.tap(find.text('选项甲'));
      await tester.pumpAndSettle();
      expect((journal.data['answers'] as Map)['renwei-test-1'], 'AC');
      if (mode == 'speed') {
        await tester.tap(find.text('确认多选答案'));
        await tester.pumpAndSettle();
        expect(app.store.events.last['value']['answer'], 'AC');
        expect(app.store.events.last['value']['grade'], 'mastered');
      } else if (mode == 'deep') {
        await tester.tap(find.text('确认作答 · 查看解析'));
        await tester.pumpAndSettle();
        expect(find.text('回答正确，再确认掌握度'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await journal.close();
    }
  });
}
