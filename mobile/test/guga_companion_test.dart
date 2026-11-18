import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/assistant/dafeiyu_dialogue.dart';
import 'package:dentstudy/features/assistant/guga_avatar.dart';
import 'package:dentstudy/features/assistant/guga_dialogue.dart';
import 'package:dentstudy/features/assistant/xiaochi_assistant.dart';
import 'package:dentstudy/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..userId = 'guest' ..email = '' ..token = '' ..baseUrl = ''
      ..companionAppearance = 'guga' ..xiaochiEnabled = true
      ..xiaochiPositionX = null ..xiaochiPositionY = null
      ..glassEnabled = false ..events = [] ..pending = [];
  });
  test('three actions have 20 unique lines, occasional catchphrase, no cycle repeat', () {
    for (final action in [DafeiyuInteraction.pet, DafeiyuInteraction.sleep, DafeiyuInteraction.praise]) {
      final lines = gugaDialogue[action]!;
      expect(lines.length, 20);
      expect(lines.toSet().length, 20);
      expect(lines.where((s) => s.contains('咕咕嘎嘎')).length, 3);
      final deck = GugaDialogueDeck(random: Random(18));
      String? previous;
      for (var round = 0; round < 3; round++) {
        final batch = <String>{};
        for (var i = 0; i < 20; i++) {
          final line = deck.next(action);
          expect(line, isNot(previous));
          expect(batch.add(line), isTrue);
          previous = line;
        }
        expect(batch, lines.toSet());
      }
    }
  });
  testWidgets('choice persists and Guga cannot call AI even if token exists', (tester) async {
    await tester.runAsync(() async {
      final store = StudyStore();
      await store.init();
      await store.setCompanionAppearance('guga');
      store.token = 'not-a-real-token';
      expect(store.usesGuga, isTrue);
      expect(store.companionName, '咕嘎');
      await expectLater(store.chatWithXiaochi(message: '你好', history: []), throwsA(predicate((e) => e.toString().contains('咕嘎暂不支持 AI 聊天'))));
      final restored = StudyStore();
      await restored.init();
      expect(restored.companionAppearance, 'guga');
    });
  });
  testWidgets('Guga actions use comic bubble, portrait, sleep and no AI or voice', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.expand(child: XiaochiAssistant()))));
    await tester.pump();
    expect(find.byType(GugaAvatar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pump();
    expect(find.byKey(const ValueKey('dafeiyu-speech-bubble')), findsOneWidget);
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsOneWidget);
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.idle);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsNothing);
    expect(find.byKey(const ValueKey('dafeiyu-bubble-portrait')), findsOneWidget);
    final portraitImages = tester.widgetList<Image>(find.descendant(
        of: find.byKey(const ValueKey('dafeiyu-bubble-portrait')),
        matching: find.byType(Image))).toList();
    expect(((portraitImages.single.image as ResizeImage).imageProvider as AssetImage).assetName, 'assets/guga/guga-idle-body.png');
    expect(portraitImages.single.fit, BoxFit.contain);
    expect(portraitImages.single.width, 56);
    expect(portraitImages.single.height, 67);
    final speech = tester.widget<Text>(find.byKey(const ValueKey('dafeiyu-speech-text')));
    expect(speech.style!.color, const Color(0xFF37363F));
    final petButton = tester.widget<TextButton>(find.ancestor(
        of: find.text('摸摸头'), matching: find.byType(TextButton)).first);
    expect(petButton.style!.foregroundColor!.resolve({}), const Color(0xFF37363F));
    expect(petButton.style!.backgroundColor!.resolve({}), const Color(0xFFECECEF));
    expect(find.descendant(of: find.byKey(const ValueKey('dafeiyu-speech-bubble')), matching: find.text('咕嘎')), findsOneWidget);
    expect(find.text('摸摸头'), findsOneWidget);
    expect(find.text('睡一会'), findsOneWidget);
    expect(find.text('夸夸我'), findsOneWidget);
    expect(find.text('AI 聊天'), findsNothing);
    expect(find.text('聊天升级中'), findsNothing);
    expect(find.byKey(const ValueKey('dafeiyu-play-voice')), findsNothing);
    await tester.tap(find.text('摸摸头'));
    await tester.pump();
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsOneWidget);
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.idle);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.pet);
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsNothing);
    await tester.tap(find.text('夸夸我'));
    await tester.pump();
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsOneWidget);
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.pet);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.praise);
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsNothing);
    await tester.tap(find.text('睡一会'));
    await tester.pump();
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsOneWidget);
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.praise);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.sleep);
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pump();
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsOneWidget);
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.sleep);
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.idle);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('floating-companion'))));
    await gesture.moveBy(const Offset(-25, -25));
    await tester.pump();
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.drag);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<GugaAvatar>(find.byType(GugaAvatar)).pose, GugaPose.idle);
    expect(app.store.events, isEmpty);
    expect(app.store.pending, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('selecting Guga closes an existing author chat', (tester) async {
    app.store.userId = 'author';
    app.store.token = 'author-test-token';
    app.store.baseUrl = 'https://author-test.invalid';
    await http.runWithClient(() => app.store.refreshCompanionAccess(),
        () => MockClient((_) async => http.Response('{"isAdmin":true}', 200)));
    await app.store.setCompanionAppearance('dafeiyu');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.expand(child: XiaochiAssistant()))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pump(const Duration(milliseconds: 550)); await tester.pump();
    await tester.tap(find.text('AI 聊天'));
    await tester.pump(const Duration(milliseconds: 550)); await tester.pump();
    expect(find.byTooltip('关闭大肥鱼聊天'), findsOneWidget);
    await app.store.setCompanionAppearance('guga');
    await tester.pump(const Duration(milliseconds: 550)); await tester.pump();
    final ignored = tester.widgetList<IgnorePointer>(find.ancestor(
        of: find.byTooltip('关闭咕嘎聊天'), matching: find.byType(IgnorePointer)));
    expect(ignored.any((widget) => widget.ignoring), isTrue);
    expect(find.byType(GugaAvatar), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); await tester.pump();
  });
}
