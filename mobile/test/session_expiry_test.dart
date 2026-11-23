import 'dart:async';
import 'dart:convert';

import 'package:dentstudy/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String? savedToken;
  late StudyStore account;
  const sessionChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final savedProgress = jsonEncode({
    'events': [],
    'pending': ['offline-answer'],
    'drafts': {
      'practice': {'id': 'practice', 'index': 2}
    }
  });

  http.Response jsonResult(Map<String, dynamic> fields, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(fields)), status,
          headers: {'Content-Type': 'application/json; charset=utf-8'});

  setUp(() async {
    savedToken = 'old-bearer';
    SharedPreferences.setMockInitialValues({
      'userId': 'learner',
      'email': 'learner@example.test',
      'baseUrl': 'https://test.invalid/api',
      'account:learner': savedProgress,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sessionChannel, (call) async {
      switch (call.method) {
        case 'read':
          return savedToken;
        case 'write':
          savedToken = call.arguments['value'];
          break;
        case 'delete':
          savedToken = null;
          break;
      }
      return null;
    });
    account = StudyStore()
      ..prefs = await SharedPreferences.getInstance()
      ..baseUrl = 'https://test.invalid/api'
      ..userId = 'learner'
      ..email = 'learner@example.test'
      ..token = savedToken!;
  });

  test(
      'expired wallet session survives reload offline and restores its own draft after sign-in',
      () async {
    await http.runWithClient(() async {
      await expectLater(account.stoneWallet(), throwsA(isA<SessionExpired>()));
      expect(account.needsSignIn, isTrue);
      expect(account.token, isEmpty);
      expect(account.canChatWithCompanion, isFalse);
      expect(account.prefs.getString('account:learner'), savedProgress);

      final reopened = StudyStore();
      await reopened.init();
      expect(reopened.needsSignIn, isTrue);
      expect(reopened.drafts['practice']?['index'], 2);
      expect(reopened.pending, ['offline-answer']);
      await reopened.login('learner@example.test', 'password', false);
      expect(reopened.needsSignIn, isFalse);
      expect(reopened.token, 'fresh-bearer');
      expect(reopened.drafts['practice']?['index'], 2);
      expect(reopened.pending, ['offline-answer']);
      expect(reopened.canChatWithCompanion, isTrue);
      final restored = StudyStore();
      await restored.init();
      expect(restored.token, 'fresh-bearer');
    },
        () => MockClient((r) async {
              switch (r.url.path) {
                case '/api/v1/stones':
                  return jsonResult({'error': '请先登录，或登录已过期'}, 401);
                case '/api/v1/auth/login':
                  return jsonResult({
                    'token': 'fresh-bearer',
                    'userId': 'learner',
                    'email': 'learner@example.test'
                  });
                case '/api/v1/profile':
                  return jsonResult({'isAdmin': true});
                case '/api/v1/sync':
                  return jsonResult({'error': 'offline'}, 503);
                default:
                  throw StateError(r.url.toString());
              }
            }));
  });

  test(
      'denied permission, bad password, and an unreachable API preserve a valid login',
      () async {
    for (final path in [
      '/v1/assistant/chat',
      '/v1/auth/login',
      '/v1/profile'
    ]) {
      await http.runWithClient(() async {
        await expectLater(
            account.request(path, path == '/v1/profile' ? null : {}),
            throwsException);
        expect(account.token, 'old-bearer');
        expect(account.needsSignIn, isFalse);
      },
          () => MockClient((r) async => path == '/v1/profile'
              ? throw http.ClientException('offline')
              : jsonResult({'error': '权限或密码错误'}, 401)));
    }
  });

  test('a late rejection cannot expire a newer login', () async {
    final reply = Completer<http.Response>();
    await http.runWithClient(() async {
      final rejected = expectLater(account.profile(), throwsException);
      account.token = 'fresh-bearer';
      reply.complete(jsonResult({'error': '请先登录，或登录已过期'}, 401));
      await rejected;
      expect(account.token, 'fresh-bearer');
      expect(account.prefs.containsKey('expiredStudySession'), isFalse);
    }, () => MockClient((_) => reply.future));
  });

  test(
      'explicit logout succeeds for an already expired session and keeps private progress',
      () async {
    await http.runWithClient(
        account.logout,
        () =>
            MockClient((r) async => jsonResult({'error': '请先登录，或登录已过期'}, 401)));
    expect(account.userId, 'guest');
    expect(account.needsSignIn, isFalse);
    expect(account.prefs.getString('account:learner'), savedProgress);
    expect(account.drafts, isEmpty);
  });
}
