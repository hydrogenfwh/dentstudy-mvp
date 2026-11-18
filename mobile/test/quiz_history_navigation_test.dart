import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/practice/batch_session.dart';
import 'package:dentstudy/features/practice/deep_session.dart';
import 'package:dentstudy/features/practice/practice_request.dart';
import 'package:dentstudy/features/practice/session_journal.dart';
import 'package:dentstudy/features/practice/speed_session.dart';
import 'package:dentstudy/models.dart';
import 'package:dentstudy/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Question question(int index) => Question({
      'id': 'history-$index',
      'stem': '回看测试题 $index',
      'subject': '口腔修复学',
      'chapter': '回看章节',
      'type': 'A1',
      'modes': ['考研'],
      'isDemo': false,
      'options': {
        'A': '答案 A $index',
        'B': '答案 B $index',
        'C': '答案 C $index',
        'D': '答案 D $index',
      },
      'answer': 'A',
      'explanation': '第 $index 题解析',
      'reference': '测试资料',
      'warning': '',
      'tags': <String>[],
    });

Future<void> prepareStore() async {
  SharedPreferences.setMockInitialValues({});
  app.store.prefs = await SharedPreferences.getInstance();
  app.store.token = '';
  app.store.userId = 'guest';
  app.store.mode = '考研';
  app.store.events = [];
  app.store.pending = [];
  app.store.sessions = [];
  app.store.drafts = {};
  app.store.dailyPlan = null;
  app.store.activeSessionId = null;
  app.store.dailyNewLimit = 20;
  app.store.questions = [question(0), question(1)];
}

Future<SessionJournal> openJournal(String mode) async {
  final journal = SessionJournal(
      app.store, PracticeRequest(app.store.questions, mode: mode));
  await journal.open();
  return journal;
}

Future<StudyStore> createStore([List<Question>? questions]) async {
  SharedPreferences.setMockInitialValues({});
  return StudyStore()
    ..prefs = await SharedPreferences.getInstance()
    ..questions = questions ?? [question(0), question(1)];
}

void freezeJournal(SessionJournal journal) {
  // Persistence itself is covered by SessionJournal tests. These tests only
  // exercise navigation, so prevent its periodic autosave from leaking across
  // widget tests while preserving the exact restored session data.
  journal.ticker?.cancel();
  journal.clock.stop();
  journal.closed = true;
}

void useTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all three modes keep a safe previous-question view',
      (tester) async {
    useTallViewport(tester);

    // Deep mode advances after the learner grades a question. The restored
    // state below is exactly the post-grade state: question 0 is saved and
    // question 1 remains active.
    await prepareStore();
    final deepJournal = await openJournal('deep');
    await deepJournal.capture({
      'index': 1,
      'answers': {'history-0': 'A'},
      'saved': ['history-0'],
    });
    freezeJournal(deepJournal);
    await tester.pumpWidget(MaterialApp(
        home: StudySession(
            questions: app.store.questions, journal: deepJournal)));

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('上一题'), findsOneWidget);
    await tester.tap(find.text('上一题'));
    await tester.pump();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('已作答 · 仅查看'), findsOneWidget);
    expect(find.text('答案 A 0'), findsOneWidget);
    await tester.tap(find.text('回到当前题').first);
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    // Speed mode writes a correct answer before it auto-advances, so its
    // restored post-auto-advance state has the same saved first question.
    await prepareStore();
    final speedJournal = await openJournal('speed');
    await speedJournal.capture({
      'index': 1,
      'answers': {'history-0': 'A'},
      'saved': ['history-0'],
    });
    freezeJournal(speedJournal);
    await tester.pumpWidget(MaterialApp(
        home: SpeedStudySession(
            questions: app.store.questions,
            store: app.store,
            review: false,
            journal: speedJournal)));

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('上一题'), findsOneWidget);

    await tester.tap(find.text('上一题'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('已作答 · 仅查看'), findsOneWidget);
    await tester.tap(find.text('回到当前题').first);
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    // Batch mode already moves explicitly, and keeps the same previous
    // control while the learner is still composing answers.
    await prepareStore();
    final batchJournal = await openJournal('batch');
    freezeJournal(batchJournal);
    await tester.pumpWidget(MaterialApp(
        home: BatchStudySession(
            questions: app.store.questions,
            store: app.store,
            journal: batchJournal)));

    await tester.tap(find.textContaining('答案 A 0'));
    await tester.pump();
    await tester.ensureVisible(find.text('下一题'));
    await tester.tap(find.text('下一题'));
    await tester.pump();
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.text('上一题'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.textContaining('答案 A 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('speed double taps keep the next question and count the last',
      (tester) async {
    useTallViewport(tester);
    final questions = [
      question(0),
      Question({...question(1).data, 'type': '多选题', 'answer': 'AC'}),
      question(2),
    ];
    final store = await createStore(questions);
    final journal =
        SessionJournal(store, PracticeRequest(questions, mode: 'speed'));
    await journal.open();
    await tester.pumpWidget(MaterialApp(
      home: SpeedStudySession(
        questions: questions,
        store: store,
        review: false,
        journal: journal,
      ),
    ));

    await tester.tap(find.byTooltip('收藏题目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('答案 B 0'));
    await tester.tap(find.text('答案 B 0'));
    await tester.pumpAndSettle();
    expect(find.text('回答错误'), findsOneWidget);
    expect(find.text('第 0 题解析'), findsOneWidget);
    final next = find.text('继续下一题');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tap(find.text('上一题'));
    await tester.pumpAndSettle();
    expect(find.text('已作答 · 仅查看'), findsOneWidget);
    expect(store.learning.attempts, hasLength(1));
    await tester.tap(find.text('回到当前题').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('答案 C 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('答案 A 1'));
    await tester.pumpAndSettle();
    expect(store.learning.attempts, hasLength(1));
    await tester.tap(find.text('确认多选答案'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.tap(find.text('答案 B 2'));
    await tester.pumpAndSettle();
    final finish = find.text('完成速刷');
    await tester.ensureVisible(finish);
    await tester.tap(finish);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(find.text('完成 3 题'), findsOneWidget);
    expect(find.text('复习错题 2'), findsOneWidget);
    expect(store.learning.attempts, hasLength(3));
    expect(store.learning.states['history-0']?.favorite, isTrue);
    expect(store.learning.states['history-2']?.wrong, isTrue);
    expect(store.sessions.single['eventIds'], hasLength(3));
    expect(store.drafts, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await journal.close();
  });

  testWidgets('recover the last committed speed answer into study history',
      (tester) async {
    useTallViewport(tester);
    final store = await createStore([question(0)]);
    final initial =
        SessionJournal(store, PracticeRequest(store.questions, mode: 'speed'));
    await initial.open();
    await store.add('history-0', 'review',
        {'answer': 'A', 'grade': 'mastered', 'mode': 'speed'});
    // The answer reached local storage just before the route was interrupted.
    // The draft still points at the last question, with no final record yet.
    await initial.close();
    expect(store.sessions, isEmpty);
    final journal = SessionJournal(
        store,
        PracticeRequest(store.questions,
            mode: 'speed', draft: store.drafts[initial.id]));
    await journal.open();
    await tester.pumpWidget(MaterialApp(
      home: SpeedStudySession(
          questions: store.questions,
          store: store,
          review: false,
          journal: journal),
    ));
    await tester.pumpAndSettle();
    expect(find.text('完成 1 题'), findsOneWidget);
    expect(store.sessions.single['eventIds'], hasLength(1));
    expect(store.drafts, isEmpty);
    expect(store.learning.attempts.single['correct'], isTrue);
    await tester.pumpWidget(const SizedBox());
    await journal.close();
  });

  testWidgets('batch reopens the unanswered item in a partial review draft',
      (tester) async {
    useTallViewport(tester);
    final store = await createStore();
    final journal =
        SessionJournal(store, PracticeRequest(store.questions, mode: 'batch'));
    await journal.open();
    await journal.capture({
      'index': 1,
      'reviewing': true,
      'answers': {'history-0': 'B', 'history-1': null},
      'grades': {'history-0': 'wrong', 'withdrawn': 'mastered'},
    });
    await tester.pumpWidget(MaterialApp(
      home: BatchStudySession(
          questions: store.questions, store: store, journal: journal),
    ));
    await tester.pumpAndSettle();
    expect(find.text('回看测试题 1'), findsOneWidget);
    expect(find.text('统一查看解析'), findsNothing);
    await tester.tap(find.text('答案 B 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成作答'));
    await tester.pumpAndSettle();
    expect(find.text('统一查看解析'), findsOneWidget);
    expect(store.events, isEmpty);
    await tester.ensureVisible(find.text('下一题解析'));
    await tester.tap(find.text('下一题解析'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('整批提交'));
    await tester.tap(find.text('整批提交'));
    await tester.tap(find.text('整批提交'));
    await tester.pumpAndSettle();
    expect(find.text('完成 2 题'), findsOneWidget);
    expect(store.learning.attempts, hasLength(2));
    expect(store.sessions.single['eventIds'], hasLength(2));

    await tester.pumpWidget(const SizedBox());
    await journal.close();
  });

  testWidgets('deep retries failed finalization without a new review event',
      (tester) async {
    useTallViewport(tester);
    SharedPreferences.setMockInitialValues({});
    final store = _FailFinishOnceStore()
      ..prefs = await SharedPreferences.getInstance()
      ..questions = [question(0)];
    final journal = SessionJournal(store, PracticeRequest(store.questions));
    await journal.open();
    await tester.pumpWidget(MaterialApp(
      home: StudySession(questions: store.questions, journal: journal),
    ));
    await tester.tap(find.text('答案 B 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认作答 · 查看解析'));
    await tester.pumpAndSettle();
    final finish = find.text('标记做错并完成');
    await tester.ensureVisible(finish);
    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败，请重试'), findsOneWidget);
    expect(find.text('完成 1 题'), findsNothing);
    expect(store.learning.attempts, hasLength(1));
    expect(store.drafts, hasLength(1));
    expect(store.sessions, isEmpty);

    await tester.tap(finish);
    await tester.pumpAndSettle();
    expect(find.text('完成 1 题'), findsOneWidget);
    expect(store.learning.attempts, hasLength(1));
    expect(store.sessions.single['eventIds'], hasLength(1));
    expect(store.drafts, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await journal.close();
  });

  testWidgets('timed practice resumes a partially committed old submission',
      (tester) async {
    useTallViewport(tester);
    final questions = [
      Question({...question(0).data, 'points': 2}),
      Question({...question(1).data, 'points': 1}),
    ];
    final store = await createStore(questions);
    final initial =
        SessionJournal(store, PracticeRequest(questions, exam: true));
    await initial.open();
    await initial.capture({
      'index': 1,
      'answers': {'history-0': 'A', 'history-1': 'B'},
      'deadline':
          DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
    });
    await store.add('history-1', 'review',
        {'answer': 'B', 'grade': 'wrong', 'mode': 'exam'});
    await initial.close();

    final journal = SessionJournal(
      store,
      PracticeRequest(questions, exam: true, draft: store.drafts[initial.id]),
    );
    await journal.open();
    await tester.pumpWidget(MaterialApp(
      home: StudySession(questions: questions, journal: journal, exam: true),
    ));
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('限时模考'), findsOneWidget);
    await tester.tap(find.text('交卷并分析'));
    await tester.tap(find.text('交卷并分析'));
    await tester.pumpAndSettle();
    expect(find.text('确认交卷'), findsOneWidget);
    await tester.tap(find.text('交卷'));
    await tester.pumpAndSettle();
    expect(find.text('客观题 2 / 3 分'), findsOneWidget);
    expect(store.learning.attempts, hasLength(2));
    expect(store.sessions.single['eventIds'], hasLength(2));
    expect(store.drafts, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await journal.close();
  });

  testWidgets('iOS practice edge-back restores the chosen answer on reopen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = await createStore();
    final questions = store.questions;
    late SessionJournal journal;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              journal = SessionJournal(
                store,
                PracticeRequest(questions,
                    draft: store.drafts.values.firstOrNull),
              );
              await journal.open();
              if (context.mounted) {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        StudySession(questions: questions, journal: journal),
                  ),
                );
              }
              await journal.close();
            },
            child: const Text('打开练习'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('答案 B 0'));
    await tester.pumpAndSettle();
    expect(store.drafts[journal.id]?['answers'], {'history-0': 'B'});
    expect(store.events, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(journal.clock.isRunning, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(journal.clock.isRunning, isTrue);

    await tester.dragFrom(const Offset(5, 400), const Offset(230, 0));
    await tester.pumpAndSettle();
    expect(find.text('打开练习'), findsOneWidget);
    expect(store.activeSessionId, isNull);

    await tester.tap(find.text('打开练习'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    final reveal = find.text('确认作答 · 查看解析');
    await tester.ensureVisible(reveal);
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    expect(find.text('回答错误'), findsOneWidget);
    expect(store.events, isEmpty);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('打开练习'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FailFinishOnceStore extends StudyStore {
  bool failNext = true;

  @override
  Future<void> finishSession(String id, Map<String, dynamic> summary) async {
    if (failNext) {
      failNext = false;
      throw StateError('simulated local write failure');
    }
    await super.finishSession(id, summary);
  }
}
