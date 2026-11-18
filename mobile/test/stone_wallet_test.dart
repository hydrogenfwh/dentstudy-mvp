import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/profile/stone_reward_notice.dart';
import 'package:dentstudy/features/profile/stone_wallet_page.dart';
import 'package:dentstudy/store.dart';

Map<String, dynamic> wallet({bool open = false, int balance = 400}) => {
      'balance': balance,
      'reserved': 0,
      'fenPerStone': 2,
      'redemptionOpen': open,
      'mixedPaymentOpen': open,
      'items': [
        {
          'id': 2,
          'amount': -345,
          'reason': 'VIP 石头兑换',
          'createdAt': '2026-10-22T02:30:00Z'
        },
        {
          'id': 1,
          'amount': 1,
          'reason': '每日签到',
          'createdAt': '2026-10-22T01:00:00Z'
        },
      ],
      'nextCursor': null,
      'plans': [
        {
          'id': 'month',
          'name': '月卡',
          'priceFen': 690,
          'displayPrice': '6.90',
          'description': '每月 ¥6.9，手动续费，不自动扣款'
        }
      ],
    };
http.Response response(Map<String, dynamic> data) =>
    http.Response(jsonEncode(data), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> leaderboard({
  required bool participating,
  required String scope,
}) =>
    {
      'scope': scope,
      'range': switch (scope) {
        'today' => '今天（北京时间）',
        'week' => '本周（北京时间）',
        'month' => '本月（北京时间）',
        _ => '累计获得石头数',
      },
      'entries': const [
        {'rank': 1, 'nickname': '牙牙向前冲', 'score': 12},
        {'rank': 4, 'nickname': '小石头', 'score': 4},
      ],
      'me': {
        'participating': participating,
        'score': 4,
        'rank': participating ? 4 : null,
        'nickname': '测试本人',
        'avatar': 'tooth',
      },
    };

Map<String, dynamic> practiceLeaderboard({
  required bool participating,
  required String scope,
}) =>
    {
      'scope': scope,
      'entries': const [
        {'rank': 1, 'nickname': '今日刷题王', 'score': 18},
        {'rank': 2, 'nickname': '复习小能手', 'score': 6},
      ],
      'me': {
        'participating': participating,
        'score': 6,
        'rank': participating ? 2 : null,
        'nickname': '刷题本人',
        'avatar': 'tooth',
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.userId = 'stone-user';
    app.store.email = 'test@example.invalid';
    app.store.token = 'stone-token';
    app.store.baseUrl = 'https://stones-test.invalid';
    app.store.questions = [];
    app.store.events = [];
    app.store.pending = [];
    app.store.stoneNotices.clear();
    app.store.glassEnabled = false;
    app.store.themeColorKey = 'teal';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/share'),
            (_) async => 'test.target');
  });

  test('money uses exact integer fen', () {
    expect(stoneMoney(690), '6.90');
    expect(stoneMoney(690 - 123 * 2), '4.44');
    expect(stoneMoney(2), '0.02');
  });

  testWidgets('wallet keeps the balance concise and opens dated signed details',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: StoneWalletPage()));
      await tester.pumpAndSettle();
      expect(find.text('400'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
      expect(find.text('有一笔订单在等你'), findsNothing);
      expect(find.text('石头商城'), findsNothing);
      expect(find.text('石头流水'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('stone-wallet-details')));
      await tester.pumpAndSettle();
      expect(find.text('石头明细'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('2026-10-22 10:30'), 250);
      expect(find.text('-345'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text('每日首次完成学习目标 +1，首次完成复习目标 +1。'), 250);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((_) async => response(wallet()
          ..['pendingOrder'] = {
            'id': 'pending-order',
            'stones': 12,
            'cashFen': 690,
          })));
  });

  testWidgets('wallet opens the default public leaderboard with self identity',
      (tester) async {
    const participating = true;
    final requestedScopes = <String>[];
    final requestedPracticeScopes = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: StoneWalletPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('stone-leaderboard-entry')));
      await tester.pumpAndSettle();
      expect(find.text('羟基磷灰石排行榜'), findsOneWidget);
      expect(find.text('牙牙向前冲'), findsOneWidget);
      expect(find.text('测试本人'), findsOneWidget);
      expect(find.text('第 4 名'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(requestedScopes, contains('today'));
      expect(requestedPracticeScopes, contains('today'));

      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      expect(requestedScopes, contains('week'));
      expect(requestedPracticeScopes, contains('week'));
      expect(find.text('本周（北京时间）'), findsNothing);
      await tester.scrollUntilVisible(find.text('刷题本人'), 250);
      expect(find.text('刷题排行榜'), findsOneWidget);
      expect(find.text('今日刷题王'), findsOneWidget);
      expect(find.text('刷题本人'), findsOneWidget);
      expect(find.text('第 2 名 · 6 题'), findsOneWidget);
      expect(find.text('每次服务器确认的学习或复习答题计 1；0 题暂不排名。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              if (request.url.path == '/v1/stones') return response(wallet());
              if (request.url.path == '/v1/stones/leaderboard') {
                requestedScopes.add(request.url.queryParameters['scope'] ?? '');
                return response(leaderboard(
                    participating: participating,
                    scope: request.url.queryParameters['scope'] ?? 'today'));
              }
              if (request.url.path == '/v1/practice/leaderboard') {
                requestedPracticeScopes
                    .add(request.url.queryParameters['scope'] ?? '');
                return response(practiceLeaderboard(
                    participating: participating,
                    scope: request.url.queryParameters['scope'] ?? 'today'));
              }
              throw StateError(
                  'Unexpected request: ${request.method} ${request.url}');
            }));
  });

  testWidgets('details appends older entries one page at a time',
      (tester) async {
    final first = wallet()
      ..['items'] = [
        {
          'id': 2,
          'amount': 1,
          'reason': '每日签到',
          'createdAt': '2026-10-22T01:00:00Z'
        }
      ]
      ..['nextCursor'] = 2;
    final older = wallet()
      ..['items'] = [
        {
          'id': 1,
          'amount': -345,
          'reason': 'VIP 石头兑换',
          'createdAt': '2026-10-21T01:00:00Z'
        }
      ]
      ..['nextCursor'] = null;
    final requested = <Uri>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: StoneDetailPage()));
      await tester.pumpAndSettle();
      expect(find.text('每日签到'), findsOneWidget);
      await tester.tap(find.text('再翻一页'));
      await tester.pumpAndSettle();
      expect(find.text('VIP 石头兑换'), findsOneWidget);
      expect(requested.last.queryParameters['before'], '2');
      expect(tester.takeException(), isNull);
    },
        () => MockClient((request) async {
              requested.add(request.url);
              return response(
                  request.url.queryParameters['before'] == '2' ? older : first);
            }));
  });

  testWidgets(
      'payment modes calculate stones and mixed cash without enabling closed payments',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: StoneVipPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('月卡 · ¥6.90'));
      await tester.pumpAndSettle();
      expect(find.text('羟基磷灰石支付 · 345 颗'), findsOneWidget);
      await tester.ensureVisible(find.text('使用 345 颗兑换'));
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '使用 345 颗兑换'))
              .onPressed,
          isNull);
      await tester.ensureVisible(find.text('组合支付 · 石头 + 支付宝'));
      await tester.tap(find.text('组合支付 · 石头 + 支付宝'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '123');
      await tester.pumpAndSettle();
      expect(find.text('抵扣 ¥2.46，还需支付宝支付 ¥4.44'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => response(wallet())));
  });

  testWidgets('cancelled share never claims and successful share claims once',
      (tester) async {
    var claims = 0;
    var shareResult = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/share'),
            (_) async => shareResult);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: StoneWalletPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('系统分享 · 今日首次 +1'));
      await tester.pumpAndSettle();
      expect(claims, 0);
      shareResult = 'dev.fluttercommunity.plus/share/unavailable';
      await tester.tap(find.text('系统分享 · 今日首次 +1'));
      await tester.pumpAndSettle();
      expect(claims, 0);
      shareResult = 'test.target';
      await tester.tap(find.text('系统分享 · 今日首次 +1'));
      await tester.pumpAndSettle();
      expect(claims, 1);
    },
        () => MockClient((req) async {
              if (req.url.path.endsWith('/share')) {
                claims++;
                return response({'stoneRewards': []});
              }
              return response(wallet());
            }));
  },
      // Browser Web Share needs a real user activation and share target.
      skip: kIsWeb);

  test('redemption retry reuses key after a lost response', () async {
    final local = StudyStore()
      ..prefs = app.store.prefs
      ..userId = 'stone-user'
      ..token = 'stone-token'
      ..baseUrl = 'https://stones-test.invalid';
    final keys = <String>[];
    await http.runWithClient(() async {
      await expectLater(local.redeemStones('month', 690), throwsException);
      await local.redeemStones('month', 690);
      expect(keys.length, 2);
      expect(keys[0], keys[1]);
      expect(local.prefs.getString('stoneRedemption:stone-user:month'), isNull);
    },
        () => MockClient((req) async {
              keys.add(jsonDecode(req.body)['requestKey'] as String);
              if (keys.length == 1) throw Exception('lost response');
              return response({'orderId': 'ST-test', 'stones': 345});
            }));
  });

  testWidgets(
      'reward notice is concise and repeated response is not shown twice',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const DentStudy());
      await tester.pumpAndSettle();
      await app.store
          .request('/v1/stones/share', {'systemShareCompleted': true});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(StoneRewardNotice), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(StoneRewardNotice),
              matching: find.textContaining('+1')),
          findsOneWidget);
      app.appMessengerKey.currentState!.removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await app.store
          .request('/v1/stones/share', {'systemShareCompleted': true});
      await tester.pumpAndSettle();
      expect(find.byType(StoneRewardNotice), findsNothing,
          reason: 'the same reward id is only celebrated once');
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((req) async => response(req.url.path.endsWith('/share')
            ? {
                'stoneRewards': [
                  {'id': 91873, 'amount': 1}
                ]
              }
            : {'events': [], 'settings': null})));
  });

  if (const bool.fromEnvironment('STONES_PREVIEW')) {
    testWidgets('stone UI mobile previews', (tester) async {
      await tester.runAsync(() async {
        for (final name in ['Regular', 'Bold']) {
          await (FontLoader(
                  name == 'Bold' ? 'DentStudySansBold' : 'DentStudySans')
                ..addFont(
                    rootBundle.load('assets/fonts/DentStudySans-$name.otf')))
              .load();
        }
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await http.runWithClient(() async {
        const key = ValueKey('stone-preview');
        await tester
            .pumpWidget(const RepaintBoundary(key: key, child: DentStudy()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await tester.runAsync(() => precacheImage(
            const AssetImage('assets/hydroxyapatite.png'),
            tester.element(find.byType(DentStudy))));
        await tester.pumpAndSettle();
        await expectLater(find.byKey(key),
            matchesGoldenFile('/private/tmp/dentstudy-stone-profile.png'));
        await tester.tap(find.byKey(const ValueKey('stone-wallet-entry')));
        await tester.pumpAndSettle();
        await expectLater(find.byKey(key),
            matchesGoldenFile('/private/tmp/dentstudy-stone-wallet.png'));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
          () => MockClient((req) async => response(switch (req.url.path) {
                '/v1/stones' => wallet(),
                '/v1/profile' => {
                    'nickname': 'hydrogen',
                    'university': '口腔医学院'
                  },
                '/v1/question-bank-submissions' => {'submissions': []},
                _ => {'events': [], 'settings': null, 'unreadCount': 0},
              })));
    });
  }
}
