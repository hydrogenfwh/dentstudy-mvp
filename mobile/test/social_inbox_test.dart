import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/features/social/social_inbox_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    app.store.prefs = await SharedPreferences.getInstance();
    app.store.baseUrl = 'https://social-test.invalid';
    app.store.token = 'test-social-token';
    app.store.email = 'learner@example.invalid';
    app.store.userId = 'test-learner';
    app.store.themeColorKey = 'teal';
    app.store.customPrimaryKey = 'teal';
  });

  test('social store uses authenticated, encoded API routes', () async {
    final seen = <http.Request>[];
    final client = MockClient((request) async {
      seen.add(request);
      return http.Response(jsonEncode({'ok': true}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await http.runWithClient(() async {
      await app.store.searchPeople('测试 大学');
      await app.store.userCard('friend/a');
      await app.store.friends();
      await app.store.sendFriendRequest('friend/a');
      await app.store.respondToFriendRequest('request/a', true);
      await app.store.removeFriend('friend/a');
      await app.store.blockUser('friend/a');
      await app.store.unblockUser('friend/a');
      await app.store.notifications();
      await app.store.markNotificationsRead(ids: ['notice/a']);
      await app.store.conversations();
      await app.store.conversationMessages('friend/a');
      await app.store.sendConversationMessage('friend/a', '你好');
      await app.store.shareQuestionInConversation('friend/a', 'question/a');
    }, () => client);

    expect(seen.map((request) => request.headers['authorization']),
        everyElement('Bearer test-social-token'));
    expect(seen[0].url.toString(),
        'https://social-test.invalid/v1/users/search?q=%E6%B5%8B%E8%AF%95+%E5%A4%A7%E5%AD%A6');
    expect(
        seen.map((request) => request.url.path),
        containsAll([
          '/v1/friends',
          '/v1/users/friend%2Fa',
          '/v1/friends/requests',
          '/v1/friends/requests/request%2Fa/accept',
          '/v1/friends/friend%2Fa/remove',
          '/v1/friends/friend%2Fa/block',
          '/v1/friends/friend%2Fa/unblock',
          '/v1/notifications',
          '/v1/notifications/read',
          '/v1/conversations',
          '/v1/conversations/friend%2Fa/messages',
          '/v1/conversations/friend%2Fa/questions',
        ]));
    expect(
        seen
            .where((request) =>
                request.url.path == '/v1/conversations/friend%2Fa/messages')
            .length,
        2);
  });

  testWidgets('message center shows a conversation and unread notification',
      (tester) async {
    final client = MockClient((request) async {
      Object body;
      switch (request.url.path) {
        case '/v1/conversations':
          body = {
            'conversations': [
              {
                'friend': {
                  'id': 'friend-1',
                  'nickname': '小林',
                  'avatar': 'book',
                  'university': '测试大学',
                  'vipBadge': false,
                },
                'lastMessage': {'body': '一起复习吧'},
                'unreadCount': 1,
                'updatedAt': '2026-10-20T12:00:00Z',
              }
            ]
          };
        case '/v1/friends':
          body = {'friends': [], 'incoming': [], 'outgoing': []};
        case '/v1/notifications':
          body = {
            'unreadCount': 1,
            'items': [
              {
                'id': 'notice-1',
                'type': 'comment_like',
                'createdAt': '2026-10-20T12:00:00Z',
                'actor': {
                  'id': 'friend-1',
                  'nickname': '小林',
                  'avatar': 'book',
                  'university': '测试大学',
                  'vipBadge': false,
                }
              }
            ]
          };
        case '/v1/notifications/read':
          body = {'ok': true, 'unreadCount': 0};
        case '/v1/conversations/friend-1/messages':
          body = {'friend': {}, 'messages': []};
        default:
          return http.Response(jsonEncode({'error': 'unexpected route'}), 500);
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SocialInboxPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('小林'), findsWidgets);
      expect(find.text('一起复习吧'), findsOneWidget);

      await tester.tap(find.text('通知'));
      await tester.pumpAndSettle();
      expect(find.text('小林 赞了你的评论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('chat wake-ups stay in chat, not the notification tab',
      (tester) async {
    final client = MockClient((request) async {
      Object body;
      switch (request.url.path) {
        case '/v1/conversations':
          body = {
            'conversations': [
              {
                'friend': {
                  'id': 'friend-1',
                  'nickname': '小林',
                  'avatar': 'book',
                  'vipBadge': false,
                },
                'lastMessage': {'body': '一起复习吧'},
                'unreadCount': 1,
                'updatedAt': '2026-10-20T12:00:00Z',
              }
            ]
          };
        case '/v1/friends':
          body = {'friends': [], 'incoming': [], 'outgoing': []};
        case '/v1/notifications':
          body = {
            // The legacy aggregate may include chat wake-ups. The widget must
            // derive its notification dot from visible, non-chat items.
            'unreadCount': 2,
            'items': [
              {
                'id': 'chat-wakeup',
                'type': 'direct_message',
                'createdAt': '2026-10-20T12:00:00Z',
                'actor': {
                  'id': 'friend-1',
                  'nickname': '小林',
                  'avatar': 'book',
                  'vipBadge': false,
                }
              },
              {
                'id': 'comment-like',
                'type': 'comment_like',
                'createdAt': '2026-10-20T12:01:00Z',
                'actor': {
                  'id': 'friend-2',
                  'nickname': '小周',
                  'avatar': 'book',
                  'vipBadge': false,
                }
              }
            ]
          };
        case '/v1/notifications/read':
          body = {'ok': true, 'unreadCount': 1};
        default:
          return http.Response(jsonEncode({'error': 'unexpected route'}), 500);
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SocialInboxPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // The conversation remains the owner of its single unread indicator.
      expect(find.text('一起复习吧'), findsOneWidget);

      await tester.tap(find.text('通知'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('小林 发来一条消息'), findsNothing);
      expect(find.text('小周 赞了你的评论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('accepted friends are not kept in the sent-request section',
      (tester) async {
    final client = MockClient((request) async {
      final body = switch (request.url.path) {
        '/v1/conversations' => {'conversations': []},
        '/v1/notifications' => {'unreadCount': 0, 'items': []},
        '/v1/friends' => {
            'friends': [
              {
                'id': 'friend-1',
                'nickname': '小林',
                'avatar': 'book',
                'vipBadge': false,
              }
            ],
            // A stale response could contain both records momentarily. The UI
            // must prefer the accepted friendship.
            'outgoing': [
              {
                'id': 'old-request',
                'profile': {
                  'id': 'friend-1',
                  'nickname': '小林',
                  'avatar': 'book',
                  'vipBadge': false,
                }
              }
            ],
            'incoming': [],
          },
        _ => {'ok': true},
      };
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SocialInboxPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('好友'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('已发送'), findsNothing);
      expect(find.text('我的好友'), findsOneWidget);
      expect(find.text('小林'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  testWidgets('desktop thread stays mounted while its read state syncs',
      (tester) async {
    var messageRequests = 0;
    final client = MockClient((request) async {
      Object body;
      switch (request.url.path) {
        case '/v1/conversations':
          body = {
            'conversations': [
              {
                'friend': {
                  'id': 'friend-1',
                  'nickname': '小林',
                  'avatar': 'book',
                  'university': '测试大学',
                  'vipBadge': false,
                },
                'lastMessage': {'body': '一起复习吧'},
                'unreadCount': 1,
                'updatedAt': '2026-10-20T12:00:00Z',
              }
            ]
          };
        case '/v1/friends':
          body = {'friends': [], 'incoming': [], 'outgoing': []};
        case '/v1/notifications':
          body = {'unreadCount': 0, 'items': []};
        case '/v1/conversations/friend-1/messages':
          messageRequests += 1;
          body = {'friend': {}, 'messages': []};
        default:
          return http.Response(jsonEncode({'error': 'unexpected route'}), 500);
      }
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SocialInboxPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.text('小林').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TextField), findsOneWidget);
      expect(messageRequests, 1);
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  for (final width in [360.0, 390.0, 768.0, 1440.0]) {
    testWidgets(
        'older unread notifications can be acknowledged at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var remaining = 87;
      var acknowledgedAll = false;
      final client = MockClient((request) async {
        Object body;
        switch (request.url.path) {
          case '/v1/notifications':
            body = {
              'unreadCount': remaining,
              'items': [
                {'id': 'recent', 'type': 'comment_like', 'actor': {}}
              ]
            };
          case '/v1/notifications/read':
            final payload = jsonDecode(request.body) as Map;
            acknowledgedAll = !payload.containsKey('ids');
            remaining = acknowledgedAll ? 0 : 86;
            body = {'unreadCount': remaining};
          case '/v1/conversations':
            body = {'conversations': []};
          default:
            body = {'friends': [], 'incoming': [], 'outgoing': []};
        }
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
            const MaterialApp(home: SocialInboxPage(initialTab: 2)));
        await tester.pumpAndSettle();
        expect(remaining, 86,
            reason: 'opening a page marks only visible items');
        expect(acknowledgedAll, isFalse);
        expect(app.store.socialUnreadCount, 86);
        await tester.tap(find.text('全部已读'));
        await tester.pumpAndSettle();
        expect(acknowledgedAll, isTrue);
        expect(app.store.socialUnreadCount, 0);
        expect(find.text('全部已读'), findsNothing);
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }

  testWidgets('desktop switches isolate drafts and delayed sends by recipient',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final delayedSend = Completer<http.Response>();
    final sentTo = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/messages')) {
        sentTo.add(request.url.path);
        return delayedSend.future;
      }
      final Object body = switch (request.url.path) {
        '/v1/conversations' => {
            'conversations': [
              for (final name in ['甲', '乙'])
                {
                  'friend': {'id': name, 'nickname': name, 'avatar': 'book'},
                  'lastMessage': {'body': '你好'},
                  'unreadCount': 0,
                }
            ]
          },
        '/v1/notifications' => {'items': [], 'unreadCount': 0},
        '/v1/friends' => {'friends': [], 'incoming': [], 'outgoing': []},
        _ => {'messages': []},
      };
      return http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: SocialInboxPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('甲').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '只给甲的草稿');
      await tester.tap(find.text('乙').first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
          reason: 'a draft must never cross recipient boundaries');
      await tester.tap(find.text('甲').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '只发给甲');
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      await tester.tap(find.text('乙').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '给乙的新草稿');
      delayedSend.complete(http.Response(
          jsonEncode({
            'message': {'body': '只发给甲', 'mine': true}
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
      await tester.pumpAndSettle();
      expect(sentTo, hasLength(1));
      expect(
          Uri.decodeComponent(sentTo.single), '/v1/conversations/甲/messages');
      expect(find.text('只发给甲'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '给乙的新草稿');
      expect(tester.takeException(), isNull);
    }, () => client);
  });

  for (final succeeds in [true, false]) {
    testWidgets('an in-flight send preserves the next draft on $succeeds',
        (tester) async {
      final delivery = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.method == 'POST') return delivery.future;
        return http.Response(jsonEncode({'messages': []}), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
            home: ChatThreadPage(friend: {'id': 'peer', 'nickname': '测试同学'})));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '第一条消息');
        await tester.tap(find.byTooltip('发送'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), '下一条草稿');
        delivery.complete(http.Response(
            jsonEncode(succeeds
                ? {
                    'message': {'body': '第一条消息', 'mine': true}
                  }
                : {'error': '无法发送'}),
            succeeds ? 200 : 403,
            headers: {'content-type': 'application/json; charset=utf-8'}));
        await tester.pumpAndSettle();
        expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '下一条草稿');
        expect(tester.takeException(), isNull);
      }, () => client);
    });
  }
}
