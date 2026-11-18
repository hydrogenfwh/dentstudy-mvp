import 'dart:convert';
import 'dart:async';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/library/library_page.dart';
import 'package:dentstudy/features/library/school_library.dart';
import 'package:dentstudy/features/library/school_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fixtureDocument(String id, String section,
        {String text = '参考资料正文', String state = 'candidate'}) =>
    {
      'id': id,
      'title': id == 'recalled' ? '2019年大医回忆资料' : '口腔修复复习资料',
      'section': section,
      'subject': '口腔修复学',
      'state': state,
      'sourceFiles': ['原始资料/$id.doc'],
      'claimedYears': section == 'recalled' ? [2019] : <int>[],
      'text': text,
      'questionIds': <String>[],
    };

SchoolLibrary fixtureLibrary() => SchoolLibrary.fromJson({
      'schools': [
        {
          'id': 'dalian-medical-university',
          'name': '大连医科大学',
          'note': '回忆整理，非官方完整试卷。',
          'documents': [
            fixtureDocument('recalled', 'recalled', state: 'recalled'),
            fixtureDocument('material', 'materials'),
            fixtureDocument('scanned', 'materials',
                text: '', state: 'needs_ocr'),
          ],
          'materialBundles': [
            {
              'id': 'fixture-prostho',
              'subject': '口腔修复学',
              'groups': [
                {
                  'id': 'notes',
                  'title': '讲义与复习笔记',
                  'documentIds': ['material']
                },
                {
                  'id': 'pending',
                  'title': '待整理资料',
                  'documentIds': ['scanned']
                },
              ],
            },
          ],
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled Dalian documents have two sections and no fabricated questions',
      () async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/school_library.json'))
            as Map<String, dynamic>;
    final library = SchoolLibrary.fromJson(raw);
    final school =
        library.schools.firstWhere((s) => s.id == 'dalian-medical-university');
    expect(school.name, '大连医科大学');
    expect(school.forSection('recalled'), hasLength(8));
    expect(school.forSection('materials'), hasLength(193));
    expect(school.materialBundles, hasLength(11));
    expect(
        school.materialBundles
            .fold<int>(0, (n, b) => n + b.sourceDocumentCount),
        195);
    final groupedIds = school.materialBundles
        .expand((b) => b.documents)
        .map((d) => d.id)
        .toList();
    expect(groupedIds.toSet(), hasLength(groupedIds.length));
    expect(groupedIds.toSet(),
        school.forSection('materials').map((d) => d.id).toSet());
    expect(school.documents.map((d) => d.id).toSet(),
        hasLength(school.documents.length));
    for (final value in ((raw['schools'] as List)
            .firstWhere((s) => (s as Map)['id'] == 'dalian-medical-university')
        as Map)['documents'] as List) {
      final document = value as Map;
      expect(document['questionIds'], isEmpty);
      expect(document['sourceVerified'], isFalse);
      expect(document['yearVerified'], isFalse);
      expect(document['sourceFiles'], isNotEmpty);
      expect(document['text'], isNot(contains('/Users/hydrogen')));
    }
    final scan = school.documents.firstWhere((d) => d.title == '20年真题');
    expect(scan.readable, isFalse);
    expect(scan.statusLabel, '待文字识别');
  });

  test('Wenzhou reading materials have explicit years and safe provenance',
      () async {
    final raw =
        jsonDecode(await rootBundle.loadString('assets/school_library.json'))
            as Map;
    final library = SchoolLibrary.fromJson(Map<String, dynamic>.from(raw));
    expect(library.schools.map((s) => s.id).toSet(),
        hasLength(library.schools.length));
    final school =
        library.schools.firstWhere((s) => s.id == 'wenzhou-medical-university');
    expect(school.name, '温州医科大学');
    expect(school.materialBundles, hasLength(10));
    expect(school.materialBundles.any((b) => b.matches('生物学宽度')), isTrue);
    expect(school.forSection('recalled'), isNotEmpty);
    final grouped = school.materialBundles
        .expand((b) => b.documents)
        .map((d) => d.id)
        .toList();
    expect(grouped.toSet(), hasLength(grouped.length));
    expect(grouped.toSet(),
        school.forSection('materials').map((d) => d.id).toSet());
    for (final d in school.documents) {
      final lecture = d.id.startsWith('WZ-M-');
      expect(d.statusLabel, lecture ? '含原资料答案' : '真题');
      expect(d.sourceAnswersReviewed, isTrue);
      expect(d.sourceLabel, lecture ? '人卫讲义' : '真题');
      expect(d.sourceFiles, [lecture ? '人卫讲义' : '真题']);
      expect(d.text, isNot(contains('/Users/')));
      expect(d.text, isNot(contains('wxid_')));
      if (d.section == 'recalled') {
        expect(d.claimedYears, hasLength(1));
        expect(d.text, isNot(contains('原资料标注：')));
      } else {
        expect(d.claimedYears, isEmpty);
      }
    }
  });

  testWidgets('Wenzhou is selectable and its recalled document opens on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    app.store.glassEnabled = false;
    final library = await tester.runAsync(() => SchoolLibrary.load());
    await tester.runAsync(() => library!.schools
        .firstWhere((s) => s.id == 'wenzhou-medical-university')
        .loadBodies());
    await tester.pumpWidget(
        MaterialApp(home: SchoolLibraryPage(loader: () async => library!)));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('school-wenzhou-medical-university')));
    await tester.pumpAndSettle();
    expect(find.text('温州医科大学'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('school-section-recalled')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('school-document-WZ-Y-2026-recalled')));
    await tester.pumpAndSettle();
    expect(find.text('来源：真题。主观题不自动判分。'), findsOneWidget);
    expect(find.textContaining('【原资料答案】'), findsNothing);
    expect(find.textContaining('PDF第'), findsNothing);
    expect(find.byKey(const ValueKey('school-answer-packs')), findsOneWidget);
    expect(find.text('开始练习'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('school-answer-packs')));
    await tester.pumpAndSettle();
    expect(find.text('口腔组织病理学'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lecture reading and merged sources do not relabel papers',
      (tester) async {
    final raw = await tester
        .runAsync(() => rootBundle.loadString('assets/school_library.json'));
    final library =
        SchoolLibrary.fromJson(jsonDecode(raw!) as Map<String, dynamic>);
    final school =
        library.schools.firstWhere((s) => s.id == 'wenzhou-medical-university');
    final bundle = school.materialBundles.first;
    final group = bundle.groups
        .firstWhere((g) => g.documents.every((d) => d.sourceLabel == '人卫讲义'));
    await tester.pumpWidget(MaterialApp(
        home: SchoolMergedReadingPage(bundle: bundle, group: group)));
    await tester.pumpAndSettle();
    expect(find.text('来源：人卫讲义。主观题不自动判分。'), findsOneWidget);
    expect(find.text('来源：真题。主观题不自动判分。'), findsNothing);
    await tester
        .tap(find.byKey(ValueKey('merged-source-${group.documents.first.id}')));
    await tester.pumpAndSettle();
    expect(find.text('人卫讲义'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
        home:
            SchoolDocumentPage(document: school.forSection('recalled').first)));
    await tester.pumpAndSettle();
    expect(find.text('来源：真题。主观题不自动判分。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'catalogue is small and reading bodies are lazy, deduplicated and retryable',
      () async {
    final encoded =
        await rootBundle.loadString('assets/school_library_index.json');
    expect(utf8.encode(encoded).length, lessThan(250000));
    final library =
        SchoolLibrary.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
    final first = library.schools.first.documents.firstWhere((d) => d.readable);
    expect(first.text, isEmpty);
    expect(first.bodyLoaded, isFalse);
    var calls = 0;
    final completed = Completer<String>();
    Future<String> reader(String path) {
      calls++;
      expect(path, first.bodyAsset);
      return completed.future;
    }

    final one = first.loadBody(reader: reader);
    final two = first.loadBody(reader: reader);
    expect(calls, 1);
    completed.complete(jsonEncode({'id': first.id, 'text': '按需加载正文'}));
    await Future.wait([one, two]);
    expect(first.bodyLoaded, isTrue);
    expect(first.text, '按需加载正文');
    final second = library.schools.first.documents
        .firstWhere((d) => d.readable && d.id != first.id);
    await expectLater(
        second.loadBody(reader: (_) async => throw StateError('network')),
        throwsStateError);
    await second.loadBody(
        reader: (_) async => jsonEncode({'id': second.id, 'text': '重试成功'}));
    expect(second.text, '重试成功');
  });

  testWidgets('a stalled school request times out instead of spinning forever',
      (tester) async {
    final stalled = Completer<SchoolLibrary>();
    await tester.pumpWidget(
        MaterialApp(home: SchoolLibraryPage(loader: () => stalled.future)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('学校资料暂未加载成功'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test('long document blocks stay bounded without splitting surrogate pairs',
      () {
    final text = '${'甲' * 1599}💐${'乙' * 3201}';
    final document = SchoolDocument.fromJson(
        fixtureDocument('long', 'materials', text: text));
    expect(document.readingBlocks.every((b) => b.length <= 1600), isTrue);
    expect(document.readingBlocks.join(), text);
    expect(
        document.readingBlocks
            .join()
            .runes
            .where((r) => r >= 0xd800 && r <= 0xdfff),
        isEmpty);
  });

  test(
      'one true-paper question stays one paragraph even beyond the old block limit',
      () {
    final data = fixtureDocument('paragraph', 'recalled',
        text: '1. 题目 ${'答案' * 1000}\n\n2. 下一题 答案');
    data['continuousQuestions'] = true;
    data['sourceLabel'] = '真题';
    final document = SchoolDocument.fromJson(data);
    expect(document.readingBlocks, hasLength(2));
    expect(document.readingBlocks.first.length, greaterThan(1600));
    expect(document.readingBlocks.every((p) => !p.contains('\n')), isTrue);
  });

  testWidgets('school sections, source reading, search and mobile navigation',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    app.store.glassEnabled = false;
    await tester.pumpWidget(MaterialApp(
        home: SchoolLibraryPage(loader: () async => fixtureLibrary())));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('school-dalian-medical-university')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('school-section-recalled')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('school-section-materials')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('school-section-recalled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('school-document-recalled')));
    await tester.pumpAndSettle();
    expect(find.text('参考资料正文'), findsOneWidget);
    expect(find.text('开始练习'), findsNothing);
    await tester.tap(find.text('查看原始来源'));
    await tester.pumpAndSettle();
    expect(find.text('原始资料/recalled.doc'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('school-section-materials')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('口腔修复学'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('school-material-group-notes')));
    await tester.pumpAndSettle();
    expect(find.text('参考资料正文'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('merged-source-material')));
    await tester.pumpAndSettle();
    expect(find.text('原始资料/material.doc'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('school-material-group-pending')));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂未加入合辑正文'), findsOneWidget);
    expect(find.text('开始练习'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('school-document-search')), '不存在的资料');
    await tester.pumpAndSettle();
    expect(find.text('暂时没有匹配的资料。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed school asset load can retry', (tester) async {
    var tries = 0;
    await tester
        .pumpWidget(MaterialApp(home: SchoolLibraryPage(loader: () async {
      if (tries++ == 0) throw StateError('fixture failure');
      return fixtureLibrary();
    })));
    await tester.pumpAndSettle();
    expect(find.text('学校资料暂未加载成功'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('大连医科大学'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('school entry is restricted to postgraduate direction',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.mode = '考研';
    app.store.questions = [];
    app.store.glassEnabled = false;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryPage(onStart: (_) async {}))));
    await tester.tap(find.byKey(const ValueKey('library-track-考研')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-school-entry')), findsOneWidget);
    await tester.tap(find.text('全部分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-track-执医')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-school-entry')), findsNothing);
    await tester.tap(find.text('全部分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-track-本科期末')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-school-entry')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
