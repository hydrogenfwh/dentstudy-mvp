import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/profile/stone_reward_notice.dart';
import 'package:dentstudy/features/today/checkin_calendar.dart';

Map<String, dynamic> calendar({
  required int year,
  required String today,
  required List<String> dates,
  required int streak,
  required int yearCount,
  required bool checkedInToday,
  int makeupDailyLimit = 3,
  int makeupUsedToday = 0,
  List<Map<String, dynamic>> stoneRewards = const [],
}) =>
    {
      'year': year,
      'today': today,
      'dates': dates,
      'currentStreak': streak,
      'yearCount': yearCount,
      'checkedInToday': checkedInToday,
      'makeupDailyLimit': makeupDailyLimit,
      'makeupUsedToday': makeupUsedToday,
      'stoneRewards': stoneRewards,
    };

http.Response jsonResponse(Map<String, dynamic> body) =>
    http.Response(jsonEncode(body), 200,
        headers: const {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (const bool.fromEnvironment('AUDIT_PREVIEW')) {
      await (FontLoader('DentStudySans')
            ..addFont(
                rootBundle.load('assets/fonts/DentStudySans-Regular.otf')))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.baseUrl = 'https://checkin-test.invalid';
    app.store.token = 'test-token';
    app.store.userId = 'checkin-test-user';
    app.store.email = 'checkin@example.invalid';
    app.store.themeColorKey = 'teal';
  });

  Future<void> openCalendar(WidgetTester tester,
      {Size size = const Size(900, 900), double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: const bool.fromEnvironment('AUDIT_PREVIEW')
            ? ThemeData(fontFamily: 'DentStudySans')
            : null,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showCheckinCalendar(context),
                    child: const Text('打开签到日历'))))));
    await tester.tap(find.text('打开签到日历'));
    await tester.pumpAndSettle();
  }

  testWidgets('reloads the actual Beijing year before rendering its calendar',
      (tester) async {
    final requestedYears = <String>[];
    http.Client client() => MockClient((request) async {
          expect(request.method, 'GET');
          final year = request.url.queryParameters['year'];
          requestedYears.add(year ?? '');
          switch (year) {
            case '2026':
              return jsonResponse(calendar(
                  year: 2026,
                  today: '2027-03-15',
                  dates: const ['2026-01-02'],
                  streak: 2,
                  yearCount: 9,
                  checkedInToday: false));
            case '2027':
              return jsonResponse(calendar(
                  year: 2027,
                  today: '2027-03-15',
                  dates: const ['2027-03-15'],
                  streak: 2,
                  yearCount: 1,
                  checkedInToday: true));
            default:
              throw StateError('Unexpected year: $year');
          }
        });

    await http.runWithClient(() async {
      await openCalendar(tester);

      expect(requestedYears, ['2026', '2027']);
      expect(find.text('2027 年 3 月'), findsOneWidget);
      expect(find.textContaining('1 天已签到'), findsOneWidget);
      expect(find.textContaining('9 天已签到'), findsNothing);
    }, client);
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('calendar and makeup fit $size with enlarged text',
        (tester) async {
      await http.runWithClient(() async {
        await openCalendar(tester, size: size, textScale: 1.3);
        expect(find.text('2026 年 10 月'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('22'));
        await tester.pumpAndSettle();
        expect(find.text('补签 2026-10-22 · 消耗 5 颗'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('31'), 50,
            scrollable: find.descendant(
                of: find.byType(GridView), matching: find.byType(Scrollable)));
        await tester.pumpAndSettle();
        expect(find.text('31').hitTestable(), findsOneWidget);
        if (const bool.fromEnvironment('AUDIT_PREVIEW')) {
          await tester.runAsync(() => precacheImage(
              const AssetImage('assets/hydroxyapatite.png'),
              tester.element(find.byType(Dialog))));
          await tester.pumpAndSettle();
          await expectLater(
              find.byType(Dialog),
              matchesGoldenFile('../../output/audit-20261025/screenshots/'
                  'calendar-${size.width.toInt()}.png'));
        }
      },
          () => MockClient((_) async => jsonResponse(calendar(
              year: 2026,
              today: '2026-10-23',
              dates: ['2026-10-23'],
              streak: 1,
              yearCount: 1,
              checkedInToday: true))));
    });
  }

  testWidgets(
      'past unsigned dates can be made up, while signed and future dates stay unavailable',
      (tester) async {
    var madeUp = false;
    final makeupBodies = <Map<String, dynamic>>[];
    http.Client client() => MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/v1/checkins') {
            return jsonResponse(calendar(
                year: 2026,
                today: '2026-10-23',
                dates: madeUp
                    ? const ['2026-10-20', '2026-10-22', '2026-10-23']
                    : const ['2026-10-20', '2026-10-23'],
                streak: madeUp ? 7 : 5,
                yearCount: madeUp ? 3 : 2,
                checkedInToday: true,
                makeupUsedToday: madeUp ? 1 : 0));
          }
          if (request.method == 'POST' &&
              request.url.path == '/v1/checkins/makeup') {
            makeupBodies.add(
                Map<String, dynamic>.from(jsonDecode(request.body) as Map));
            madeUp = true;
            return jsonResponse(calendar(
                year: 2026,
                today: '2026-10-23',
                dates: const ['2026-10-20', '2026-10-22', '2026-10-23'],
                streak: 7,
                yearCount: 3,
                checkedInToday: true,
                makeupUsedToday: 1,
                stoneRewards: const [
                  {'id': 7022, 'amount': 7}
                ]));
          }
          throw StateError(
              'Unexpected request: ${request.method} ${request.url}');
        });

    await http.runWithClient(() async {
      await openCalendar(tester);

      expect(
          find.byWidgetPredicate(
              (widget) => widget is StoneCoinIcon && widget.size == 16),
          findsNWidgets(2),
          reason: 'each completed date carries the visible small stone badge');
      expect(
          find.byKey(const ValueKey('checkin-complete-status')), findsOneWidget,
          reason: 'a completed check-in stays visibly associated with a stone');
      expect(find.text('日期按北京时间计算'), findsNothing);
      await tester.tap(find.text('24'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('补签 2026-10-24'), findsNothing,
          reason: 'future dates cannot be selected for makeup');
      await tester.tap(find.text('20'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('补签 2026-10-20'), findsNothing,
          reason: 'a completed date cannot be selected for makeup');

      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();
      expect(find.text('补签 2026-10-22 · 消耗 5 颗'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '补签'));
      await tester.pumpAndSettle();
      expect(find.text('补签 2026-10-22？'), findsOneWidget);
      expect(find.textContaining('如果正好凑满连续'), findsNothing,
          reason: 'the confirmation stays concise');
      expect(find.textContaining('将消耗 5 颗'), findsNothing,
          reason: 'the action label already explains the cost');
      expect(makeupBodies, isEmpty,
          reason: 'the cost confirmation must precede the API call');
      await tester.tap(find.widgetWithText(FilledButton, '消耗 5 颗补签'));
      await tester.pumpAndSettle();

      expect(makeupBodies, hasLength(1));
      expect(makeupBodies.single['date'], '2026-10-22');
      expect(find.textContaining('今天还可补 2 次'), findsOneWidget);
      expect(find.byType(StoneRewardNotice), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(StoneRewardNotice),
              matching: find.textContaining('+7')),
          findsOneWidget,
          reason: 'a makeup that completes seven days shows its bonus inline');
      expect(
          find.byWidgetPredicate(
              (widget) => widget is StoneCoinIcon && widget.size == 16),
          findsNWidgets(3),
          reason: 'the made-up day receives the same calendar badge');
      expect(tester.takeException(), isNull);
    }, client);
  });

  testWidgets('daily check-in shows its stone reward below the check-in card',
      (tester) async {
    var checkedIn = false;
    http.Client client() => MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/v1/checkins') {
            return jsonResponse(calendar(
                year: 2026,
                today: '2026-10-23',
                dates: checkedIn ? const ['2026-10-23'] : const [],
                streak: checkedIn ? 1 : 0,
                yearCount: checkedIn ? 1 : 0,
                checkedInToday: checkedIn));
          }
          if (request.method == 'POST' && request.url.path == '/v1/checkins') {
            checkedIn = true;
            return jsonResponse(calendar(
                year: 2026,
                today: '2026-10-23',
                dates: const ['2026-10-23'],
                streak: 1,
                yearCount: 1,
                checkedInToday: true,
                stoneRewards: const [
                  {'id': 1023, 'amount': 1}
                ]));
          }
          throw StateError(
              'Unexpected request: ${request.method} ${request.url}');
        });

    await http.runWithClient(() async {
      await openCalendar(tester);
      await tester.tap(find.widgetWithText(FilledButton, '签到 +1'));
      await tester.pumpAndSettle();

      expect(find.byType(StoneRewardNotice), findsOneWidget);
      expect(
          find.byKey(const ValueKey('checkin-complete-status')), findsOneWidget,
          reason: 'the successful check-in has a persistent in-place state');
      expect(
          find.descendant(
              of: find.byType(StoneRewardNotice),
              matching: find.textContaining('+1')),
          findsOneWidget);
      expect(find.textContaining('签到成功'), findsNothing,
          reason: 'the reward is shown in context instead of a generic toast');
      expect(tester.takeException(), isNull);
    }, client);
  });

  testWidgets('signing while viewing another year reloads that year instead',
      (tester) async {
    var signedToday = false;
    var selectedYearLoads = 0;
    http.Client client() => MockClient((request) async {
          final year = request.url.queryParameters['year'];
          if (request.method == 'GET') {
            if (year == '2026') {
              return jsonResponse(calendar(
                  year: 2026,
                  today: '2026-10-20',
                  dates: const ['2026-10-02'],
                  streak: 3,
                  yearCount: 1,
                  checkedInToday: signedToday));
            }
            if (year == '2027') {
              selectedYearLoads += 1;
              return jsonResponse(calendar(
                  year: 2027,
                  today: '2026-10-20',
                  dates: const ['2027-01-04'],
                  streak: signedToday ? 4 : 3,
                  yearCount: 1,
                  checkedInToday: signedToday));
            }
          }
          if (request.method == 'POST' && request.url.path == '/v1/checkins') {
            signedToday = true;
            return jsonResponse(calendar(
                year: 2026,
                today: '2026-10-20',
                dates: const ['2026-10-02', '2026-10-20'],
                streak: 4,
                yearCount: 9,
                checkedInToday: true));
          }
          throw StateError(
              'Unexpected request: ${request.method} ${request.url}');
        });

    await http.runWithClient(() async {
      await openCalendar(tester);
      for (var i = 0; i < 3; i += 1) {
        await tester.tap(find.byTooltip('下个月'));
        await tester.pumpAndSettle();
      }
      expect(find.text('2027 年 1 月'), findsOneWidget);
      expect(selectedYearLoads, 1);

      await tester.tap(find.widgetWithText(FilledButton, '签到 +1'));
      await tester.pumpAndSettle();

      expect(selectedYearLoads, 2,
          reason: 'the current-year POST snapshot must not replace 2027 data');
      expect(find.text('2027 年 1 月'), findsOneWidget);
      expect(find.textContaining('1 天已签到'), findsOneWidget);
      expect(find.textContaining('9 天已签到'), findsNothing);
      expect(find.text('今日已签到'), findsOneWidget);
    }, client);
  });

  testWidgets('stale year responses cannot overwrite a newer calendar choice',
      (tester) async {
    final pending2026 = Completer<http.Response>();
    http.Client client() => MockClient((request) async {
          final year = request.url.queryParameters['year'];
          if (request.method == 'GET' && year == '2026') {
            return pending2026.future;
          }
          if (request.method == 'GET' && year == '2027') {
            return jsonResponse(calendar(
                year: 2027,
                today: '2027-02-15',
                dates: const ['2027-02-15'],
                streak: 1,
                yearCount: 1,
                checkedInToday: true));
          }
          throw StateError(
              'Unexpected request: ${request.method} ${request.url}');
        });

    await http.runWithClient(() async {
      await openCalendar(tester);
      for (var i = 0; i < 12; i += 1) {
        await tester.tap(find.byTooltip('下个月'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('2027 年 2 月'), findsOneWidget);
      expect(find.textContaining('1 天已签到'), findsOneWidget);

      pending2026.complete(jsonResponse(calendar(
          year: 2026,
          today: '2026-10-20',
          dates: const ['2026-10-20'],
          streak: 9,
          yearCount: 9,
          checkedInToday: true)));
      await tester.pumpAndSettle();

      expect(find.text('2027 年 2 月'), findsOneWidget);
      expect(find.textContaining('1 天已签到'), findsOneWidget);
      expect(find.textContaining('9 天已签到'), findsNothing);
    }, client);
  });
}
