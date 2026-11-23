import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'features/library/catalog.dart';
import 'features/profile/background_image.dart';
import 'app/theme_palette.dart';
import 'app/language_state.dart';

/// The validated, complete JSON sent to the private submission inbox.
///
/// The UI also accepts a smaller learner-friendly shape and expands it into
/// this form before it is stored locally or sent to the server.
class PreparedQuestionBank {
  final String name;
  final String content;
  final List<Question> questions;
  const PreparedQuestionBank(
      {required this.name, required this.content, required this.questions});
}

/// A privacy-safe 小齿 response. [thinkingSummary] is a short learner-facing
/// outline generated for the “深度思考” view; it is never a hidden model trace.
class XiaochiReply {
  final String text;
  final String thinkingSummary;
  const XiaochiReply({required this.text, this.thinkingSummary = ''});
}

class SessionExpired implements Exception {
  const SessionExpired();

  @override
  String toString() => '登录已过期，请重新登录。';
}

class StudyStore extends ChangeNotifier {
  static const maxQuestionBankBytes = 12 * 1024 * 1024;
  late SharedPreferences prefs;
  final secure = const FlutterSecureStorage();
  List<Question> _questions = const [];
  Map<String, Question>? _questionsById;
  final _catalogs = <String, QuestionCatalog>{};

  List<Question> get questions => _questions;
  set questions(List<Question> bank) {
    _questions = List.unmodifiable(bank);
    _questionsById = null;
    _catalogs.clear();
  }
  List<Map<String, dynamic>> events = [];
  List<String> pending = [];
  Map<String, dynamic>? continuation;
  Map<String, Map<String, dynamic>> drafts = {};
  List<Map<String, dynamic>> sessions = [];
  Map<String, dynamic>? dailyPlan;
  Set<String> importedQuestionIds = <String>{};
  String? lastImportedBankName;
  Map<String, Question> _bundledQuestions = <String, Question>{};
  List<Question>? _publicQuestions;
  Map<String, Question> _legacyPrivateQuestions = {};
  String? activeSessionId;
  int _accountGeneration = 0;
  Future<void> _writeQueue = Future.value();
  final List<Map<String, dynamic>> stoneNotices = [];
  final Set<String> _seenStoneNotices = {};
  QuestionCatalog catalogFor(String track) =>
      _catalogs.putIfAbsent(track, () => QuestionCatalog(questions, track));
  QuestionCatalog get catalog => catalogFor(mode);
  String mode = '考研', email = '', userId = 'guest', baseUrl = '', token = '';
  bool get needsSignIn => token.isEmpty && userId != 'guest';
  static const _expiredSessionKey = 'expiredStudySession';
  static String _sessionFingerprint(String credential) =>
      sha256.convert(utf8.encode('dentstudy-expired-session:$credential'))
          .toString();

  String _socialUnreadAccount = '';
  int _notificationUnread = 0, _notificationRevision = 0, _chatRevision = 0;
  bool _legacyNotificationCount = false;
  Set<String> _notificationUnreadIds = {};
  Map<String, int> _chatUnread = {};
  Future<void>? _socialRefresh;
  String _socialRefreshAccount = '';
  String get _socialAccount => token.isEmpty ? '' : '$userId:$token';
  int get socialUnreadCount => _socialUnreadAccount == _socialAccount &&
          token.isNotEmpty
      ? _notificationUnread + _chatUnread.values.fold<int>(0, (a, b) => a + b)
      : 0;

  String _bindSocialUnreadAccount() {
    final account = _socialAccount;
    if (_socialUnreadAccount != account) {
      _socialUnreadAccount = account;
      _notificationUnread = 0;
      _notificationUnreadIds = {};
      _chatUnread = {};
      _legacyNotificationCount = false;
      _notificationRevision++;
      _chatRevision++;
    }
    return account;
  }

  /// Shared by both entry dots. Background failures retain the last confirmed
  /// state; polling never acknowledges a message or notification as read.
  Future<void> refreshSocialUnread() {
    final account = _bindSocialUnreadAccount();
    if (account.isEmpty) return Future<void>.value();
    if (_socialRefreshAccount == account && _socialRefresh != null) {
      return _socialRefresh!;
    }
    Future<void> read(Future<Map<String, dynamic>> Function() fetch) async {
      try {
        await fetch();
      } catch (_) {
        // Optional social sync must not interrupt study or clear unread state.
      }
    }

    final future = Future.wait([read(conversations), read(notifications)])
        .then<void>((_) {});
    _socialRefreshAccount = account;
    _socialRefresh = future;
    return future.whenComplete(() {
      if (identical(_socialRefresh, future)) _socialRefresh = null;
    });
  }

  ThemeMode themeMode = ThemeMode.system;
  String themeColorKey = 'teal';
  String languageCode = 'zh';
  String customPrimaryKey = 'teal', customBackgroundKey = 'teal';
  String? customBackgroundImage;
  Uint8List? customBackgroundImageBytes;
  double customBackgroundScale = 1;
  double customBackgroundOpacity = .42;
  bool glassEnabled = false;
  bool xiaochiEnabled = true;
  String companionAppearance = 'dafeiyu';
  String dafeiyuVoiceMode = 'manual';
  String _companionAuthorScope = '';
  bool _companionAuthorAuthorized = false;
  Future<void>? _companionAccessRefresh;
  String _companionAccessRefreshScope = '';
  String get _currentCompanionScope => '$userId:$token';
  bool get canChatWithCompanion =>
      token.isNotEmpty &&
      userId != 'guest' &&
      _companionAuthorScope == _currentCompanionScope &&
      _companionAuthorAuthorized;
  // Appearance and local actions are public; only AI chat needs author access.
  bool get usesDafeiyu => companionAppearance == 'dafeiyu';
  bool get usesGuga => companionAppearance == 'guga';
  bool get usesLivlivPreview => companionAppearance == 'livliv-preview';
  bool get usesInteractiveCompanion => usesDafeiyu || usesGuga || usesLivlivPreview;
  static const _companionAppearances = {'xiaochi', 'dafeiyu', 'guga', 'livliv-preview'};
  String get companionName => usesLivlivPreview ? 'LivLiv' : usesGuga ? '咕嘎' : (usesDafeiyu ? '大肥鱼' : '小齿');
  double? xiaochiPositionX, xiaochiPositionY;
  int dailyNewLimit = 20;
  int? dailyReviewTarget;
  String settingsUpdatedAt = '1970-01-01T00:00:00.000000Z';
  bool syncing = false;
  bool deletingAccount = false;
  static const _deletedAccountCleanupKey = 'deletedAccountCleanup';
  String syncMessage = '离线学习 · 记录保存在本机';
  LearningState? _learningCache;
  List<Map<String, dynamic>>? _cachedEvents;
  List<Question>? _cachedQuestions;
  int _cachedCount = -1;
  LearningState get learning {
    if (!identical(_cachedEvents, events) ||
        !identical(_cachedQuestions, questions) ||
        _cachedCount != events.length) {
      _learningCache = LearningState(events, questions);
      _cachedEvents = events;
      _cachedQuestions = questions;
      _cachedCount = events.length;
    }
    return _learningCache!;
  }

