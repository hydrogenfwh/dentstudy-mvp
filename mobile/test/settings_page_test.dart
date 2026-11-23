import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/features/profile/profile_page.dart';
import 'package:dentstudy/features/profile/settings_page.dart';
import 'package:dentstudy/features/profile/policy_page.dart';
import 'package:dentstudy/features/profile/account_deletion_page.dart';
import 'package:dentstudy/features/statistics/statistics_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.token = '';
    app.store.email = '';
    app.store.userId = 'guest';
    app.store.baseUrl = '';
    app.store.questions = [];
    app.store.events = [];
    app.store.pending = [];
    app.store.glassEnabled = false;
    app.store.xiaochiEnabled = true;
    app.store.companionAppearance = 'dafeiyu';
    app.store.dailyNewLimit = 20;
    app.store.dailyReviewTarget = null;
  });

  testWidgets('profile replaces three sections with a single settings entry',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ProfilePage(onStart: (_) async {}))));
    await tester.pumpAndSettle();
    expect(find.text('主题与外观'), findsNothing);
    expect(find.text('学习设置'), findsNothing);
    expect(find.text('服务与规则'), findsNothing);
    expect(find.text('关于题库'), findsNothing);
    expect(find.byKey(const ValueKey('question-bank-upload-stone-reward')),
        findsOneWidget);
    expect(find.text('每日上传成功'), findsOneWidget);
    final entry = find.byKey(const ValueKey('profile-settings-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('主题与外观'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('学习设置'), 300);
    expect(find.text('学习设置'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('用户协议、隐私说明、版权投诉与数据删除'), 300);
    await tester.tap(find.text('用户协议、隐私说明、版权投诉与数据删除'));
    await tester.pumpAndSettle();
    expect(find.byType(PolicyPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('learning controls persist and update within settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.scrollUntilVisible(find.text('大肥鱼 · 备考搭子'), 300);
    await tester.tap(find.text('大肥鱼 · 备考搭子'));
    await tester.pumpAndSettle();
    expect(app.store.xiaochiEnabled, isFalse);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '大肥鱼 · 备考搭子'))
            .value,
        isFalse);
    await tester.ensureVisible(find.text('每日学习目标'));
    await tester.tap(find.text('每日学习目标'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '35');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    // The shared store's serialized persistence queue may cross the test's
    // fake clock; drain real microtasks before checking the notified UI.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(app.store.dailyNewLimit, 35);
    expect(
        jsonDecode(app.store.prefs.getString('account:guest')!)['settings']
            ['dailyNewLimit'],
        35);
    expect(find.textContaining('当前 35'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-in account deletion stays accessible from settings',
      (tester) async {
    app.store.token = 'test-only-token';
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    final deleteAccount = find.text('删除账号').hitTestable();
    await tester.scrollUntilVisible(deleteAccount, 300);
    await tester.pumpAndSettle();
    await tester.tap(deleteAccount);
    await tester.pumpAndSettle();
    expect(find.byType(AccountDeletionPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ranking participation is default-on and managed in settings',
      (tester) async {
    app.store.token = 'test-only-token';
    app.store.userId = 'ranking-user';
    app.store.baseUrl = 'https://ranking-test.invalid';
    var enabled = true;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.pumpAndSettle();
      final setting =
          find.byKey(const ValueKey('stone-leaderboard-participation-setting'));
      await tester.scrollUntilVisible(setting, 300);
      await tester.ensureVisible(setting);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(setting).value, isTrue);
      expect(find.textContaining('默认参与：头像、昵称和获得石头数会公开展示'), findsOneWidget);

      await tester.tap(setting);
      await tester.pumpAndSettle();
      expect(enabled, isFalse);
      expect(tester.widget<SwitchListTile>(setting).value, isFalse);
      expect(find.textContaining('已关闭：不会公开上榜'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              if (request.url.path == '/v1/stones/leaderboard') {
                return http.Response(
                    jsonEncode({
                      'me': {'participating': enabled}
                    }),
                    200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }
              if (request.url.path == '/v1/stones/leaderboard/participation') {
                final body =
                    Map<String, dynamic>.from(jsonDecode(request.body) as Map);
                enabled = body['enabled'] == true;
                return http.Response(jsonEncode({'enabled': enabled}), 200,
                    headers: {
                      'content-type': 'application/json; charset=utf-8'
                    });
              }
              throw StateError(
                  'Unexpected request: ${request.method} ${request.url}');
            }));
  });

  testWidgets('statistics keeps the threshold without small-sample copy',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatisticsPage(onStart: (_) async {}))));
    await tester.scrollUntilVisible(find.text('已作答客观题正确率低于 80%'), 300);
    expect(find.textContaining('小样本仅供参考'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings can override and resume the system appearance',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    final platform = tester.platformDispatcher;
    platform.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(platform.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({'webWelcomeCompleted': true});
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..themeMode = ThemeMode.system
      ..xiaochiEnabled = false;
    await tester.pumpWidget(const DentStudy());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    final settings = find.byKey(const ValueKey('profile-settings-entry'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();

    void check(String label, Brightness brightness) {
      final chip = find.widgetWithText(ChoiceChip, label);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(Theme.of(tester.element(chip)).brightness, brightness);
    }

    Future<void> choose(String label) async {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
    }

    check('跟随系统', Brightness.light);
    await choose('深色');
    check('深色', Brightness.dark);
    platform.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    await choose('浅色');
    check('浅色', Brightness.light);
    expect(app.store.prefs.getString('themeMode'), 'light');
    platform.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    platform.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    check('浅色', Brightness.light);
    await choose('跟随系统');
    check('跟随系统', Brightness.dark);
    platform.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    check('跟随系统', Brightness.light);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  if (const bool.fromEnvironment('SETTINGS_PREVIEW')) {
    testWidgets('settings layout preview', (tester) async {
      await tester.runAsync(() async {
        await (FontLoader('DentStudySans')
              ..addFont(
                  rootBundle.load('assets/fonts/DentStudySans-Regular.otf')))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const preview = ValueKey('settings-preview');
      await tester
          .pumpWidget(const RepaintBoundary(key: preview, child: DentStudy()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(preview),
          matchesGoldenFile('/private/tmp/dentstudy-profile-settings.png'));
      await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(preview),
          matchesGoldenFile('/private/tmp/dentstudy-settings-appearance.png'));
      await tester.scrollUntilVisible(find.text('用户协议、隐私说明、版权投诉与数据删除'), 250);
      await tester.pumpAndSettle();
      await expectLater(find.byKey(preview),
          matchesGoldenFile('/private/tmp/dentstudy-settings-services.png'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
