import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dentstudy/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Use the cross-platform fake: Web/Wasm does not use the native channel.
    FlutterSecureStorage.setMockInitialValues({});
    if (kIsWeb) {
      // Browser unit tests do not serve the app's 4,210-question asset bundle.
      // Only the fixture bank is mocked; init and preference decoding are real.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
        return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
          'questions': [
            {'id': 'q1'}
          ]
        }))));
      });
    }
  });

  test('startup accepts integer positions restored from legacy web JSON',
      () async {
    SharedPreferences.setMockInitialValues({
      'xiaochiPositionX:guest': 1,
      'xiaochiPositionY:guest': 0,
    });
    final store = StudyStore();
    await store.init();
    expect(store.xiaochiPositionX, 1.0);
    expect(store.xiaochiPositionY, 0.0);
    expect(store.prefs.get('xiaochiPositionX:guest'), 1);
    expect(store.questions, isNotEmpty);
  });

  test(
      'startup accepts integer background controls without deleting the picture',
      () async {
    const picture = 'data:image/jpeg;base64,AQID';
    SharedPreferences.setMockInitialValues({
      'customBackgroundImage': picture,
      'customBackgroundScale': 1,
      'customBackgroundOpacity': 0,
    });
    final store = StudyStore();
    await store.init();
    expect(store.customBackgroundScale, 1.0);
    expect(store.customBackgroundOpacity, 0.0);
    expect(store.customBackgroundImage, picture);
    expect(store.prefs.getString('customBackgroundImage'), picture);
  });

  test(
      'numeric compatibility preserves account records, pending sync and drafts',
      () async {
    final account = jsonEncode({
      'events': [
        {
          'id': 'unsynced',
          'questionId': 'q1',
          'kind': 'note',
          'at': '2026-10-22T12:00:00Z',
          'value': 'keep my note'
        }
      ],
      'pending': ['unsynced'],
      'drafts': {
        'practice': {
          'id': 'practice',
          'questionIds': ['q1'],
          'index': 0
        }
      },
      'sessions': [],
      'settings': {
        'dailyNewLimit': 25,
        'dailyReviewTarget': 10,
        'updatedAt': '2026-10-22T12:00:00Z'
      },
    });
    FlutterSecureStorage.setMockInitialValues({'token': 'test-only-token'});
    SharedPreferences.setMockInitialValues({
      'userId': 'existing-user',
      'account:existing-user': account,
      'learningRecordReset:20261018': 'v1',
      'publicBankRevision': '20261018-omfs-v1',
      'xiaochiPositionX:existing-user': 1,
      'xiaochiPositionY:existing-user': .75,
    });
    final store = StudyStore();
    await store.init();
    expect(store.userId, 'existing-user');
    expect(store.pending, ['unsynced']);
    expect(store.events.single['value'], 'keep my note');
    expect(store.drafts['practice']!['questionIds'], ['q1']);
    expect(store.dailyNewLimit, 25);
    expect(store.dailyReviewTarget, 10);
    expect(store.xiaochiPositionY, .75);
    expect(store.prefs.getString('account:existing-user'), account);
  });

  test('invalid decorative numeric values fall back without rewriting storage',
      () async {
    SharedPreferences.setMockInitialValues({
      'xiaochiPositionX:guest': 'invalid',
      'xiaochiPositionY:guest': 2,
    });
    final store = StudyStore();
    await store.init();
    expect(store.xiaochiPositionX, isNull);
    expect(store.xiaochiPositionY, isNull);
    expect(store.prefs.getString('xiaochiPositionX:guest'), 'invalid');
  });
}
