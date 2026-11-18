import 'dart:convert';
import 'package:dentstudy/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'old downloads receive chapter placement without clearing records or imports',
      () async {
    final bank =
        jsonDecode(await rootBundle.loadString('assets/all_questions.json'));
    final old = Map<String, dynamic>.from(
        (bank['questions'] as List).firstWhere((q) => q['id'] == 'YS1000-0001'))
      ..remove('chapterByMode')
      ..remove('chapterAssignment');
    final cache = jsonEncode({
      'questions': [old]
    });
    final personal = {...old, 'id': 'private-fixture', 'chapter': '私有章节'};
    final history = jsonEncode({
      'events': [
        {
          'id': 'unsynced',
          'questionId': 'YS1000-0001',
          'at': '2026-10-24T01:00:00Z',
          'kind': 'answer',
          'value': {'answer': 'C'}
        }
      ],
      'pending': ['unsynced'],
      'drafts': {},
      'sessions': [],
      'settings': {},
    });
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'publicBankRevision': '20261018-omfs-v1',
      'account:guest': history,
      'questionOverrides': cache,
      'importedQuestionBank:guest': jsonEncode({
        'questions': [personal]
      }),
      'importedQuestionIds:guest': ['private-fixture'],
    });
    final store = StudyStore();
    await store.init();
    final merged = store.questions.firstWhere((q) => q.id == old['id']);
    expect(merged.chapterFor('执医'), '一、牙体解剖');
    expect(merged.chapter, '口腔解剖生理学',
        reason: 'original source chapter stays intact');
    expect(merged.data['answer'], old['answer']);
    expect(store.events.single['id'], 'unsynced');
    expect(store.pending, ['unsynced']);
    expect(store.prefs.getString('account:guest'), history);
    expect(store.prefs.getString('questionOverrides'), cache);
    expect(store.questions.firstWhere((q) => q.id == 'private-fixture').chapter,
        '私有章节');
    expect(store.importedQuestionIds, contains('private-fixture'));
    store.dispose();
  });

  test('old private cache follows its account through login and logout',
      () async {
    final bank =
        jsonDecode(await rootBundle.loadString('assets/all_questions.json'));
    final sample = Map<String, dynamic>.from((bank['questions'] as List).first);
    final guest = {...sample, 'id': 'private-guest'};
    final member = {...sample, 'id': 'private-member'};
    final retired = {...sample, 'id': 'withdrawn-public-question'};
    final original = jsonEncode({
      'events': [],
      'pending': [],
      'drafts': {
        'resume': {
          'id': 'resume',
          'questionIds': ['private-guest'],
          'index': 0,
        }
      },
    });
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'baseUrl': 'https://test.invalid',
      'userId': 'member',
      'bank': jsonEncode({
        'questions': [guest, member, retired],
      }),
      'importedQuestionIds:guest': ['private-guest'],
      'importedQuestionIds:member': ['private-member'],
      'account:guest': original,
    });
    final store = StudyStore();
    await store.init();
    expect(store.userId, 'guest');
    expect(store.importedQuestions.single.id, 'private-guest');
    expect(store.resolveQuestions(['private-member', retired['id']]), isEmpty);
    expect(store.drafts['resume']!['questionIds'], ['private-guest']);
    expect(store.prefs.getString('account:guest'), original);
    expect(store.prefs.containsKey('bank'), isFalse);
    expect(store.prefs.containsKey('importedQuestionBank:member'), isTrue);

    await http.runWithClient(() async {
      await store.login('member@example.invalid', 'test-only-password', false);
      expect(store.importedQuestions.single.id, 'private-member');
      expect(store.resolveQuestions(['private-guest']), isEmpty);
      expect(store.drafts, isEmpty);

      await store.logout();
      expect(store.importedQuestions.single.id, 'private-guest');
      expect(store.resolveQuestions(['private-member']), isEmpty);
      expect(store.drafts['resume']!['questionIds'], ['private-guest']);
    },
        () => MockClient((request) async {
              final Object response = switch (request.url.path) {
                '/v1/auth/login' => {
                    'userId': 'member',
                    'token': 'test-only-token',
                    'email': 'member@example.invalid',
                  },
                '/v1/sync' => {'events': []},
                _ => <String, dynamic>{},
              };
              return http.Response(jsonEncode(response), 200);
            }));
    store.dispose();
  });
}
