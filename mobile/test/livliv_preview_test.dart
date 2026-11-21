import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/assistant/dafeiyu_avatar.dart';
import 'package:dentstudy/features/assistant/livliv_avatar_stub.dart';
import 'package:dentstudy/features/assistant/xiaochi_assistant.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('touch drag moves the minimized companion without opening chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..userId = 'guest'
      ..token = ''
      ..companionAppearance = 'livliv-preview'
      ..xiaochiEnabled = true
      ..xiaochiPositionX = null
      ..xiaochiPositionY = null
      ..glassEnabled = false;
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: XiaochiAssistant()))));
    await tester.pump();
    final avatar = find.byKey(const ValueKey('floating-companion'));
    final before = tester.getTopLeft(avatar);
    final touch = await tester.startGesture(tester.getCenter(avatar),
        kind: PointerDeviceKind.touch);
    await touch.moveBy(const Offset(-100, -100));
    await tester.pump();
    await touch.moveBy(const Offset(-30, -20));
    await tester.pump();
    final after = tester.getTopLeft(avatar);
    expect(after.dx, lessThan(before.dx - 40));
    expect(after.dy, lessThan(before.dy - 40));
    await touch.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('dafeiyu-speech-bubble')), findsNothing);
    expect(app.store.xiaochiPositionX, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'LivLiv selection persists and offers local actions and the character room',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..userId = 'guest'
      ..token = ''
      ..companionAppearance = 'dafeiyu'
      ..xiaochiEnabled = true
      ..xiaochiPositionX = null
      ..xiaochiPositionY = null
      ..glassEnabled = false;
    await app.store.setCompanionAppearance('livliv-preview');
    expect(app.store.usesLivlivPreview, isTrue);
    expect(app.store.usesInteractiveCompanion, isTrue);
    expect(app.store.prefs.getString('companionAppearance:guest'),
        'livliv-preview');
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: XiaochiAssistant()))));
    await tester.pump();
    expect(find.byType(LivLivAvatar), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(find.text('LivLiv'), findsWidgets);
    expect(find.byKey(const ValueKey('livliv-expand-chat')), findsOneWidget);
    expect(find.text('AI 聊天'), findsNothing);
    expect(find.byKey(const ValueKey('dafeiyu-play-voice')), findsNothing);
    for (final entry in {'生闷气': 'angry', '不开心': 'sad', '害羞': 'shy'}.entries) {
      expect(find.text(entry.key), findsOneWidget);
      await tester.tap(find.text(entry.key));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      expect(tester.widget<LivLivAvatar>(find.byType(LivLivAvatar)).expression,
          entry.value);
      expect(tester.widget<LivLivAvatar>(find.byType(LivLivAvatar)).pose,
          DafeiyuPose.wave);
    }
    await tester.tap(find.text('夸夸我'));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(tester.widget<LivLivAvatar>(find.byType(LivLivAvatar)).pose,
        DafeiyuPose.praise);
    expect(tester.widget<LivLivAvatar>(find.byType(LivLivAvatar)).expression,
        isNull);
    final previousSerial = tester
        .widget<LivLivAvatar>(find.byType(LivLivAvatar))
        .interactionSerial;
    await tester.tap(find.text('夸夸我'));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(
        tester
            .widget<LivLivAvatar>(find.byType(LivLivAvatar))
            .interactionSerial,
        previousSerial + 1);
    await tester.tap(find.text('睡一会'));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    expect(tester.widget<LivLivAvatar>(find.byType(LivLivAvatar)).pose,
        DafeiyuPose.sleep);
    expect(find.text('醒醒啦'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
