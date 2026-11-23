import 'dart:math' as math;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dentstudy/store.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/assistant/dafeiyu_avatar.dart';
import 'package:dentstudy/features/assistant/xiaochi_assistant.dart';
import 'package:dentstudy/features/profile/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..userId = 'guest'
      ..email = ''
      ..token = ''
      ..baseUrl = ''
      ..companionAppearance = 'xiaochi'
      ..xiaochiEnabled = true
      ..xiaochiPositionX = null
      ..xiaochiPositionY = null
      ..glassEnabled = false
      ..events = []
      ..pending = [];
  });

  Future<void> authorize(StudyStore store) async {
    store.userId = 'author';
    store.token = 'author-test-token';
    store.baseUrl = 'https://author-test.invalid';
    await http.runWithClient(() => store.refreshCompanionAccess(),
        () => MockClient((_) async => http.Response('{"isAdmin":true}', 200)));
  }

  testWidgets('default is Dafeiyu and explicit appearances restore per account',
      (tester) async {
    await tester.runAsync(() async {
      final s = StudyStore();
      await s.init();
      expect(s.companionName, '大肥鱼');
      await s.setCompanionAppearance('xiaochi');
      await authorize(s);
      await s.prefs.setString('userId', 'author');
      await s.secure.write(key: 'token', value: 'author-test-token');
      var notified = 0;
      s.addListener(() => notified++);
      final saving = s.setCompanionAppearance('dafeiyu');
      expect(s.usesDafeiyu, isTrue);
      expect(notified, 1);
      await saving;
      final restored = StudyStore();
      await restored.init();
      expect(restored.canChatWithCompanion, isFalse);
      await authorize(restored);
      expect(restored.companionName, '大肥鱼');
      expect(restored.events, isEmpty);
      expect(restored.pending, isEmpty);
      s.userId = 'second-account';
      await s.setCompanionAppearance('xiaochi');
      expect(s.prefs.getString('companionAppearance:author'), 'dafeiyu');
      expect(
          s.prefs.getString('companionAppearance:second-account'), 'xiaochi');
      await expectLater(
          s.setCompanionAppearance('unknown'), throwsArgumentError);
    });
  });

  testWidgets('unknown stored appearance falls back to Dafeiyu',
      (tester) async {
    await tester.runAsync(() async {
      await app.store.prefs.setString('companionAppearance:guest', 'unknown');
      final s = StudyStore();
      await s.init();
      expect(s.companionName, '大肥鱼');
    });
  });

  for (final pose in DafeiyuPose.values) {
    testWidgets(
        'rig ${pose.name}: assets, weights, seamless loop and no folded triangles',
        (tester) async {
      final bytes = await tester.runAsync(() => rootBundle.load(pose.asset));
      expect(bytes!.lengthInBytes, greaterThan(1000));
      final rig = DafeiyuRig(pose);
      expect(rig.weights.length, 925);
      expect(DafeiyuRig.indices.length, 1728 * 3);
      for (final w in rig.weights) {
        expect(w.length, 8);
        expect(w.reduce((a, b) => a + b), closeTo(1, 1e-12));
        expect(w.every((value) => value.isFinite && value >= 0), isTrue);
      }
      final first = rig.vertices(0), last = rig.vertices(1);
      final zero = rig.vertices(.2, intensity: 0);
      for (var i = 0; i < first.length; i++) {
        expect((first[i] - last[i]).distance, lessThan(1e-12));
        expect((zero[i] - DafeiyuRig.rest[i]).distance, lessThan(1e-12));
      }
      var minimum = double.infinity;
      for (var step = 0; step < 24; step++) {
        final v = rig.vertices(step / 24, intensity: 2);
        for (var t = 0; t < DafeiyuRig.indices.length; t += 3) {
          final a = v[DafeiyuRig.indices[t]],
              b = v[DafeiyuRig.indices[t + 1]],
              c = v[DafeiyuRig.indices[t + 2]];
          final cross =
              (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
          minimum = math.min(minimum, -cross * 24 * 36);
        }
      }
      expect(minimum, greaterThan(.15));
    });
  }

  Future<void> mount(WidgetTester tester,
      {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SizedBox.expand(child: XiaochiAssistant()))));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1440, 900)
  ]) {
    testWidgets('Dafeiyu local interaction, sleep/wake and switching fit $size',
        (tester) async {
      await authorize(app.store);
      await app.store.setCompanionAppearance('dafeiyu');
      await mount(tester, size: size);
      expect(find.byType(DafeiyuAvatar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('floating-companion')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dafeiyu-interaction-menu')),
          findsOneWidget);
      expect(find.text('AI 聊天'), findsOneWidget);
      final locked =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'AI 聊天'));
      expect(locked.onPressed, isNotNull);
      await tester.tap(find.text('夸夸我'));
      await tester.pumpAndSettle();
      expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
          DafeiyuPose.praise);
      await tester.tap(find.text('睡一会'));
      await tester.pumpAndSettle();
      expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
          DafeiyuPose.sleep);
      await tester.tap(find.byKey(const ValueKey('floating-companion')));
      await tester.pumpAndSettle();
      expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
          DafeiyuPose.wave);
      await app.store.setCompanionAppearance('xiaochi');
      await tester.pumpAndSettle();
      expect(find.byType(DafeiyuAvatar), findsNothing);
      expect(
          find.byKey(const ValueKey('dafeiyu-interaction-menu')), findsNothing);
      expect(app.store.events, isEmpty);
      expect(app.store.pending, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('idle sleep and disabling cancel the companion timers',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    await mount(tester);
    await tester.pump(const Duration(seconds: 61));
    expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
        DafeiyuPose.sleep);
    await app.store.setXiaochiEnabled(false);
    await tester.pump();
    expect(find.byKey(const ValueKey('floating-companion')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all four actions and a small portrait share the comic bubble',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dafeiyu-speech-bubble')), findsOneWidget);
    final bubble = find.byKey(const ValueKey('dafeiyu-speech-bubble'));
    expect(find.descendant(of: bubble, matching: find.byType(TextButton)),
        findsNWidgets(4));
    expect(
        find.byKey(const ValueKey('dafeiyu-bubble-portrait')), findsOneWidget);
    await tester.tap(find.text('摸摸头'));
    await tester.pumpAndSettle();
    final line = tester
        .widget<Text>(find.byKey(const ValueKey('dafeiyu-speech-text')))
        .data!;
    expect(line, isNotEmpty);
    await tester.tap(find.byTooltip('收起大肥鱼气泡'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dafeiyu-speech-bubble')), findsNothing);
    expect(
        find.byKey(const ValueKey('dafeiyu-interaction-menu')), findsNothing);
  });

  testWidgets('local actions show floating dots for 200 to 500 milliseconds',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('夸夸我'));
    await tester.pump();
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsOneWidget);
    expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
        DafeiyuPose.wave);
    await tester.pump(const Duration(milliseconds: 199));
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 302));
    expect(find.byKey(const ValueKey('dafeiyu-thinking-dots')), findsNothing);
    expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
        DafeiyuPose.praise);
  });

  testWidgets('latest action wins and closing cancels the pending reaction',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('夸夸我'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('睡一会'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
        DafeiyuPose.sleep);
    await tester.tap(find.text('醒醒啦'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('收起大肥鱼气泡'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(find.byKey(const ValueKey('dafeiyu-speech-bubble')), findsNothing);
    expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
        DafeiyuPose.sleep);
  });

  testWidgets('switching companion cancels a pending local response',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('夸夸我'));
    await tester.pump(const Duration(milliseconds: 100));
    await app.store.setCompanionAppearance('xiaochi');
    await tester.pump(const Duration(milliseconds: 501));
    expect(find.byKey(const ValueKey('dafeiyu-speech-bubble')), findsNothing);
    expect(find.byType(DafeiyuAvatar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings offers both appearances and persists selection',
      (tester) async {
    await authorize(app.store);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    final dafeiyu = find.byKey(const ValueKey('companion-dafeiyu')).hitTestable();
    await tester.scrollUntilVisible(dafeiyu, 250);
    await tester.pumpAndSettle();
    await tester.tap(dafeiyu);
    await tester.pumpAndSettle();
    expect(app.store.companionName, '大肥鱼');
    expect(app.store.prefs.getString('companionAppearance:author'), 'dafeiyu');
    await tester.tap(find.byKey(const ValueKey('companion-xiaochi')));
    await tester.pumpAndSettle();
    expect(app.store.companionName, '小齿');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'AI reply has its own scrollable comic preview after closing chat',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    await mount(tester);
    const reply = '哦鲸鲸～认真学习，也允许休息 (｡•ᴗ•｡) 🐳';
    var requests = 0;
    await http.runWithClient(() async {
      await tester.tap(find.byKey(const ValueKey('floating-companion')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 聊天'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '你叫什么？');
      expect(find.byKey(const ValueKey('floating-companion')), findsNothing);
      await tester.tap(find.byTooltip('发送给大肥鱼'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text(reply), findsOneWidget);
      await tester.tap(find.byTooltip('关闭大肥鱼聊天'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('dafeiyu-speech-text')))
              .data,
          reply);
      expect(find.text('大肥鱼 · AI 回复'), findsOneWidget);
      expect(find.byKey(const ValueKey('dafeiyu-interaction-menu')),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(
          find.byKey(const ValueKey('dafeiyu-speech-bubble')), findsOneWidget);
    },
        () => MockClient((request) async {
              requests++;
              expect(request.url.path, '/v1/assistant/chat');
              return http.Response('{"reply":"$reply"}', 200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
    expect(tester.takeException(), isNull);
  });

  testWidgets('everyone can switch both appearances in settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    final dafeiyu = find.byKey(const ValueKey('companion-dafeiyu')).hitTestable();
    await tester.scrollUntilVisible(dafeiyu, 250);
    await tester.pumpAndSettle();
    await tester.tap(dafeiyu);
    await tester.pumpAndSettle();
    expect(app.store.usesDafeiyu, isTrue);
    expect(app.store.canChatWithCompanion, isFalse);
    await tester.tap(find.byKey(const ValueKey('companion-xiaochi')));
    await tester.pumpAndSettle();
    expect(app.store.companionName, '小齿');
    expect(app.store.prefs.getString('companionAppearance:guest'), 'xiaochi');
    await tester.runAsync(() async {
      final restored = StudyStore();
      await restored.init();
      expect(restored.companionName, '小齿');
    });
  });

  for (final role in ['guest', 'ordinary']) {
    testWidgets('$role local actions send zero HTTP requests and cannot chat',
        (tester) async {
      app.store
        ..userId = role
        ..token = role == 'guest' ? '' : 'ordinary-test-token'
        ..email = 'dentstudy1126@aka.yeah.net'
        ..baseUrl = 'https://ordinary-test.invalid';
      await app.store.setCompanionAppearance('dafeiyu');
      var requests = 0;
      await http.runWithClient(() async {
        await mount(tester);
        await tester.tap(find.byKey(const ValueKey('floating-companion')));
        await tester.pumpAndSettle();
        expect(app.store.canChatWithCompanion, isFalse);
        final chat =
            tester.widget<TextButton>(find.widgetWithText(TextButton, '聊天升级中'));
        expect(chat.onPressed, isNull);
        for (final label in ['摸摸头', '夸夸我', '睡一会', '醒醒啦']) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }
        await expectLater(
            app.store.chatWithXiaochi(message: '你好', history: const []),
            throwsException);
        expect(requests, 0);
        expect(app.store.events, isEmpty);
        expect(app.store.pending, isEmpty);
      },
          () => MockClient((_) async {
                requests++;
                throw StateError(
                    'Local interactions must not make HTTP requests');
              }));
    });
  }

  testWidgets(
      'permission is tied to session; delayed old profile cannot authorize new user',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    await mount(tester);
    final response = Completer<http.Response>();
    await http.runWithClient(() async {
      final pending = app.store.refreshCompanionAccess();
      app.store
        ..userId = 'other-account'
        ..token = 'other-token';
      expect(app.store.canChatWithCompanion, isFalse);
      response.complete(http.Response('{"isAdmin":true}', 200));
      await pending;
      expect(app.store.canChatWithCompanion, isFalse);
      await tester.pump();
    }, () => MockClient((_) => response.future));
  });

  testWidgets('chat permission revocation keeps local Dafeiyu available',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pumpAndSettle();
    await http.runWithClient(() => app.store.refreshCompanionAccess(),
        () => MockClient((_) async => http.Response('{"isAdmin":false}', 200)));
    await tester.pumpAndSettle();
    expect(find.byType(DafeiyuAvatar), findsOneWidget);
    expect(
        find.byKey(const ValueKey('dafeiyu-interaction-menu')), findsNothing);
    expect(app.store.canChatWithCompanion, isFalse);
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pumpAndSettle();
    expect(find.text('聊天升级中'), findsOneWidget);
    await tester.tap(find.text('摸摸头'));
    await tester.pumpAndSettle();
    expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
        DafeiyuPose.happy);
  });

  testWidgets('unloaded interaction is not reset after eight seconds',
      (tester) async {
    await authorize(app.store);
    await app.store.setCompanionAppearance('dafeiyu');
    final pending = Completer<ByteData>();
    await tester.pumpWidget(DefaultAssetBundle(
        bundle: _DelayedBundle(pending),
        child: const MaterialApp(
            home: Scaffold(body: SizedBox.expand(child: XiaochiAssistant())))));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('floating-companion')));
    await tester.pump();
    await tester.tap(find.text('夸夸我'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
        DafeiyuPose.praise);
    expect(
        find.byKey(const ValueKey('dafeiyu-interaction-menu')), findsOneWidget);
    final bytes =
        await tester.runAsync(() => rootBundle.load(DafeiyuPose.praise.asset));
    await tester.runAsync(() async {
      pending.complete(bytes!);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump();
    expect(
        find.byKey(const ValueKey('dafeiyu-rendered-praise')), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(tester.widget<DafeiyuAvatar>(find.byType(DafeiyuAvatar)).pose,
        DafeiyuPose.wave);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _DelayedBundle extends CachingAssetBundle {
  final Completer<ByteData> pending;
  _DelayedBundle(this.pending);
  @override
  Future<ByteData> load(String key) =>
      key.contains('/dafeiyu/') && key.endsWith('.png')
          ? pending.future
          : rootBundle.load(key);
}
