import 'dart:async';
import 'dart:convert';
import 'package:dentstudy/app/app.dart';
import 'package:dentstudy/app/shared.dart' as app;
import 'package:dentstudy/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response reply(Map<String, dynamic> data) =>
    http.Response(jsonEncode(data), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> thread(String id, int count) => {
      'friend': {'id': id, 'nickname': '测试同学', 'avatar': 'book'},
      'unreadCount': count,
      'lastMessage': {'body': '未读私信'},
      'updatedAt': '2026-10-24T12:00:00Z',
    };

StudyStore localStore() => StudyStore()
  ..userId = 'test-user'
  ..token = 'test-token'
  ..baseUrl = 'https://unread-test.invalid';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'chat and notifications share one total, but reading one keeps the other',
      () async {
    final store = localStore();
    var chatRead = false;
    var notificationsRead = false;
    final routes = <String>[];
    await http.runWithClient(() async {
      await store.refreshSocialUnread();
      expect(store.socialUnreadCount, 3);
      expect(
          routes.every((r) => !r.endsWith('/read') && !r.endsWith('/messages')),
          isTrue);
      await store.conversationMessages('a');
      expect(store.socialUnreadCount, 2);
      await store.markNotificationsRead(ids: ['n']);
      expect(store.socialUnreadCount, 1, reason: 'another chat remains unread');
      await store.conversationMessages('b');
      expect(store.socialUnreadCount, 0);
      await store.refreshSocialUnread();
      expect(store.socialUnreadCount, 0);
    },
        () => MockClient((r) async {
              routes.add(r.url.path);
              if (r.url.path == '/v1/conversations') {
                return reply({
                  'conversations': [
                    thread('a', chatRead ? 0 : 1),
                    thread('b', chatRead ? 0 : 1)
                  ]
                });
              }
              if (r.url.path == '/v1/notifications') {
                return reply({
                  'unreadCount': notificationsRead ? 0 : 1,
                  'items': notificationsRead
                      ? []
                      : [
                          {'id': 'n', 'type': 'comment_like'}
                        ]
                });
              }
              if (r.url.path.endsWith('/read')) {
                notificationsRead = true;
                return reply({'ok': true, 'unreadCount': 0});
              }
              chatRead = true;
              return reply({'messages': []});
            }));
    store.dispose();
  });

  test('pagination uses the exact aggregate and failures do not clear red dots',
      () async {
    final store = localStore();
    var fail = false;
    await http.runWithClient(() async {
      await store.refreshSocialUnread();
      expect(store.socialUnreadCount, 87);
      await store.markNotificationsRead(ids: ['n']);
      expect(store.socialUnreadCount, 86);
      fail = true;
      await store.refreshSocialUnread();
      expect(store.socialUnreadCount, 86);
    },
        () => MockClient((r) async {
              if (fail) throw Exception('offline');
              if (r.url.path.endsWith('/read'))
                return reply({'unreadCount': 86});
              if (r.url.path == '/v1/conversations')
                return reply({'conversations': []});
              return reply({
                'unreadCount': 87,
                'items': [
                  {'id': 'n', 'type': 'comment_like'}
                ]
              });
            }));
    store.dispose();
  });

  test('a stale poll cannot restore a conversation dot after reading',
      () async {
    final store = localStore();
    final stale = Completer<http.Response>();
    var lists = 0;
    await http.runWithClient(() async {
      await store.conversations();
      expect(store.socialUnreadCount, 1);
      final pending = store.conversations();
      await store.conversationMessages('a');
      expect(store.socialUnreadCount, 0);
      stale.complete(reply({
        'conversations': [thread('a', 1)]
      }));
      await pending;
      expect(store.socialUnreadCount, 0);
    },
        () => MockClient((r) async {
              if (r.url.path == '/v1/conversations') {
                if (++lists == 2) return stale.future;
                return reply({
                  'conversations': [thread('a', 1)]
                });
              }
              return reply({'messages': []});
            }));
    store.dispose();
  });

  test('a stale notification response cannot undo its read acknowledgement',
      () async {
    final store = localStore();
    final stale = Completer<http.Response>();
    var lists = 0;
    await http.runWithClient(() async {
      await store.notifications();
      final pending = store.notifications();
      await store.markNotificationsRead(ids: ['n']);
      stale.complete(reply({
        'unreadCount': 1,
        'items': [
          {'id': 'n', 'type': 'comment_like'}
        ]
      }));
      await pending;
      expect(store.socialUnreadCount, 0);
    },
        () => MockClient((r) async {
              if (r.url.path.endsWith('/read'))
                return reply({'unreadCount': 0});
              if (++lists == 2) return stale.future;
              return reply({
                'unreadCount': 1,
                'items': [
                  {'id': 'n', 'type': 'comment_like'}
                ]
              });
            }));
    store.dispose();
  });

  test('refreshes deduplicate and account changes cannot inherit unread state',
      () async {
    final store = localStore();
    var requests = 0;
    await http.runWithClient(() async {
      await Future.wait(
          [store.refreshSocialUnread(), store.refreshSocialUnread()]);
      expect(requests, 2);
      expect(store.socialUnreadCount, 1);
      store.token = '';
      expect(store.socialUnreadCount, 0);
      store.userId = 'another-user';
      store.token = 'another-token';
      expect(store.socialUnreadCount, 0);
      await store.refreshSocialUnread();
      expect(store.socialUnreadCount, 0);
    },
        () => MockClient((r) async {
              requests++;
              if (r.url.path == '/v1/conversations')
                return reply({'conversations': []});
              return reply({
                'unreadCount':
                    r.headers['authorization'] == 'Bearer test-token' ? 1 : 0,
                'items': []
              });
            }));
    store.dispose();
  });

  testWidgets('both real entry dots appear on receipt and clear after viewing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.store
      ..prefs = await SharedPreferences.getInstance()
      ..baseUrl = 'https://unread-test.invalid'
      ..userId = 'widget-user'
      ..token = 'widget-token'
      ..email = 'test@example.invalid'
      ..questions = []
      ..events = []
      ..pending = []
      ..drafts = {}
      ..sessions = []
      ..dailyPlan = null
      ..glassEnabled = false
      ..xiaochiEnabled = false;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var chatUnread = 0;
    var noticeUnread = 0;
    const messageDot = ValueKey('profile-message-unread-dot');
    const tabDot = ValueKey('profile-tab-unread-dot');
    void expectDots(bool visible) {
      expect(find.byKey(messageDot), visible ? findsOneWidget : findsNothing);
      expect(find.byKey(tabDot), visible ? findsOneWidget : findsNothing);
    }

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Home(initialTab: 4)));
      await tester.pumpAndSettle();
      expectDots(false);
      chatUnread = 1;
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expectDots(true);
      // Visiting My itself is not an acknowledgement of unseen contents.
      await tester.tap(find.byTooltip('消息'));
      await tester.pumpAndSettle();
      expect(app.store.socialUnreadCount, 1);
      await tester.tap(find.text('未读私信'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expectDots(false);
      noticeUnread = 1;
      await app.store.refreshSocialUnread();
      await tester.pumpAndSettle();
      expectDots(true);
      await tester.tap(find.byTooltip('消息'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通知'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expectDots(false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((r) async {
              if (r.url.path == '/v1/conversations')
                return reply({
                  'conversations': [thread('a', chatUnread)]
                });
              if (r.url.path.endsWith('/messages')) {
                chatUnread = 0;
                return reply({'messages': []});
              }
              if (r.url.path == '/v1/notifications')
                return reply({
                  'unreadCount': noticeUnread,
                  'items': noticeUnread == 0
                      ? []
                      : [
                          {
                            'id': 'n',
                            'type': 'comment_like',
                            'createdAt': '2026-10-24T12:00:00Z'
                          }
                        ]
                });
              if (r.url.path.endsWith('/read')) {
                noticeUnread = 0;
                return reply({'unreadCount': 0});
              }
              if (r.url.path == '/v1/friends')
                return reply({'friends': [], 'incoming': [], 'outgoing': []});
              if (r.url.path == '/v1/profile')
                return reply({'nickname': '测试用户'});
              if (r.url.path == '/v1/stones')
                return reply({'balance': 0, 'items': []});
              if (r.url.path == '/v1/question-bank-submissions')
                return reply({'submissions': []});
              return reply({'events': [], 'settings': null});
            }));
    app.store.token = '';
  });
}
