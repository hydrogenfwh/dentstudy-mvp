import 'dart:async';
import 'dart:convert';

import 'package:dentstudy/models.dart';
import 'package:dentstudy/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  const accountKey = 'flutter.account:guest';
  late Map<String, Object> disk;
  late StudyStore store;
  FutureOr<bool> Function(String)? onAccountWrite;

  const submitted = {
    'answer': 'B',
    'grade': 'wrong',
    'mode': 'practice',
  };

  setUp(() async {
    disk = {};
    onAccountWrite = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll' || call.method == 'getAllWithParameters') {
        return disk;
      }
      if (call.method == 'setString') {
        final key = call.arguments['key'] as String;
        final value = call.arguments['value'] as String;
        if (key == accountKey && onAccountWrite != null) {
          if (!await onAccountWrite!(value)) return false;
        }
        disk[key] = value;
        return true;
      }
      throw StateError('Unexpected preference call: ${call.method}');
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    store = StudyStore()
      ..prefs = prefs
      ..questions = [
        Question({
          'id': 'q1',
          'type': 'A1',
          'options': {'A': '正确', 'B': '错误'},
          'answer': 'A',
        })
      ]
      ..activeSessionId = 'practice';
    await store.saveDraft({
      'id': 'practice',
      'index': 0,
      'questionIds': ['q1'],
      'answers': {'q1': 'B'},
      'saved': <String>[],
      'eventIds': <String>[],
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    store.dispose();
  });

  test('failed write keeps answer draft and retry counts the question once',
      () async {
    final previous = disk[accountKey];
    onAccountWrite = (_) => false;
    await expectLater(store.add('q1', 'review', submitted), throwsException);
    expect(store.events, isEmpty);
    expect(store.pending, isEmpty);
    expect(store.drafts['practice']!['saved'], isEmpty);
    expect(store.prefs.getString('account:guest'), previous);

    onAccountWrite = null;
    await Future.wait([
      store.add('q1', 'review', submitted),
      store.add('q1', 'review', submitted),
    ]);
    final saved = jsonDecode(disk[accountKey] as String);
    expect(store.learning.attempts.single['correct'], false);
    expect(store.learning.states['q1']!.wrong, true);
    expect(store.pending.single, store.events.single['id']);
    expect(saved['drafts']['practice']['saved'], ['q1']);
    expect(saved['drafts']['practice']['eventIds'], store.pending);
  });

  test('checkpoint queued during answer save keeps committed review metadata',
      () async {
    final writing = Completer<void>();
    final release = Completer<bool>();
    onAccountWrite = (_) {
      writing.complete();
      onAccountWrite = null;
      return release.future;
    };
    final review = store.add('q1', 'review', submitted);
    await writing.future;
    final checkpoint = store.saveDraft({
      'id': 'practice',
      'index': 1,
      'answers': {'q1': 'A'},
      'eventIds': <String>[],
    });
    expect(store.events, isEmpty);
    release.complete(true);
    await Future.wait([review, checkpoint]);

    final current = store.drafts['practice']!;
    expect(current['index'], 1);
    expect(current['answers'], {'q1': 'B'});
    expect(current['saved'], ['q1']);
    expect(current['eventIds'], store.pending);
    onAccountWrite = (_) => false;
    await expectLater(
        store.finishSession('practice', current), throwsException);
    expect(store.drafts['practice'], current);
    expect(store.sessions, isEmpty);
    onAccountWrite = null;
    await store.finishSession('practice', current);
    expect(store.drafts, isEmpty);
    expect(store.sessions.single['eventIds'], store.pending);
  });

  test(
      'offline retry uploads the same event ID and leaves retired records local',
      () async {
    store
      ..activeSessionId = null
      ..baseUrl = 'https://test.invalid'
      ..token = 'test-only-token';
    await store.add('retired', 'favorite', true);
    await store.add('q1', 'review', submitted);
    final retiredId = store.pending.first;
    final eventId = store.pending.last;
    var attempts = 0;
    await http.runWithClient(() async {
      await expectLater(store.sync(), throwsException);
      expect(store.pending, [retiredId, eventId]);
      await store.sync();
    },
        () => MockClient((request) async {
              expect(request.url.path, '/v1/sync');
              final outgoing = jsonDecode(request.body)['events'] as List;
              expect(outgoing.single['id'], eventId);
              if (attempts++ == 0) throw http.ClientException('offline');
              return http.Response(jsonEncode({'events': outgoing}), 200);
            }));
    expect(attempts, 2);
    expect(store.pending, [retiredId]);
    expect(store.events.map((e) => e['id']), [retiredId, eventId]);
    expect(store.learning.attempts, hasLength(1));
  });

  test('offline download can be retried without replacing the usable bank',
      () async {
    store.baseUrl = 'https://test.invalid';
    final downloaded = {...store.questions.single.data, 'id': 'downloaded'};
    var attempts = 0;
    await http.runWithClient(() async {
      await expectLater(store.download(), throwsException);
      expect(store.questions.single.id, 'q1');
      expect(disk['flutter.questionOverrides'], isNull);
      await store.download();
    },
        () => MockClient((request) async {
              expect(request.url.path, '/v1/questions');
              if (attempts++ == 0) throw http.ClientException('offline');
              return http.Response(
                  jsonEncode({
                    'questions': [downloaded],
                  }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
            }));
    expect(
        store.questions.map((question) => question.id), ['q1', 'downloaded']);
    final cache = jsonDecode(disk['flutter.questionOverrides'] as String);
    expect(cache['questions'], hasLength(2));
  });
}