  List<Question> get bank =>
      questions.where((q) => q.modes.contains(mode)).toList();
  bool get hasCustomBackground => customBackgroundImageBytes != null;
  List<Question> get importedQuestions => questions
      .where((question) => importedQuestionIds.contains(question.id))
      .toList();
  bool hasImportedQuestionBank(PreparedQuestionBank prepared) =>
      prepared.questions.isNotEmpty &&
      prepared.questions
          .every((question) => importedQuestionIds.contains(question.id));
  bool isLocalOnlyQuestionId(Object? questionId) =>
      questionId is String && importedQuestionIds.contains(questionId);
  String get _importedQuestionIdsKey => 'importedQuestionIds:$userId';
  String get _lastImportedBankNameKey => 'lastImportedBankName:$userId';
  String get _importedQuestionBankKey => 'importedQuestionBank:$userId';
  String get _xiaochiEnabledKey => 'xiaochiEnabled:$userId';
  String get _companionAppearanceKey => 'companionAppearance:$userId';
  String get _dafeiyuVoiceModeKey => 'dafeiyuVoiceMode:$userId';
  String get _xiaochiPositionXKey => 'xiaochiPositionX:$userId';
  String get _xiaochiPositionYKey => 'xiaochiPositionY:$userId';
  String get _xiaochiGreetingDateKey => 'xiaochiGreetingDate:$userId';
  static const _webWelcomeCompletedKey = 'webWelcomeCompleted';
  static const _questionOverridesKey = 'questionOverrides';
  static const _publicBankRevisionKey = 'publicBankRevision';
  static const _publicBankRevision = '20261018-omfs-v1';
  // Review-first is account-wide, including questions from other exam tracks.
  List<Question> get due => learning.due(questions, DateTime.now());
  String get today => dayOf(DateTime.now());
  Set<String> get learnedBeforeToday {
    final result = <String>{};
    for (final event in events) {
      if (event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) != today) {
        result.add(event['questionId'] as String);
      }
    }
    return result;
  }

  Set<String> get answeredToday => events
      .where((event) =>
          event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) == today)
      .map((event) => event['questionId'] as String)
      .toSet();
  int get todayNewCount =>
      answeredToday.where((id) => !learnedBeforeToday.contains(id)).length;
  int get todayReviewCount =>
      answeredToday.where(learnedBeforeToday.contains).length;
  int get dailyPracticeLimit => 200;
  int get todayPracticeCount => events
      .where((event) =>
          event['kind'] == 'review' &&
          dayOf(DateTime.parse(event['at'])) == today)
      .length;
  int get remainingPractice {
    final limit = dailyPracticeLimit;
    return (limit - todayPracticeCount).clamp(0, limit);
  }

  int get remainingNew =>
      (dailyNewLimit - todayNewCount).clamp(0, dailyNewLimit);

  /// The welcome screen is a first-visit introduction, not an account switcher.
  /// Authentication itself is restored from secure storage; this small local
  /// preference only prevents the introductory screen from returning after a
  /// learner has already chosen how to enter the app.
  bool get hasCompletedWebWelcome =>
      prefs.getBool(_webWelcomeCompletedKey) ?? false;

  Future<void> completeWebWelcome() =>
      prefs.setBool(_webWelcomeCompletedKey, true);

  // Legacy JavaScript builds encode whole-valued doubles as JSON integers.
  // Wasm distinguishes int from double, so getDouble's direct cast can abort
  // startup after an upgrade. Normalize in memory without rewriting storage.
  double? _preferenceDouble(String key) {
    final value = prefs.get(key);
    return value is num && value.isFinite ? value.toDouble() : null;
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    languageCode = prefs.getString('appLanguage') == 'en' ? 'en' : 'zh';
    setAppLanguage(languageCode);
    final deletedAccount = prefs.getString(_deletedAccountCleanupKey);
    if (deletedAccount != null) await _clearDeletedAccountCache(deletedAccount);
    mode = prefs.getString('mode') ?? '考研';
    baseUrl = prefs.getString('baseUrl') ??
        const String.fromEnvironment('API_URL',
            defaultValue: 'http://10.0.2.2:8787');
    email = prefs.getString('email') ?? '';
    userId = prefs.getString('userId') ?? 'guest';
    // WebKit can deny IndexedDB-backed secure storage in a private window or
    // under restrictive browser settings.  A denied restore must never leave
    // the app on an empty loading screen: it simply starts as a signed-out
    // visitor.  Normal browser sessions still keep the token in secure
    // storage for automatic sign-in.
    try {
      token = await secure.read(key: 'token') ?? '';
    } catch (_) {
      token = '';
    }
    if (token.isEmpty || userId == 'guest') {
      token = '';
      userId = 'guest';
      email = '';
    } else if (prefs.getString(_expiredSessionKey) ==
        _sessionFingerprint(token)) {
      token = '';
      syncMessage = '登录已过期，学习记录保存在本机。';
    }
    // Membership state is server-authoritative.  Do not infer VIP from a
    // browser flag or a past purchase ID: the profile endpoint reflects only
    // verified server-side membership records.
    themeMode = switch (prefs.get('themeMode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    themeColorKey = prefs.getString('themeColorKey') ?? 'teal';
    if (themeColorKey != 'custom' && !themeColors.containsKey(themeColorKey))
      themeColorKey = 'teal';
    customPrimaryKey = prefs.getString('customPrimaryKey') ?? 'teal';
    customBackgroundKey = prefs.getString('customBackgroundKey') ?? 'teal';
    if (!themeColors.containsKey(customPrimaryKey)) customPrimaryKey = 'teal';
    if (!themeColors.containsKey(customBackgroundKey))
      customBackgroundKey = 'teal';
    final savedBackground = prefs.getString('customBackgroundImage');
    if (isStoredBackgroundDataUri(savedBackground)) {
      customBackgroundImage = savedBackground;
      customBackgroundImageBytes = Uint8List.fromList(base64Decode(
          savedBackground!.substring(savedBackground.indexOf(',') + 1)));
      customBackgroundScale = (_preferenceDouble('customBackgroundScale') ?? 1)
          .clamp(.8, 2.4)
          .toDouble();
      customBackgroundOpacity =
          (_preferenceDouble('customBackgroundOpacity') ?? .42)
              .clamp(0, 1)
              .toDouble();
    } else if (savedBackground != null) {
      await prefs.remove('customBackgroundImage');
      await prefs.remove('customBackgroundScale');
      await prefs.remove('customBackgroundOpacity');
    }
    glassEnabled = prefs.getBool('glassEnabled') ?? false;
    const bankAsset = String.fromEnvironment('QUESTION_BANK_ASSET',
        defaultValue: 'assets/all_questions.json');
    final raw = await rootBundle.loadString(bankAsset);
    questions = (jsonDecode(raw)['questions'] as List)
        .map((q) => Question(Map<String, dynamic>.from(q)))
        .toList();
    _bundledQuestions = {
      for (final question in questions) question.id: question
    };
    _loadAccount();
    await _restoreQuestionCache();
  }

  List<Question> _readQuestionCache(String? content) {
    if (content == null || content.isEmpty) return const [];
    try {
      return [
        for (final value in jsonDecode(content)['questions'] as List)
          if (value is Map<String, dynamic> && value['id'] is String)
            Question(value),
      ];
    } catch (_) {
      return const [];
    }
  }

  bool _isBundledQuestion(Question question) {
    final bundled = _bundledQuestions[question.id];
    return bundled != null &&
        (identical(bundled, question) ||
            jsonEncode(bundled.data) == jsonEncode(question.data));
  }

  Question _withBundledCataloguePlacement(Question question) {
    final bundled = _bundledQuestions[question.id];
    if (identical(question, bundled) ||
        bundled?.data['chapterAssignment'] != 'reviewed_legacy_topics_v1') {
      return question;
    }
    // An old downloaded cache may predate view-only chapter placement. Merge
    // just that metadata, never clear cached content, imports or user history.
    final oldPlacement = question.data['chapterByMode'];
    return Question({
      ...question.data,
      'chapterByMode': {
        if (oldPlacement is Map) ...oldPlacement,
        ...(bundled!.data['chapterByMode'] as Map)
      },
      'chapterAssignment': bundled.data['chapterAssignment']
    });
  }

  /// Split the old full-bank cache by owner before retiring it. A public-bank
  /// revision may withdraw public downloads while private imports still work.
  Future<void> _restoreQuestionCache() async {
    _legacyPrivateQuestions = {};
    final legacy = prefs.getString('bank');
    final legacyById = {
      for (final question in _readQuestionCache(legacy)) question.id: question,
    };
    final currentRevision =
        prefs.getString(_publicBankRevisionKey) == _publicBankRevision;
    var overrides = currentRevision
        ? _readQuestionCache(prefs.getString(_questionOverridesKey))
        : <Question>[];
    var migrated = true;
    if (legacyById.isNotEmpty) {
      final privateIds = <String>{};
      const prefix = 'importedQuestionIds:';
      for (final key
          in prefs.getKeys().where((key) => key.startsWith(prefix))) {
        final ids = prefs.getStringList(key) ?? const <String>[];
        privateIds.addAll(ids);
        final account = key.substring(prefix.length);
        final bankKey = 'importedQuestionBank:$account';
        final existing = _readQuestionCache(prefs.getString(bankKey));
        final existingIds = existing.map((question) => question.id).toSet();
        final missing = ids
            .where((id) => !existingIds.contains(id))
            .map((id) => legacyById[id])
            .whereType<Question>()
            .toList();
        if (missing.isEmpty) continue;
        try {
          await _writeQuestionCache(bankKey, [...existing, ...missing]);
        } catch (_) {
          // Safari storage may be full. Keep the legacy copy recoverable.
          migrated = false;
          _legacyPrivateQuestions.addEntries(
              missing.map((question) => MapEntry(question.id, question)));
        }
      }
      if (currentRevision && overrides.isEmpty) {
        overrides = legacyById.values
            .where((question) =>
                !privateIds.contains(question.id) &&
                !_isBundledQuestion(question))
            .toList();
        if (overrides.isNotEmpty) {
          try {
            await _writeQuestionCache(_questionOverridesKey, overrides);
          } catch (_) {
            migrated = false;
          }
        }
      }
    }
    try {
      if (!currentRevision && prefs.containsKey(_questionOverridesKey)) {
        migrated = await prefs.remove(_questionOverridesKey) && migrated;
      }
      if (migrated && legacy != null) migrated = await prefs.remove('bank');
      if (migrated && !currentRevision) {
        await prefs.setString(_publicBankRevisionKey, _publicBankRevision);
      }
    } catch (_) {
      // The bundled bank and scoped imports are still available in memory.
    }
    _setPublicQuestions([..._bundledQuestions.values, ...overrides]);
  }

  Future<void> _writeQuestionCache(String key, List<Question> questions) async {
    if (!await prefs.setString(key,
        jsonEncode({'questions': questions.map((q) => q.data).toList()}))) {
      throw Exception('本机存储空间不足，未能保存题库');
    }
  }

  void _setPublicQuestions(List<Question> bank) {
    _publicQuestions = {
      for (final question in bank)
        question.id: _withBundledCataloguePlacement(question),
    }.values.toList();
    _applyImportedQuestions();
  }

  void _applyImportedQuestions() {
    final imports = {
      for (final id in importedQuestionIds)
        if (_legacyPrivateQuestions.containsKey(id))
          id: _legacyPrivateQuestions[id]!,
      for (final question
          in _readQuestionCache(prefs.getString(_importedQuestionBankKey)))
        question.id: question,
    };
    importedQuestionIds.addAll(imports.keys);
    questions = {
      for (final question in _publicQuestions ?? questions)
        question.id: question,
      ...imports,
    }.values.toList();
  }

  void _loadAccount() {
    final data = jsonDecode(
        prefs.getString('account:$userId') ?? '{"events":[],"pending":[]}');
    events = (data['events'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    pending = List<String>.from(data['pending'] ?? const []);
    final savedContinuation = data['continuation'];
    continuation = savedContinuation is Map
        ? Map<String, dynamic>.from(savedContinuation)
        : null;
    drafts = (data['drafts'] as Map? ?? {})
        .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v)));
    sessions = (data['sessions'] as List? ?? [])
        .map((v) => Map<String, dynamic>.from(v))
        .toList();
    dailyPlan = data['dailyPlan'] is Map
        ? Map<String, dynamic>.from(data['dailyPlan'])
        : null;
    // Older builds saved only the remaining IDs. Preserve those IDs without
    // inventing the answers or elapsed time they never recorded.
    if (continuation != null && !drafts.containsKey('legacy')) {
      drafts['legacy'] = {
        ...continuation!,
        'id': 'legacy',
        'legacy': true,
        'answers': <String, String>{},
        'saved': <String>[],
        'index': 0
      };
      continuation = null;
    }
    final settings = Map<String, dynamic>.from(data['settings'] ?? {});
    dailyNewLimit = settings['dailyNewLimit'] as int? ?? 20;
    dailyReviewTarget = settings['dailyReviewTarget'] as int?;
    settingsUpdatedAt =
        settings['updatedAt'] as String? ?? '1970-01-01T00:00:00.000000Z';
    // Builds before 0.2.49 stored their untouched default as 10 with the
    // epoch timestamp. Preserve intentional choices, but migrate that old
    // implicit default to the new 20-question daily plan.
    if (dailyNewLimit == 10 &&
        settingsUpdatedAt == '1970-01-01T00:00:00.000000Z') {
      dailyNewLimit = 20;
      settingsUpdatedAt = DateTime.now().toUtc().toIso8601String();
    }
    importedQuestionIds =
        (prefs.getStringList(_importedQuestionIdsKey) ?? <String>[]).toSet();
    lastImportedBankName = prefs.getString(_lastImportedBankNameKey);
    xiaochiEnabled = prefs.getBool(_xiaochiEnabledKey) ?? true;
    final savedCompanion = prefs.getString(_companionAppearanceKey);
    companionAppearance =
        _companionAppearances.contains(savedCompanion) && (kIsWeb || savedCompanion != 'livliv-preview')
            ? savedCompanion!
            : 'dafeiyu';
    final voiceMode = prefs.getString(_dafeiyuVoiceModeKey);
    dafeiyuVoiceMode = const {'auto', 'manual', 'off'}.contains(voiceMode)
        ? voiceMode!
        : 'manual';
    final savedX = _preferenceDouble(_xiaochiPositionXKey);
    final savedY = _preferenceDouble(_xiaochiPositionYKey);
    xiaochiPositionX =
        savedX != null && savedX >= 0 && savedX <= 1 ? savedX : null;
    xiaochiPositionY =
        savedY != null && savedY >= 0 && savedY <= 1 ? savedY : null;
  }

  VoidCallback _restoreAccountSnapshot() {
    final previousEvents = events;
    final previousPending = pending;
    final previousContinuation = continuation;
    final previousDrafts = drafts;
    final previousSessions = sessions;
    final previousPlan = dailyPlan;
    final previousNewLimit = dailyNewLimit;
    final previousReviewTarget = dailyReviewTarget;
    final previousSettingsUpdatedAt = settingsUpdatedAt;
    return () {
      events = previousEvents;
      pending = previousPending;
      continuation = previousContinuation;
      drafts = previousDrafts;
      sessions = previousSessions;
      dailyPlan = previousPlan;
      dailyNewLimit = previousNewLimit;
      dailyReviewTarget = previousReviewTarget;
      settingsUpdatedAt = previousSettingsUpdatedAt;
    };
  }

  Future<void> _save(VoidCallback update) async {
    if (deletingAccount) throw Exception('正在删除账号，请稍候');
    final account = userId;
    final generation = _accountGeneration;
    final write = _writeQueue.then((_) async {
      if (generation != _accountGeneration || userId != account) {
        throw Exception('账号状态已变更，请重试');
      }
      // Stage replacements synchronously. Readers keep seeing the previous
      // state until the event log, upload queue and checkpoint are all saved.
      final restore = _restoreAccountSnapshot();
      final String payload;
      final VoidCallback commit;
      try {
        update();
        commit = _restoreAccountSnapshot();
        payload = jsonEncode({
          'events': events,
          'pending': pending,
          if (continuation != null) 'continuation': continuation,
          'settings': settingsPayload,
          'drafts': drafts,
          'sessions': sessions,
          'dailyPlan': dailyPlan,
        });
      } finally {
        restore();
      }
      try {
        if (!await prefs.setString('account:$account', payload)) {
          throw Exception('本机存储失败');
        }
      } catch (_) {
        // SharedPreferences updates its cache before writing to disk.
        try {
          await prefs.reload();
        } catch (_) {}
        rethrow;
      }
      if (generation == _accountGeneration && userId == account) commit();
    });
    _writeQueue = write.catchError((_) {});
    await write;
    notifyListeners();
  }

  List<Question> resolveQuestions(Iterable<dynamic> ids) {
    if (ids.isEmpty) return [];
    final byId = _questionsById ??= {for (final q in questions) q.id: q};
    return ids.map((id) => byId[id]).whereType<Question>().toList();
  }

  Map<String, dynamic> _mergeCheckpoint(
      Map<String, dynamic> value, Map<String, dynamic>? stored) {
    if (stored == null) return value;
    final saved = List<String>.from(stored['saved'] ?? const []);
    final storedAnswers = Map<String, dynamic>.from(stored['answers'] ?? {});
    return {
      ...stored,
      ...value,
      'saved':
          {...saved, ...List<String>.from(value['saved'] ?? const [])}.toList(),
      'eventIds': stored['eventIds'] ?? value['eventIds'] ?? const <String>[],
      'answers': {
        ...Map<String, dynamic>.from(value['answers'] ?? storedAnswers),
        for (final id in saved)
          if (storedAnswers.containsKey(id)) id: storedAnswers[id],
      },
    };
  }

  Future<void> saveDraft(Map<String, dynamic> value) => _save(() {
        final id = value['id'] as String;
        if (sessions.any((session) => session['id'] == id)) return;
        drafts = {...drafts, id: _mergeCheckpoint(value, drafts[id])};
      });

  Future<void> discardDraft(String id) => _save(() {
        drafts = {...drafts}..remove(id);
      });

  Future<void> finishSession(String id, Map<String, dynamic> summary) =>
      _save(() {
        final previous =
            drafts[id] ?? sessions.where((s) => s['id'] == id).firstOrNull;
        drafts = {...drafts}..remove(id);
        sessions = [
          ...sessions.where((s) => s['id'] != id),
          _mergeCheckpoint(summary, previous),
        ];
      });

  Future<void> savePlan(Map<String, dynamic> plan) => _save(() {
        dailyPlan = plan;
      });

  Map<String, dynamic> get settingsPayload => {
        'dailyNewLimit': dailyNewLimit,
        'dailyReviewTarget': dailyReviewTarget,
        'updatedAt': settingsUpdatedAt,
      };

  List<Question> get continuationQuestions {
    final ids = continuation?['questionIds'];
    if (ids is! List) return [];
    return resolveQuestions(ids);
  }

  Future<void> saveContinuation({
    required List<Question> questions,
    required String practiceMode,
    required String kind,
  }) async {
    if (questions.isEmpty) return;
    await _save(() {
      continuation = {
        'questionIds': questions.map((question) => question.id).toList(),
        'practiceMode': practiceMode,
        'kind': kind,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      };
    });
  }

  Future<void> clearContinuation() async {
    if (continuation == null) return;
    await _save(() => continuation = null);
  }

  Future<void> setGoals(int newLimit, int? reviewTarget) async {
    if (newLimit < 0 ||
        newLimit > 1000000 ||
        (reviewTarget != null && (reviewTarget < 0 || reviewTarget > 200))) {
      throw Exception('学习目标超出允许范围');
    }
    await _save(() {
      dailyNewLimit = newLimit;
      dailyReviewTarget = reviewTarget;
      settingsUpdatedAt = DateTime.now().toUtc().toIso8601String();
    });
    if (token.isNotEmpty) {
      try {
        await sync();
      } catch (_) {/* Saved locally and retried on next sync. */}
    }
  }

  Future<void> setMode(String value) async {
    mode = value;
    await prefs.setString('mode', mode);
    notifyListeners();
  }

  /// Local device preference, intentionally available before sign-in.
  Future<void> setLanguage(String value) async {
    final next = value == 'en' ? 'en' : 'zh';
    if (languageCode == next) return;
    languageCode = next;
    setAppLanguage(next);
    notifyListeners();
    await prefs.setString('appLanguage', next);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
    await prefs.setString('themeMode', mode.name);
  }

  Future<void> setThemeColor(String value) async {
    if (value != 'custom' && !themeColors.containsKey(value))
      throw Exception('请选择已有主题色');
    themeColorKey = value;
    await prefs.setString('themeColorKey', value);
    notifyListeners();
  }

  Future<void> setCustomTheme(
      {required String primary, required String background}) async {
    if (!themeColors.containsKey(primary) ||
        !themeColors.containsKey(background)) {
      throw Exception('请从已有颜色中选择');
    }
    customPrimaryKey = primary;
    customBackgroundKey = background;
    await prefs.setString('customPrimaryKey', primary);
    await prefs.setString('customBackgroundKey', background);
    await setThemeColor('custom');
  }

  Future<void> setGlassEnabled(bool value) async {
    glassEnabled = value;
    await prefs.setBool('glassEnabled', value);
    notifyListeners();
  }

  /// 小齿的展示偏好、位置和问候频率仅留在当前设备与当前账号下，
  /// 不参与学习事件同步，也不会影响题库或历史作答。
  Future<void> setXiaochiEnabled(bool value) async {
    if (xiaochiEnabled == value) return;
    xiaochiEnabled = value;
    // Repaint first. A preference write can take a visible moment in Safari,
    // and the companion should respond to the switch instantly.
    notifyListeners();
    await prefs.setBool(_xiaochiEnabledKey, value);
  }

  Future<void> setXiaochiPosition(double x, double y) async {
    xiaochiPositionX = x.clamp(0, 1).toDouble();
    xiaochiPositionY = y.clamp(0, 1).toDouble();
    await prefs.setDouble(_xiaochiPositionXKey, xiaochiPositionX!);
    await prefs.setDouble(_xiaochiPositionYKey, xiaochiPositionY!);
  }

  /// Cosmetic, local-only preference. Never switches AI provider or permissions.
  Future<void> setCompanionAppearance(String value) async {
    if (!_companionAppearances.contains(value)) {
      throw ArgumentError.value(value, 'value', '不支持的搭子形象');
    }
    if (companionAppearance == value) return;
    companionAppearance = value;
    notifyListeners();
    await prefs.setString(_companionAppearanceKey, value);
  }

  Future<void> setDafeiyuVoiceMode(String value) async {
    if (!const {'auto', 'manual', 'off'}.contains(value)) {
      throw ArgumentError.value(value, 'value', '不支持的语音模式');
    }
    if (dafeiyuVoiceMode == value) return;
    dafeiyuVoiceMode = value;
    notifyListeners();
    await prefs.setString(_dafeiyuVoiceModeKey, value);
  }

  Future<bool> claimXiaochiGreeting() async {
    final now = DateTime.now();
    final today = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final previous = prefs.getString(_xiaochiGreetingDateKey);
    if (previous != null) {
      final parsed = DateTime.tryParse(previous);
      if (parsed != null && now.difference(parsed).inDays < 3) return false;
    }
    await prefs.setString(_xiaochiGreetingDateKey, today);
    return true;
  }

  Future<void> setCustomBackground(PreparedBackgroundImage prepared) async {
    if (!themeColors.containsKey(prepared.suggestedThemeKey) ||
        !isStoredBackgroundDataUri(prepared.dataUri)) {
      throw Exception('背景图片格式无效，请重新选择');
    }
    final bytes = Uint8List.fromList(base64Decode(
        prepared.dataUri.substring(prepared.dataUri.indexOf(',') + 1)));
    try {
      await prefs.setString('customBackgroundImage', prepared.dataUri);
      await prefs.setDouble('customBackgroundScale', 1);
      await prefs.setDouble('customBackgroundOpacity', .42);
      await prefs.setString('customPrimaryKey', prepared.suggestedThemeKey);
      await prefs.setString('customBackgroundKey', prepared.suggestedThemeKey);
      await prefs.setString('themeColorKey', 'custom');
    } catch (_) {
      throw Exception('背景保存失败，请换一张更小的图片后重试');
    }
    customBackgroundImage = prepared.dataUri;
    customBackgroundImageBytes = bytes;
    customBackgroundScale = 1;
    customBackgroundOpacity = .42;
    customPrimaryKey = prepared.suggestedThemeKey;
    customBackgroundKey = prepared.suggestedThemeKey;
    themeColorKey = 'custom';
    notifyListeners();
  }

  void previewCustomBackground({double? scale, double? opacity}) {
    if (!hasCustomBackground) return;
    if (scale != null) customBackgroundScale = scale.clamp(.8, 2.4).toDouble();
    if (opacity != null)
      customBackgroundOpacity = opacity.clamp(0, 1).toDouble();
    notifyListeners();
  }

  Future<void> saveCustomBackgroundPresentation() async {
    if (!hasCustomBackground) return;
    await prefs.setDouble('customBackgroundScale', customBackgroundScale);
    await prefs.setDouble('customBackgroundOpacity', customBackgroundOpacity);
  }

  Future<void> clearCustomBackground() async {
    customBackgroundImage = null;
    customBackgroundImageBytes = null;
    customBackgroundScale = 1;
    customBackgroundOpacity = .42;
    await prefs.remove('customBackgroundImage');
    await prefs.remove('customBackgroundScale');
    await prefs.remove('customBackgroundOpacity');
    notifyListeners();
  }

  Future<void> add(String questionId, String kind, dynamic value) async {
    await addMany([
      {'questionId': questionId, 'kind': kind, 'value': value}
    ]);
  }

  Future<void> addMany(List<Map<String, dynamic>> additions) {
    if (additions.isEmpty) return Future<void>.value();
    final sessionId = activeSessionId;
    return _save(() {
      final localSession = drafts[sessionId] ??
          sessions.where((s) => s['id'] == sessionId).firstOrNull;
      final saved = Set<String>.from(localSession?['saved'] ?? const []);
      final remainingAdditions = localSession == null
          ? additions
          : additions
              .where((a) =>
                  a['kind'] != 'review' || saved.add(a['questionId'] as String))
              .toList();
      if (remainingAdditions.isEmpty) return;
      final reviews = remainingAdditions.where((a) => a['kind'] == 'review');
      if (sessionId != null) {
        final freshIds = reviews
            .where((a) =>
                a['value']?['mode'] != 'exam' &&
                learning.states[a['questionId']]?.lastDay == null)
            .map((a) => a['questionId'])
            .toSet();
        if (freshIds.length > remainingNew) {
          throw Exception('今日新题目标已完成，当前作答已保留。');
        }
      }
      if (reviews.length > remainingPractice) {
        throw Exception('今日刷题量已达到 200 道，请明天再继续练习。');
      }
      final random = Random.secure();
      final nextEvents = <Map<String, dynamic>>[];
      for (final addition in remainingAdditions) {
        final id = List.generate(20,
                (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
        nextEvents.add({
          'id': id,
          'at': DateTime.now().toUtc().toIso8601String(),
          ...addition,
        });
      }
      events = [...events, ...nextEvents];
      pending = [
        ...pending,
        for (final event in nextEvents)
          if (!isLocalOnlyQuestionId(event['questionId']))
            event['id'] as String,
      ];
      if (sessionId != null && localSession != null && reviews.isNotEmpty) {
        final recorded = {
          ...localSession,
          'saved': saved.toList(),
          'eventIds': [
            ...List<String>.from(localSession['eventIds'] ?? const []),
            for (final event in nextEvents)
              if (event['kind'] == 'review') event['id'] as String,
          ],
          'answers': {
            ...Map<String, dynamic>.from(localSession['answers'] ?? {}),
            for (final review in reviews)
              review['questionId'] as String: review['value']['answer'],
          }
        };
        if (drafts.containsKey(sessionId)) {
          drafts = {...drafts, sessionId: recorded};
        } else {
          sessions = [
            for (final old in sessions) old['id'] == sessionId ? recorded : old,
          ];
        }
      }
    });
  }

  Future<Map<String, dynamic>> request(String path,
      [Map<String, dynamic>? data,
      Duration timeout = const Duration(seconds: 15),
      bool queueStoneNotices = true]) async {
    if (deletingAccount && path != '/v1/account/delete') {
      throw Exception('正在删除账号，请稍候');
    }
    final configuredBase = baseUrl.trim();
    final relativeBase = configuredBase.startsWith('/');
    final uri = relativeBase
        ? Uri.base
            .resolve('${configuredBase.replaceAll(RegExp(r'/+$'), '')}$path')
        : Uri.parse('${configuredBase.replaceAll(RegExp(r'/+$'), '')}$path');
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty)
      throw Exception('请输入有效的 API 地址');
    if (kReleaseMode && uri.scheme != 'https' && !relativeBase)
      throw Exception('发行版本必须使用 HTTPS 服务');
    final headers = {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token'
    };
    final requestToken = token;
    final response = await (data == null
            ? http.get(uri, headers: headers)
            : http.post(uri, headers: headers, body: jsonEncode(data)))
        .timeout(timeout);
    if (requestToken != token ||
        (deletingAccount && path != '/v1/account/delete')) {
      throw Exception('账号状态已变更，请重试');
    }
    final body = Map<String, dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)));
    // Other routes also use 401 for wrong passwords and restricted features.
    // Only a rejected bearer may suspend this account's network session.
    if (response.statusCode == 401 &&
        requestToken.isNotEmpty &&
        ((path == '/v1/profile' && data == null) ||
            body['error'] == '请先登录，或登录已过期')) {
      final fingerprint = _sessionFingerprint(requestToken);
      token = '';
      syncMessage = '登录已过期，学习记录保存在本机。';
      notifyListeners();
      // Keep drafts and pending writes in their owner's scope. An older tab
      // may only mark its own credential, never erase a fresh browser login.
      try {
        await prefs.setString(_expiredSessionKey, fingerprint);
      } catch (_) {
        // Storage can be unavailable. This tab still stops using the bearer.
      }
      throw const SessionExpired();
    }
    if (response.statusCode >= 400) throw Exception(body['error'] ?? '服务暂不可用');
    var addedStoneNotice = false;
    if (queueStoneNotices) {
      for (final reward in body['stoneRewards'] as List? ?? const []) {
        if (reward is Map && reward['amount'] is int && reward['amount'] > 0) {
          final key = '$userId:${reward['id']}';
          if (_seenStoneNotices.add(key)) {
            stoneNotices
                .add({...Map<String, dynamic>.from(reward), 'userId': userId});
            addedStoneNotice = true;
          }
        }
      }
    }
    if (addedStoneNotice) notifyListeners();
    return body;
  }

  Future<Map<String, dynamic>> stoneWallet({int? before}) =>
      request('/v1/stones${before == null ? '' : '?before=$before'}');

  Future<Map<String, dynamic>> stoneLeaderboard(String scope) {
    if (!const {'today', 'week', 'month', 'all'}.contains(scope)) {
      throw Exception('排行榜范围无效');
    }
    return request('/v1/stones/leaderboard?scope=$scope');
  }

  Future<Map<String, dynamic>> practiceLeaderboard(String scope) {
    if (!const {'today', 'week', 'month', 'all'}.contains(scope)) {
      throw Exception('排行榜范围无效');
    }
    return request('/v1/practice/leaderboard?scope=$scope');
  }

  Future<Map<String, dynamic>> setStoneLeaderboardParticipation(bool enabled) =>
      request('/v1/stones/leaderboard/participation', {'enabled': enabled});

  Future<Map<String, dynamic>> claimShareStone() =>
      request('/v1/stones/share', {'systemShareCompleted': true});

  Future<Map<String, dynamic>> redeemStones(String planId, int priceFen) async {
    final accountId = userId;
    final key = 'stoneRedemption:$accountId:$planId';
    var requestKey = prefs.getString(key);
    if (requestKey == null) {
      final random = Random.secure();
      requestKey = List.generate(
              20, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      if (!await prefs.setString(key, requestKey))
        throw Exception('本机存储失败，请重试');
    }
    if (userId != accountId || token.isEmpty) throw Exception('账号已变更，请重试');
    final result = await request('/v1/stones/redeem', {
      'planId': planId,
      'requestKey': requestKey,
      'expectedPriceFen': priceFen,
    });
    await prefs.remove(key);
    return result;
  }

  Future<void> login(String account, String password, bool register) async {
    if (deletingAccount) throw Exception('正在删除账号，请稍候');
    if (syncing) throw Exception('请等待当前同步完成');
    final result = await request('/v1/auth/${register ? 'register' : 'login'}',
        {'email': account, 'password': password});
    final nextToken = result['token'] as String;
    final nextEmail = result['email'] as String;
    final nextUserId = result['userId'] as String;
    try {
      await secure.write(key: 'token', value: nextToken);
    } catch (_) {
      // The authenticated session remains usable in this tab.  We never
      // downgrade to SharedPreferences, which would persist a bearer token
      // outside secure browser/system storage.
    }
    await prefs.setString('baseUrl', baseUrl);
    await prefs.setString('email', nextEmail);
    await prefs.setString('userId', nextUserId);
    await _switchAccount(nextUserId, nextEmail, nextToken);
    await refreshCompanionAccess();
    try {
      await sync();
    } catch (_) {
      /* Account is valid; pending data remains available for retry. */
    }
  }

  Future<void> importGuest() async {
    if (userId == 'guest' || syncing) return;
    final guest = (jsonDecode(
                prefs.getString('account:guest') ?? '{"events":[]}')['events']
            as List)
        .map((e) => Map<String, dynamic>.from(e));
    final privateIds =
        (prefs.getStringList('importedQuestionIds:guest') ?? const <String>[])
            .toSet();
    privateIds.addAll(
        _readQuestionCache(prefs.getString('importedQuestionBank:guest'))
            .map((question) => question.id));
    await _save(() {
      final ids = events.map((e) => e['id']).toSet();
      final imported = guest
          .where((event) =>
              !privateIds.contains(event['questionId']) && ids.add(event['id']))
          .toList();
      events = [...events, ...imported];
      pending = [...pending, ...imported.map((event) => event['id'] as String)];
    });
    await sync();
  }

  Future<void> _switchAccount(
      String nextUserId, String nextEmail, String nextToken) {
    final change = _writeQueue.then((_) {
      _publicQuestions ??= questions
          .where((question) => !importedQuestionIds.contains(question.id))
          .toList();
      _accountGeneration++;
      userId = nextUserId;
      email = nextEmail;
      token = nextToken;
      activeSessionId = null;
      _loadAccount();
      _applyImportedQuestions();
    });
    _writeQueue = change.catchError((_) {});
    return change;
  }

  Future<void> logout() async {
    if (deletingAccount) throw Exception('正在删除账号，请稍候');
    if (syncing) throw Exception('请等待当前同步完成');
    // Revoke remotely first; on failure retain the session so the user can retry.
    if (token.isNotEmpty) {
      try {
        await request('/v1/auth/logout', {});
      } on SessionExpired {
        // A rejected bearer is already unusable. Finish the requested logout.
      }
    }
    try {
      await secure.delete(key: 'token');
    } catch (_) {
      // The server has already revoked the session.  Clearing in-memory
      // state below keeps the current tab signed out even if storage is
      // unavailable.
    }
    await prefs.remove('email');
    await prefs.remove('userId');
    await _switchAccount('guest', '', '');
    syncMessage = '离线学习 · 记录保存在本机';
    notifyListeners();
  }

  Future<void> _clearDeletedAccountCache(String id) async {
    final scopedKeys = {
      for (final prefix in [
        'account',
        'importedQuestionIds',
        'lastImportedBankName',
        'importedQuestionBank',
        'xiaochiEnabled',
        'companionAppearance',
        'dafeiyuVoiceMode',
        'xiaochiPositionX',
        'xiaochiPositionY',
        'xiaochiGreetingDate'
      ])
        '$prefix:$id',
    };
    for (final key in prefs.getKeys().toList()) {
      if (scopedKeys.contains(key) ||
          key.startsWith('reading:$id:') ||
          key.startsWith('stoneRedemption:$id:')) {
        if (!await prefs.remove(key)) throw Exception('本机数据清理失败，请重新打开应用重试');
      }
    }
    // Invalidate the persisted identity before attempting secure-storage cleanup.
    // A stale token has already been revoked by the server.
    if (!await prefs.remove('email') || !await prefs.remove('userId')) {
      throw Exception('本机登录信息清理失败，请重新打开应用重试');
    }
    await secure.delete(key: 'token');
    await prefs.remove(_deletedAccountCleanupKey);
  }

  /// Returns whether the server is still retrying deletion of a submission file.
  Future<bool> deleteAccount(String password) async {
    if (token.isEmpty || userId == 'guest') throw Exception('请先登录要删除的账号');
    if (syncing || deletingAccount) throw Exception('请等待当前操作完成');
    final deletedId = userId;
    deletingAccount = true;
    notifyListeners();
    var serverDeleted = false;
    try {
      await _writeQueue;
      final result = await request(
          '/v1/account/delete',
          {'password': password, 'confirmation': 'DELETE'},
          const Duration(seconds: 30));
      if (result['deleted'] != true) throw Exception('服务器尚未确认删除，请重试');
      serverDeleted = true;
      if (!await prefs.setString(_deletedAccountCleanupKey, deletedId)) {
        throw Exception('账号已删除；本机存储不可用，请清除本站数据或应用数据');
      }
      await _clearDeletedAccountCache(deletedId);
      return result['fileCleanupPending'] == true;
    } finally {
      if (serverDeleted) {
        await _switchAccount('guest', '', '');
        syncMessage = '账号已删除 · 当前为访客模式';
      }
      deletingAccount = false;
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (token.isEmpty || syncing || deletingAccount) return;
    syncing = true;
    notifyListeners();
    try {
      // Older clients queued events for private or retired questions. Keep
      // those records locally and continue syncing the current public bank.
      await _writeQueue;
      final publicIds = questions
          .where((question) => !isLocalOnlyQuestionId(question.id))
          .map((question) => question.id)
          .toSet();
      List<Map<String, dynamic>> nextBatch() {
        final uploadable = {
          for (final event in events)
            if (publicIds.contains(event['questionId'])) event['id']: event,
        };
        return pending
            .map((id) => uploadable[id])
            .whereType<Map<String, dynamic>>()
            .take(500)
            .toList();
      }

      var outgoing = nextBatch();
      do {
        final ids = outgoing.map((e) => e['id']).toSet();
        final result = await request('/v1/sync', {
          'mode': mode,
          'events': outgoing,
          'settings': settingsPayload,
        });
        final remote =
            (result['events'] as List).map((e) => Map<String, dynamic>.from(e));
        await _save(() {
          final merged = {for (final e in events) e['id'] as String: e};
          for (final e in remote) {
            merged[e['id'] as String] = e;
          }
          events = merged.values.toList();
          pending = pending.where((id) => !ids.contains(id)).toList();
          final remoteSettings = result['settings'];
          if (remoteSettings is Map &&
              (remoteSettings['updatedAt'] as String)
                      .compareTo(settingsUpdatedAt) >=
                  0) {
            dailyNewLimit = remoteSettings['dailyNewLimit'] as int;
            dailyReviewTarget = remoteSettings['dailyReviewTarget'] as int?;
            settingsUpdatedAt = remoteSettings['updatedAt'] as String;
          }
        });
        outgoing = nextBatch();
      } while (outgoing.isNotEmpty);
      syncMessage = '已同步 · ${dayOf(DateTime.now())}'
          '${pending.isEmpty ? '' : ' · ${pending.length} 条记录暂留本机'}';
    } catch (e) {
      if (!needsSignIn) syncMessage = '同步未完成，记录已保留：$e';
      rethrow;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    final result = await request('/v1/questions');
    final updated = (result['questions'] as List)
        .map((q) => Question(Map<String, dynamic>.from(q)))
        .map(_withBundledCataloguePlacement)
        .toList();
    final existing = _publicQuestions ??
        questions.where((question) => !isLocalOnlyQuestionId(question.id));
    final publicBank = {
      for (final question in existing) question.id: question,
      for (final question in updated) question.id: question,
    }.values.toList();
    await _writeQuestionCache(_questionOverridesKey,
        publicBank.where((question) => !_isBundledQuestion(question)).toList());
    _setPublicQuestions(publicBank);
    notifyListeners();
  }

  PreparedQuestionBank prepareQuestionBankImport(String content) {
    if (content.trim().isEmpty) throw Exception('题库文件为空');
    final bytes = utf8.encode(content).length;
    if (bytes > maxQuestionBankBytes) throw Exception('题库文件不能超过 12 MB');
    final normalized = _normalizeImportedBank(content);
    final normalizedContent = jsonEncode(normalized);
    if (utf8.encode(normalizedContent).length > maxQuestionBankBytes) {
      throw Exception('题库补全后的文件超过 12 MB，请拆分后再上传');
    }
    return PreparedQuestionBank(
        name: normalized['name'] as String,
        content: normalizedContent,
        questions: _readImportedQuestions(normalizedContent));
  }

  Future<int> importPreparedQuestionBank(PreparedQuestionBank prepared) async {
    final imported = prepared.questions;
    final existing = questions.map((question) => question.id).toSet();
    final conflict = imported
        .map((question) => question.id)
        .where(existing.contains)
        .firstOrNull;
    if (conflict != null) {
      throw Exception('题目 ID “$conflict” 已存在；为保护既有学习记录，请更换题目 ID 后再导入。');
    }
    final before = questions;
    final existingImported = questions
        .where((question) => importedQuestionIds.contains(question.id))
        .toList();
    questions = [...questions, ...imported];
    try {
      // Never duplicate the bundled bank in SharedPreferences. Storing only
      // personal imports keeps Safari's site storage free for study records.
      if (!await prefs.setString(
          _importedQuestionBankKey,
          jsonEncode({
            'questions': [
              ...existingImported.map((question) => question.data),
              ...imported.map((question) => question.data),
            ]
          }))) {
        throw Exception('本机存储空间不足，未能保存导入题库');
      }
    } catch (_) {
      questions = before;
      rethrow;
    }
    importedQuestionIds = {
      ...importedQuestionIds,
      ...imported.map((q) => q.id)
    };
    lastImportedBankName = prepared.name;
    if (!await prefs.setStringList(
        _importedQuestionIdsKey, importedQuestionIds.toList()..sort())) {
      throw Exception('本机存储空间不足，未能记录导入题库');
    }
    if (!await prefs.setString(_lastImportedBankNameKey, prepared.name)) {
      throw Exception('本机存储空间不足，未能记录导入题库');
    }
    await _save(() => dailyPlan = null);
    return imported.length;
  }

  Future<int> importQuestionBank(String content) async =>
      importPreparedQuestionBank(prepareQuestionBankImport(content));

  Future<Map<String, dynamic>> submitQuestionBank({
    required String filename,
    required String content,
  }) async {
    if (token.isEmpty) throw Exception('请先登录后再提交题库');
    return request(
        '/v1/question-bank-submissions',
        {'filename': filename, 'content': content},
        const Duration(seconds: 60));
  }

  /// Sends source text only after the learner explicitly chooses AI
  /// conversion in the import dialog. The returned JSON still goes through
  /// [prepareQuestionBankImport] before it can reach local storage.
  Future<Map<String, dynamic>> prepareQuestionBankWithAi({
    required String text,
    required String name,
    required String subject,
    required String chapter,
    required String mode,
  }) async {
    if (token.isEmpty) throw Exception('请先登录后再使用 AI 整理');
    final result = await request(
        '/v1/ai/question-bank/prepare',
        {
          'text': text,
          'name': name,
          'subject': subject,
          'chapter': chapter,
          'mode': mode,
        },
        const Duration(seconds: 90));
    if (result['filename'] is! String || result['content'] is! String) {
      throw Exception('AI 返回内容不完整，请使用本地格式整理');
    }
    return result;
  }

  /// Sends only the current message and a tiny in-memory conversation window.
  /// Neither the app nor the API saves the transcript as a learning record.
  Future<XiaochiReply> chatWithXiaochi({
    required String message,
    required List<Map<String, String>> history,
    bool deep = false,
  }) async {
    if (usesLivlivPreview) throw Exception('请从 LivLiv 互动空间与当前角色聊天');
    if (usesGuga) throw Exception('咕嘎暂不支持 AI 聊天');
    if (token.isEmpty) throw Exception('请先登录后再和$companionName聊天');
    if (!canChatWithCompanion) throw Exception('AI 聊天目前仅作者可用');
    final text = message.trim();
    if (text.isEmpty || text.length > 1000) {
      throw Exception('消息长度为 1–1000 个字');
    }
    final result = await request(
        '/v1/assistant/chat',
        {
          'message': text,
          'history': history
              .take(6)
              .map((item) => {
                    'role': item['role'] ?? '',
                    'content': item['content'] ?? '',
                  })
              .toList(),
          'deep': deep,
          'companion': usesDafeiyu ? 'dafeiyu' : 'xiaochi',
        },
        const Duration(seconds: 45));
    final reply = result['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw Exception('$companionName没有返回可用回复，请稍后再试');
    }
    final summary = result['thinkingSummary'];
    return XiaochiReply(
        text: reply.trim(),
        thinkingSummary: summary is String ? summary.trim() : '');
  }

  Future<Map<String, dynamic>> questionBankSubmissions() async {
    if (token.isEmpty) throw Exception('请先登录');
    return request('/v1/question-bank-submissions');
  }

  Future<Map<String, dynamic>> downloadQuestionBankSubmission(
      String submissionId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,100}$').hasMatch(submissionId)) {
      throw Exception('投稿编号无效');
    }
    return request('/v1/admin/question-bank-submissions/$submissionId', null,
        const Duration(seconds: 60));
  }

  Future<Map<String, dynamic>> profile() async {
    if (token.isEmpty) throw Exception('请先登录');
    final scope = _currentCompanionScope;
    final result =
        await request('/v1/profile', null, const Duration(seconds: 10));
    if (scope == _currentCompanionScope) {
      final before = canChatWithCompanion;
      _companionAuthorScope = scope;
      _companionAuthorAuthorized = result['isAdmin'] == true;
      if (before != canChatWithCompanion) notifyListeners();
    }
    return result;
  }

  /// Server-confirmed, in-memory capability; never trust email or preferences.
  Future<void> refreshCompanionAccess() {
    if (token.isEmpty || userId == 'guest') return Future<void>.value();
    final scope = _currentCompanionScope;
    if (_companionAccessRefreshScope == scope &&
        _companionAccessRefresh != null) {
      return _companionAccessRefresh!;
    }
    Future<void> load() async {
      try {
        await profile();
      } catch (_) {
        if (scope == _currentCompanionScope) {
          final before = canChatWithCompanion;
          _companionAuthorScope = scope;
          _companionAuthorAuthorized = false;
          if (before) notifyListeners();
        }
      }
    }

    final pending = load();
    _companionAccessRefreshScope = scope;
    _companionAccessRefresh = pending;
    return pending.whenComplete(() {
      if (identical(_companionAccessRefresh, pending))
        _companionAccessRefresh = null;
    });
  }

  Future<Map<String, dynamic>> paymentPreview() async {
    if (token.isEmpty) throw Exception('请先登录');
    return request('/v1/admin/payment-preview');
  }

  Future<Map<String, dynamic>> alipayOffer() async {
    if (token.isEmpty) throw Exception('请先登录后查看会员服务');
    return request('/v1/payments/alipay/offer');
  }

  Future<Map<String, dynamic>> vipPlans() => request('/v1/vip/plans');

  Future<Map<String, dynamic>> checkinCalendar(int year) async {
    if (token.isEmpty) throw Exception('请先登录后查看签到日历');
    return request('/v1/checkins?year=$year');
  }

  Future<Map<String, dynamic>> checkinToday() async {
    if (token.isEmpty) throw Exception('请先登录后签到');
    return request('/v1/checkins', {}, const Duration(seconds: 15), false);
  }

  Future<Map<String, dynamic>> makeupCheckin(String day) async {
    if (token.isEmpty) throw Exception('请先登录后补签');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw Exception('补签日期无效');
    }
    return request('/v1/checkins/makeup', {'date': day},
        const Duration(seconds: 15), false);
  }

  Future<Map<String, dynamic>> createAlipayCheckout(String planId,
      {bool mobileWeb = false}) async {
    if (token.isEmpty) throw Exception('请先登录后再开通会员');
    return request('/v1/payments/alipay/checkout', {
      'planId': planId,
      // This only chooses Alipay's browser-facing cashier product. The
      // server still fixes the amount, plan, order ownership and signature.
      'checkoutMode': mobileWeb ? 'mobile_web' : 'desktop',
    });
  }

  Future<Map<String, dynamic>> alipayOrderStatus(String orderId) async {
    if (!RegExp(r'^DS[a-f0-9]{40}$').hasMatch(orderId)) {
      throw Exception('订单编号无效');
    }
    if (token.isEmpty) throw Exception('请先登录后查看支付结果');
    return request('/v1/payments/alipay/orders/$orderId');
  }

  Future<Map<String, dynamic>> updateProfile({
    required String nickname,
    required String avatar,
    required String university,
  }) async {
    if (token.isEmpty) throw Exception('请先登录');
    return request('/v1/profile', {
      'nickname': nickname,
      'avatar': avatar,
      'university': university,
    });
  }

  Future<Map<String, dynamic>> questionComments(String questionId) async {
    return request('/v1/questions/${Uri.encodeComponent(questionId)}/comments');
  }

  Future<Map<String, dynamic>> postQuestionComment(
      String questionId, String body,
      {String? parentId}) async {
    if (token.isEmpty) throw Exception('登录后即可参与讨论');
    return request('/v1/questions/${Uri.encodeComponent(questionId)}/comments',
        {'body': body, if (parentId != null) 'parentId': parentId});
  }

  Future<Map<String, dynamic>> voteComment(String commentId, int value) async =>
      request('/v1/comments/${Uri.encodeComponent(commentId)}/vote',
          {'value': value});

  Future<void> deleteComment(String commentId) async {
    await request('/v1/comments/${Uri.encodeComponent(commentId)}/delete', {});
  }

  Future<Map<String, dynamic>> authorComments({int offset = 0}) async =>
      request('/v1/admin/comments?offset=$offset');

  Future<Map<String, dynamic>> authorUsers() async {
    if (token.isEmpty) throw Exception('请先登录');
    return request('/v1/admin/users');
  }

  /// Social endpoints never return account email addresses.  They are kept
  /// here (rather than in the widgets) so every request consistently carries
  /// the authenticated bearer token and benefits from [request]'s HTTPS rules.
  Future<Map<String, dynamic>> searchPeople(String query) async {
    if (token.isEmpty) throw Exception('请先登录后查找同学');
    final normalized = query.trim();
    if (normalized.runes.length < 2 || normalized.runes.length > 40) {
      throw Exception('昵称搜索需为 2–40 个字');
    }
    return request(
        '/v1/users/search?q=${Uri.encodeQueryComponent(normalized)}');
  }

  /// Load the privacy-filtered card opened from an avatar.  The server decides
  /// whether the caller is the configured author before it includes an email;
  /// widgets must never infer that privilege from a local address string.
  Future<Map<String, dynamic>> userCard(String userId) async {
    if (token.isEmpty) throw Exception('请先登录后查看用户资料');
    if (userId.trim().isEmpty) throw Exception('用户信息不完整');
    return request('/v1/users/${Uri.encodeComponent(userId)}');
  }

  Future<Map<String, dynamic>> friends() async {
    if (token.isEmpty) throw Exception('请先登录后查看好友');
    return request('/v1/friends');
  }

  Future<Map<String, dynamic>> sendFriendRequest(String userId) async {
    if (token.isEmpty) throw Exception('请先登录后添加好友');
    if (userId.trim().isEmpty) throw Exception('用户信息不完整');
    return request('/v1/friends/requests', {'userId': userId});
  }

  Future<Map<String, dynamic>> respondToFriendRequest(
      String requestId, bool accept) async {
    if (token.isEmpty) throw Exception('请先登录后处理好友申请');
    if (requestId.trim().isEmpty) throw Exception('好友申请信息不完整');
    return request(
        '/v1/friends/requests/${Uri.encodeComponent(requestId)}/${accept ? 'accept' : 'reject'}',
        {});
  }

  Future<Map<String, dynamic>> removeFriend(String userId) async {
    if (token.isEmpty) throw Exception('请先登录后管理好友');
    if (userId.trim().isEmpty) throw Exception('用户信息不完整');
    return request('/v1/friends/${Uri.encodeComponent(userId)}/remove', {});
  }

  Future<Map<String, dynamic>> blockUser(String userId) async {
    if (token.isEmpty) throw Exception('请先登录后管理屏蔽名单');
    if (userId.trim().isEmpty) throw Exception('用户信息不完整');
    return request('/v1/friends/${Uri.encodeComponent(userId)}/block', {});
  }

  Future<Map<String, dynamic>> unblockUser(String userId) async {
    if (token.isEmpty) throw Exception('请先登录后管理屏蔽名单');
    if (userId.trim().isEmpty) throw Exception('用户信息不完整');
    return request('/v1/friends/${Uri.encodeComponent(userId)}/unblock', {});
  }

  Future<Map<String, dynamic>> notifications() async {
    if (token.isEmpty) throw Exception('请先登录后查看消息');
    final account = _bindSocialUnreadAccount();
    final revision = _notificationRevision;
    final result = await request('/v1/notifications?limit=50');
    if (account == _socialAccount && revision == _notificationRevision) {
      final before = socialUnreadCount;
      final items = (result['items'] as List? ?? []).whereType<Map>();
      _legacyNotificationCount =
          items.any((item) => item['type'] == 'direct_message');
      _notificationUnreadIds = items
          .where((item) =>
              item['type'] != 'direct_message' && item['readAt'] == null)
          .map((item) => item['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      _notificationUnread = _legacyNotificationCount
          ? _notificationUnreadIds.length
          : max(
              0,
              (result['unreadCount'] as num?)?.toInt() ??
                  _notificationUnreadIds.length);
      if (before != socialUnreadCount) notifyListeners();
    }
    return result;
  }

  Future<Map<String, dynamic>> markNotificationsRead(
      {List<String>? ids}) async {
    if (token.isEmpty) throw Exception('请先登录后查看消息');
    final account = _bindSocialUnreadAccount();
    _notificationRevision++;
    final result = await request('/v1/notifications/read', {
      if (ids != null && ids.isNotEmpty) 'ids': ids,
    });
    if (account == _socialAccount) {
      _notificationRevision++;
      final before = socialUnreadCount;
      if (ids == null || ids.isEmpty) {
        _notificationUnreadIds.clear();
      } else {
        _notificationUnreadIds.removeAll(ids);
      }
      _notificationUnread = _legacyNotificationCount
          ? _notificationUnreadIds.length
          : max(
              0,
              (result['unreadCount'] as num?)?.toInt() ??
                  _notificationUnreadIds.length);
      if (before != socialUnreadCount) notifyListeners();
    }
    return result;
  }

  Future<Map<String, dynamic>> conversations() async {
    if (token.isEmpty) throw Exception('请先登录后查看消息');
    final account = _bindSocialUnreadAccount();
    final revision = _chatRevision;
    final result = await request('/v1/conversations');
    if (account == _socialAccount && revision == _chatRevision) {
      final before = socialUnreadCount;
      _chatUnread = {
        for (final item
            in (result['conversations'] as List? ?? []).whereType<Map>())
          if (item['friend'] is Map && (item['friend'] as Map)['id'] is String)
            (item['friend'] as Map)['id'] as String:
                max(0, (item['unreadCount'] as num?)?.toInt() ?? 0)
      };
      if (before != socialUnreadCount) notifyListeners();
    }
    return result;
  }

  Future<Map<String, dynamic>> conversationMessages(String friendId) async {
    if (token.isEmpty) throw Exception('请先登录后查看聊天');
    if (friendId.trim().isEmpty) throw Exception('好友信息不完整');
    final account = _bindSocialUnreadAccount();
    _chatRevision++;
    final result = await request(
        '/v1/conversations/${Uri.encodeComponent(friendId)}/messages');
    if (account == _socialAccount) {
      _chatRevision++;
      final before = socialUnreadCount;
      _chatUnread.remove(friendId);
      if (before != socialUnreadCount) notifyListeners();
    }
    return result;
  }

  Future<Map<String, dynamic>> sendConversationMessage(
      String friendId, String body) async {
    if (token.isEmpty) throw Exception('请先登录后发送消息');
    final normalized = body.trim();
    if (friendId.trim().isEmpty) throw Exception('好友信息不完整');
    if (normalized.isEmpty || normalized.runes.length > 1000) {
      throw Exception('消息长度为 1–1000 个字');
    }
    return request(
        '/v1/conversations/${Uri.encodeComponent(friendId)}/messages',
        {'body': normalized});
  }

  /// A structured question card is safer than pasting question text/answers
  /// into a chat body.  The backend validates the canonical question ID and
  /// permits this only for accepted friends.
  Future<Map<String, dynamic>> shareQuestionInConversation(
      String friendId, String questionId) async {
    if (token.isEmpty) throw Exception('请先登录后分享题目');
    if (friendId.trim().isEmpty || questionId.trim().isEmpty) {
      throw Exception('题目或好友信息不完整');
    }
    return request(
        '/v1/conversations/${Uri.encodeComponent(friendId)}/questions',
        {'questionId': questionId});
  }
}

List<Question> _readImportedQuestions(String content) {
  dynamic decoded;
  try {
    decoded = jsonDecode(content.replaceFirst('\uFEFF', ''));
  } on FormatException {
    throw Exception('文件不是有效 JSON');
  }
  if (decoded is! Map || decoded['questions'] is! List) {
    throw Exception('题库顶层必须是包含 questions 数组的 JSON 对象');
  }
  final rawQuestions = decoded['questions'] as List;
  if (rawQuestions.isEmpty) throw Exception('题库至少需要 1 道题');
  final ids = <String>{};
  final result = <Question>[];
  for (var index = 0; index < rawQuestions.length; index++) {
    final raw = rawQuestions[index];
    if (raw is! Map) throw Exception('第 ${index + 1} 题必须是对象');
    final question = Map<String, dynamic>.from(raw);
    const required = [
      'id',
      'subject',
      'chapter',
      'type',
      'stem',
      'options',
      'answer',
      'explanation',
      'warning',
      'reference',
      'citation',
      'tags',
      'topics',
      'modes',
      'paperId',
      'paperName',
      'durationMinutes',
      'order',
      'points',
      'isDemo',
      'reviewStatus',
      'sourceType',
      'license'
    ];
    final missing = required.where((field) => !question.containsKey(field));
    if (missing.isNotEmpty) {
      throw Exception('第 ${index + 1} 题缺少 ${missing.first} 字段，请使用题库模板');
    }
    final id = question['id'];
    if (id is! String || id.trim().isEmpty || !ids.add(id)) {
      throw Exception('第 ${index + 1} 题的 id 为空或重复');
    }
    for (final field in [
      'subject',
      'chapter',
      'type',
      'stem',
      'explanation',
      'warning',
      'reference',
      'paperId',
      'paperName',
      'license'
    ]) {
      if (question[field] is! String ||
          (question[field] as String).trim().isEmpty) {
        throw Exception('第 ${index + 1} 题的 $field 必须是非空文字');
      }
    }
    if (question['options'] is! Map ||
        !(question['options'] as Map)
            .entries
            .every((entry) => entry.key is String && entry.value is String)) {
      throw Exception('第 ${index + 1} 题的 options 必须是选项文字映射');
    }
    final options = Map<String, String>.from(question['options'] as Map);
    final subjective = question['type'] == '简答题' || question['type'] == '案例分析';
    if (!subjective &&
        (options.length < 2 || !options.containsKey(question['answer']))) {
      throw Exception('第 ${index + 1} 题至少需要两个选项，且答案必须属于选项');
    }
    if (subjective && question['answer'] != null) {
      throw Exception('第 ${index + 1} 题为主观题时 answer 必须为 null');
    }
    for (final field in ['tags', 'topics', 'modes']) {
      if (question[field] is! List ||
          !(question[field] as List).every((value) => value is String)) {
        throw Exception('第 ${index + 1} 题的 $field 必须是文字数组');
      }
    }
    if ((question['modes'] as List).isEmpty) {
      throw Exception('第 ${index + 1} 题至少要指定一个学习方向');
    }
    result.add(Question(question));
  }
  return result;
}

const _importRequiredFields = [
  'id',
  'subject',
  'chapter',
  'type',
  'stem',
  'options',
  'answer',
  'explanation',
  'warning',
  'reference',
  'citation',
  'tags',
  'topics',
  'modes',
  'paperId',
  'paperName',
  'durationMinutes',
  'order',
  'points',
  'isDemo',
  'reviewStatus',
  'sourceType',
  'license'
];

Map<String, dynamic> _normalizeImportedBank(String content) {
  dynamic decoded;
  try {
    decoded = jsonDecode(content.replaceFirst('\uFEFF', ''));
  } on FormatException {
    throw Exception('文件不是有效 JSON，请从模板复制后再填写');
  }
  final Map<String, dynamic> bank;
  if (decoded is List) {
    bank = {'name': '用户导入题库', 'questions': decoded};
  } else if (decoded is Map) {
    bank = Map<String, dynamic>.from(decoded);
  } else {
    throw Exception('题库顶层应为 questions 数组，或直接是题目数组');
  }
  if (bank['questions'] is! List) {
    throw Exception('题库顶层必须包含 questions 数组');
  }
  final rawQuestions = bank['questions'] as List;
  if (rawQuestions.isEmpty) throw Exception('题库至少需要 1 道题');
  final suppliedName = bank['name'];
  final name = suppliedName is String && suppliedName.trim().isNotEmpty
      ? suppliedName.trim()
      : '用户导入题库';
  final normalized = <Map<String, dynamic>>[];
  for (var index = 0; index < rawQuestions.length; index++) {
    final raw = rawQuestions[index];
    if (raw is! Map) throw Exception('第 ${index + 1} 题必须是 JSON 对象');
    final question = Map<String, dynamic>.from(raw);
    final canonical =
        _importRequiredFields.every((field) => question.containsKey(field));
    normalized.add(canonical
        ? question
        : _normalizeSimpleImportedQuestion(question, index + 1, name));
  }
  return {'version': 1, 'name': name, 'questions': normalized};
}

Map<String, dynamic> _normalizeSimpleImportedQuestion(
    Map<String, dynamic> raw, int position, String bankName) {
  String requiredText(String field, {String? fallback}) {
    final value = raw[field];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (fallback != null) return fallback;
    throw Exception('第 $position 题的 $field 不能为空');
  }

  final subject = requiredText('subject');
  if (!subjects.contains(subject)) {
    throw Exception('第 $position 题的 subject 不在支持科目中，请按模板填写');
  }
  var type = raw['type'] is String ? (raw['type'] as String).trim() : 'A1';
  if (type == '单选题') type = 'A1';
  if (!const ['A1', 'A2'].contains(type)) {
    throw Exception('简化模板暂只支持 A1 或 A2；共用题干请使用完整 JSON 格式');
  }
  final options = _simpleOptions(raw['options'], position);
  final answer = requiredText('answer');
  if (!options.containsKey(answer)) {
    throw Exception('第 $position 题的 answer 必须与选项编号一致，例如 A');
  }
  final chapter = requiredText('chapter', fallback: '未分类章节');
  final stem = requiredText('stem');
  final id = raw['id'] is String && (raw['id'] as String).trim().isNotEmpty
      ? (raw['id'] as String).trim()
      : _generatedImportedId(raw, position);
  final modes = _stringList(raw['modes'], fallback: const ['考研']);
  if (modes.isEmpty ||
      modes.any((mode) => !const ['考研', '本科期末', '执医'].contains(mode))) {
    throw Exception('第 $position 题的 modes 仅可使用 考研、本科期末、执医');
  }
  final tags = _stringList(raw['tags'], fallback: const ['用户导入', '待医学审核']);
  final topics = _stringList(raw['topics'], fallback: [chapter]);
  final reference = requiredText('reference', fallback: '用户自有学习资料');
  final explanation = requiredText('explanation', fallback: '导入资料未提供详细解析。');
  final warning = requiredText('warning', fallback: '请结合教材、课程与专业教师意见核对。');
  final citation = raw['citation'] is Map
      ? Map<String, dynamic>.from(raw['citation'] as Map)
      : <String, dynamic>{'verified': false, 'title': reference};
  final duration = raw['durationMinutes'];
  final order = raw['order'];
  final points = raw['points'];
  return {
    'id': id,
    'subject': subject,
    'chapter': chapter,
    'type': type,
    'stem': stem,
    'options': options,
    'answer': answer,
    'explanation': explanation,
    'warning': warning,
    'reference': reference,
    'citation': citation,
    'tags': tags,
    'topics': topics,
    'modes': modes,
    'paperId':
        raw['paperId'] is String && (raw['paperId'] as String).trim().isNotEmpty
            ? (raw['paperId'] as String).trim()
            : 'user-import-$subject-$chapter',
    'paperName': raw['paperName'] is String &&
            (raw['paperName'] as String).trim().isNotEmpty
        ? (raw['paperName'] as String).trim()
        : '$subject · $bankName（用户导入）',
    'durationMinutes': duration is int && duration > 0 ? duration : 60,
    'order': order is int && order > 0 ? order : position,
    'points': points is int && points > 0 ? points : 1,
    'isDemo': false,
    'reviewStatus': 'draft',
    'sourceType': 'user_material',
    'license':
        raw['license'] is String && (raw['license'] as String).trim().isNotEmpty
            ? (raw['license'] as String).trim()
            : '用户提供资料；仅供本地学习使用，公开前需核实授权与医学审核。',
  };
}

Map<String, String> _simpleOptions(dynamic value, int position) {
  if (value is Map) {
    final options = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String ||
          entry.value is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.value as String).trim().isEmpty) {
        throw Exception('第 $position 题的 options 必须是非空文字选项');
      }
      options[(entry.key as String).trim()] = (entry.value as String).trim();
    }
    if (options.length >= 2) return options;
  }
  if (value is List &&
      value.length >= 2 &&
      value.every((item) => item is String && item.trim().isNotEmpty)) {
    return {
      for (var index = 0; index < value.length; index++)
        String.fromCharCode(65 + index): (value[index] as String).trim()
    };
  }
  throw Exception('第 $position 题至少需要 2 个 options，例如 {"A":"选项一","B":"选项二"}');
}

List<String> _stringList(dynamic value, {required List<String> fallback}) {
  if (value == null) return List<String>.from(fallback);
  if (value is! List || !value.every((item) => item is String)) {
    throw Exception('tags、topics、modes 需要填写为文字数组');
  }
  return value
      .cast<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

String _generatedImportedId(Map<String, dynamic> raw, int position) {
  var hash = 0x811c9dc5;
  for (final unit in jsonEncode(raw).codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'user-${hash.toRadixString(16)}-$position';
}
