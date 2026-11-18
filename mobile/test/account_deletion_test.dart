import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/store.dart';
import 'package:dentstudy/features/profile/account_deletion_page.dart';

class DeletionFake extends StudyStore {
  int calls = 0;
  bool fail = false;
  @override
  Future<bool> deleteAccount(String password) async {
    calls++;
    if (fail) throw Exception('账号密码不正确');
    token = '';
    userId = 'guest';
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StudyStore account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'email': 'me@example.test',
      'userId': 'mine',
      'account:mine': '{"events":[],"pending":[]}',
      'account:guest': '{"events":[],"pending":[]}',
      'account:other': '{"events":[],"pending":[]}',
      'reading:mine:考研:章节': 'private',
      'reading:other:考研:章节': 'preserve',
      'importedQuestionBank:mine': '{"questions":[]}',
      'importedQuestionBank:other': 'preserve',
      'themeColorKey': 'teal',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
    account = StudyStore()
      ..prefs = await SharedPreferences.getInstance()
      ..token = 'private-token'
      ..userId = 'mine'
      ..email = 'me@example.test'
      ..baseUrl = 'https://test.invalid/api';
  });

  test('server-confirmed deletion purges only current account cache', () async {
    await http.runWithClient(
        () => account.deleteAccount('correct-password'),
        () => MockClient((request) async {
              expect(request.url.path, '/api/v1/account/delete');
              expect(request.headers['Authorization'], 'Bearer private-token');
              expect(jsonDecode(request.body),
                  {'password': 'correct-password', 'confirmation': 'DELETE'});
              return http.Response(
                  '{"deleted":true,"fileCleanupPending":false}', 200);
            }));
    expect(account.token, isEmpty);
    expect(account.userId, 'guest');
    expect(account.prefs.containsKey('account:mine'), isFalse);
    expect(account.prefs.containsKey('reading:mine:考研:章节'), isFalse);
    expect(account.prefs.containsKey('importedQuestionBank:mine'), isFalse);
    expect(account.prefs.containsKey('account:other'), isTrue);
    expect(account.prefs.containsKey('account:guest'), isTrue);
    expect(account.prefs.getString('reading:other:考研:章节'), 'preserve');
    expect(account.prefs.getString('importedQuestionBank:other'), 'preserve');
    expect(account.prefs.getString('themeColorKey'), 'teal');
    expect(account.prefs.containsKey('deletedAccountCleanup'), isFalse);
    expect(account.deletingAccount, isFalse);
  });

  test('rejected deletion preserves login and local data for retry', () async {
    await http.runWithClient(() async {
      await expectLater(
          account.deleteAccount('wrong-password'), throwsException);
    },
        () => MockClient(
            (_) async => http.Response('{"error":"wrong password"}', 401)));
    expect(account.token, 'private-token');
    expect(account.userId, 'mine');
    expect(account.prefs.containsKey('account:mine'), isTrue);
    expect(account.deletingAccount, isFalse);
  });

  test('deletion does not race an active sync', () async {
    account.syncing = true;
    await expectLater(
        account.deleteAccount('correct-password'), throwsException);
    expect(account.token, 'private-token');
  });

  test('an older profile response cannot repopulate a deleted account',
      () async {
    final response = Completer<http.Response>();
    await http.runWithClient(() async {
      final profile = account.request('/v1/profile');
      final rejected = expectLater(profile, throwsException);
      await account.deleteAccount('correct-password');
      response.complete(http.Response('{"nickname":"old personal data"}', 200));
      await rejected;
      expect(account.userId, 'guest');
    },
        () => MockClient((request) async => request.url.path.endsWith('/delete')
            ? http.Response('{"deleted":true}', 200)
            : await response.future));
  });

  for (final fail in [false, true]) {
    testWidgets('deletion confirmation and ${fail ? "retry" : "success"}',
        (tester) async {
      final fake = DeletionFake()
        ..prefs = account.prefs
        ..email = 'me@example.test'
        ..userId = 'mine'
        ..token = 'private-token'
        ..fail = fail;
      await tester.pumpWidget(
          MaterialApp(home: AccountDeletionPage(accountStore: fake)));
      final submit = find.widgetWithText(FilledButton, '永久删除账号');
      await tester.ensureVisible(submit);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'correct-password');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fake.calls, 0);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认永久删除'));
      await tester.pumpAndSettle();
      expect(fake.calls, 1);
      expect(find.text(fail ? '账号密码不正确' : '账号已删除'), findsOneWidget);
      expect(fake.token.isEmpty, !fail);
      expect(tester.takeException(), isNull);
    });
  }
}
