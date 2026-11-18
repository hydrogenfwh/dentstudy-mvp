import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../store.dart';
import '../../models.dart';
import 'practice_request.dart';

/// Local session metadata is separate from the event sync contract.
class SessionJournal with WidgetsBindingObserver {
  final StudyStore store;
  final PracticeRequest request;
  late Map<String, dynamic> data;
  final Stopwatch clock = Stopwatch();
  Timer? ticker;
  final checkpointReady = ValueNotifier(false);
  bool completed = false;
  bool closed = false;
  bool _foreground = true;
  int _checkpointVersion = 0;
  Future<void>? _finishing;
  String? error;
  SessionJournal(this.store, this.request) {
    final previous = request.draft;
    data = previous == null
        ? {
            'id': '${DateTime.now().microsecondsSinceEpoch}',
            'questionIds': request.questions.map((q) => q.id).toList(),
            'kind': request.kind,
            'label': request.label,
            'practiceMode': request.mode,
            'review': request.review,
            'exam': request.exam,
            'index': 0,
            'answers': <String, String>{},
            'grades': <String, String>{},
            'saved': <String>[],
            'eventIds': <String>[],
            'elapsedSeconds': 0,
            'startedAt': DateTime.now().toUtc().toIso8601String(),
          }
        : Map<String, dynamic>.from(previous);
    store.activeSessionId = id;
  }
  String get id => data['id'] as String;
  int get milliseconds =>
      (data['elapsedMs'] as int? ??
          (data['elapsedSeconds'] as int? ?? 0) * 1000) +
      clock.elapsedMilliseconds;
  int get seconds => milliseconds ~/ 1000;
  List<Question> get questions => request.questions;
  Set<String> get saved =>
      Set<String>.from(store.drafts[id]?['saved'] ?? data['saved'] ?? []);
  Map<String, String> get answers => {
        for (final entry in (data['answers'] as Map? ?? {}).entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };

  Future<void> open() async {
    await store.saveDraft({...data});
    data = store.drafts[id] ?? data;
    checkpointReady.value = true;
    final binding = WidgetsBinding.instance;
    _foreground = binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    if (_foreground) clock.start();
    binding.addObserver(this);
    ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (clock.isRunning) unawaited(capture({}));
    });
  }

  Future<void> capture(Map<String, dynamic> state) async {
    if (completed || closed || _finishing != null) return;
    await _capture(state);
  }

  Future<void> _capture(Map<String, dynamic> state) async {
    final version = ++_checkpointVersion;
    if (state.isNotEmpty) checkpointReady.value = false;
    final persisted = store.drafts[id] ?? data;
    final elapsedNow = milliseconds;
    clock.reset();
    data = {
      ...data,
      ...state,
      if (data['finished'] == true) 'finished': true,
      'elapsedMs': elapsedNow,
      'elapsedSeconds': elapsedNow ~/ 1000,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'saved': <String>{
        ...List<String>.from(persisted['saved'] ?? []),
        ...List<String>.from(state['saved'] ?? data['saved'] ?? [])
      }.toList(),
      'eventIds': persisted['eventIds'] ?? [],
    };
    try {
      await store.saveDraft({...data});
      if (version == _checkpointVersion) {
        error = null;
        checkpointReady.value = true;
      }
    } catch (e) {
      if (version == _checkpointVersion) {
        error = '续练记录保存失败：$e';
        checkpointReady.value = false;
      }
    }
  }

  Future<void> finish([Map<String, dynamic> state = const {}]) =>
      _finishing ??= _finish(state).whenComplete(() => _finishing = null);

  Future<void> _finish(Map<String, dynamic> state) async {
    if (completed) return;
    clock.stop();
    try {
      await _capture({...state, 'finished': true});
      if (error != null) throw Exception(error);
      await store.finishSession(id,
          {...data, 'finishedAt': DateTime.now().toUtc().toIso8601String()});
      completed = true;
      ticker?.cancel();
    } catch (_) {
      if (_foreground && !closed) clock.start();
      rethrow;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      if (!completed && !closed && _finishing == null) clock.start();
    } else {
      clock.stop();
      unawaited(capture({}));
    }
  }

  Future<void> close() async {
    if (closed) return;
    ticker?.cancel();
    clock.stop();
    try {
      if (data['finished'] == true) await finish();
      await capture({});
      if (error != null) throw Exception(error);
    } finally {
      closed = true;
      clock.stop();
      WidgetsBinding.instance.removeObserver(this);
      if (store.activeSessionId == id) store.activeSessionId = null;
      checkpointReady.dispose();
    }
  }
}
