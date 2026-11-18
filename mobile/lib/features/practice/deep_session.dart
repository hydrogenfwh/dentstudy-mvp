import 'session_journal.dart';
import 'session_summary.dart';
import 'question_tools.dart';
import 'practice_widgets.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../app/shared.dart';

class StudySession extends StatefulWidget {
  final List<Question> questions;
  final bool exam, review;
  final String checkpointKind;
  final SessionJournal journal;
  StudySession(
      {super.key,
      required this.questions,
      required this.journal,
      this.exam = false,
      this.review = false,
      this.checkpointKind = 'study'});
  @override
  State<StudySession> createState() => _StudySessionState();
}

class _StudySessionState extends State<StudySession>
    with WidgetsBindingObserver {
  bool leaving = false;
  bool restoring = true;
  Map<String, dynamic> snapshot() => {
        'index': index,
        'finished': finished,
        'answers': Map<String, String>.from(answers),
        'revealed': revealed,
        'saved': saved.toList(),
      };
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!restoring && !leaving) {
      widget.journal.capture(snapshot());
    }
  }

  int index = 0;
  bool revealed = false, busy = false, finished = false;
  final Map<String, String> answers = {};
  final Set<String> saved = {};
  int? viewingIndex;
  late DateTime deadline;
  Timer? timer;
  int seconds = 0;
  bool autoSubmitAttempted = false;
  bool confirmingExam = false;
  Question get q => widget.questions[index];
  Question get displayed => widget.questions[viewingIndex ?? index];
  bool get isViewingHistory => viewingIndex != null;

  /// A graded question has already been saved, so it can be shown safely as a
  /// read-only history item without changing the active question or its
  /// review record.
  int? get previousAnsweredIndex {
    final before = isViewingHistory ? viewingIndex! : index;
    for (var i = before - 1; i >= 0; i--) {
      if (saved.contains(widget.questions[i].id)) return i;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final data = widget.journal.data;
    index = (data['index'] as int? ?? 0).clamp(0, widget.questions.length - 1);
    answers.addAll(widget.journal.answers);
    saved.addAll(widget.journal.saved);
    finished = data['finished'] == true;
    revealed = !widget.exam &&
        data['revealed'] == true &&
        (answers[q.id]?.trim().isNotEmpty ?? false);
    while (!widget.exam &&
        !finished &&
        index < widget.questions.length &&
        saved.contains(widget.questions[index].id)) {
      index++;
      revealed = false;
    }
    if (index >= widget.questions.length) {
      finished = true;
      index = widget.questions.length - 1;
    }

    restoring = false;

    WidgetsBinding.instance.addObserver(this);
    deadline = DateTime.now().add(Duration(
        minutes: widget.questions.first.data['durationMinutes'] as int? ?? 15));
    deadline =
        DateTime.tryParse(widget.journal.data['deadline'] as String? ?? '') ??
            deadline;
    widget.journal.capture(
        {'deadline': deadline.toUtc().toIso8601String(), 'finished': finished});
    if (widget.exam && !finished) {
      tick();
      timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.exam) tick();
  }

  void tick() {
    if (!mounted || finished || leaving) return;
    final millisecondsLeft = deadline.difference(DateTime.now()).inMilliseconds;
    super.setState(() => seconds = max(0, (millisecondsLeft + 999) ~/ 1000));
    if (millisecondsLeft <= 0 && !busy && !autoSubmitAttempted) {
      autoSubmitAttempted = true;
      unawaited(submitExam());
    }
  }

  Future<void> save(Question question, String grade,
      {String mode = 'practice'}) async {
    if (saved.contains(question.id)) return;
    await widget.journal.store.add(question.id, 'review',
        {'answer': answers[question.id], 'grade': grade, 'mode': mode});
    saved.add(question.id);
  }

  Future<void> grade(Question question, String grade) async {
    if (busy ||
        finished ||
        widget.exam ||
        !revealed ||
        isViewingHistory ||
        q.id != question.id) {
      return;
    }
    setState(() => busy = true);
    try {
      await save(question, grade, mode: widget.review ? 'review' : 'practice');
      if (!mounted) return;
      if (index + 1 == widget.questions.length) {
        await widget.journal.finish(snapshot());
        if (mounted) setState(() => finished = true);
      } else {
        setState(() {
          index++;
          revealed = false;
        });
        // The next question is now visible. Persist that position before
        // re-enabling actions so an immediate browser refresh cannot reopen
        // the question that was already graded.
        await widget.journal.capture(snapshot());
        if (widget.journal.error != null) {
          throw Exception(widget.journal.error);
        }
      }
    } catch (e) {
      if (mounted) message(context, '保存失败，请重试：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submitExam() async {
    if (busy || finished) return;
    setState(() => busy = true);
    try {
      final unsubmitted = widget.questions
          .where((question) =>
              question.answer != null &&
              (answers[question.id]?.trim().isNotEmpty ?? false) &&
              !saved.contains(question.id))
          .toList();
      if (unsubmitted.isNotEmpty) {
        await widget.journal.store.addMany([
          for (final question in unsubmitted)
            {
              'questionId': question.id,
              'kind': 'review',
              'value': {
                'answer': answers[question.id],
                'grade': answers[question.id] == question.answer
                    ? 'guessed'
                    : 'wrong',
                'mode': 'exam',
              },
            },
        ]);
        saved.addAll(unsubmitted.map((question) => question.id));
      }
      await widget.journal.finish(snapshot());
      timer?.cancel();
      if (mounted) setState(() => finished = true);
    } catch (e) {
      if (mounted) message(context, tr('提交失败，作答仍保留在本页：$e'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> leave() async {
    if (busy || leaving) return false;
    if (finished) return true;
    super.setState(() => busy = true);
    try {
      await widget.journal.capture(snapshot());
      final error = widget.journal.error;
      if (error == null) return true;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      return false;
    } finally {
      if (mounted) super.setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previous = previousAnsweredIndex;
    final history = viewingIndex;
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: widget.journal.checkpointReady,
      builder: (context, ready, child) => PopScope(
        canPop: !busy && (finished || leaving || ready),
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) {
            timer?.cancel();
          } else if (await leave() && context.mounted) {
            setState(() => leaving = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted &&
                  ModalRoute.of(context)?.isCurrent == true) {
                Navigator.pop(context);
              }
            });
          }
        },
        child: child!,
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            tr(finished
                ? '本次练习分析'
                : widget.exam
                    ? '限时模考'
                    : widget.review
                        ? '今日巩固'
                        : '专注练习'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (!finished && isViewingHistory)
              TextButton(
                onPressed: () => setState(() => viewingIndex = null),
                child: Text(tr('回到当前题')),
              )
            else if (!finished && previous != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        if (viewingIndex == history) {
                          setState(() => viewingIndex = previous);
                        }
                      },
                child: Text(tr('上一题')),
              ),
            if (widget.exam && !finished)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: seconds < 60 ? colors.error : colors.onSurface,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: PracticeScrollView(
          page: (finished, finished ? null : displayed.id, isViewingHistory),
          children: finished
              ? [
                  SessionSummary(journal: widget.journal),
                  if (widget.exam) ...report(),
                ]
              : _questionView(context),
        ),
      ),
    );
  }

  List<Widget> _questionView(BuildContext context) {
    final question = displayed;
    final selected = answers[question.id];
    final previous = previousAnsweredIndex;
    final answerShown = isViewingHistory || revealed;
    final colors = Theme.of(context).colorScheme;
    final wrong = question.answer != null && selected != question.answer;
    final last = index + 1 == widget.questions.length;
    return [
      PracticeProgress(
        index: viewingIndex ?? index,
        count: widget.questions.length,
        caption: isViewingHistory ? tr('已作答 · 仅查看') : null,
      ),
      PracticeQuestionStem(question: question),
      QuestionTools(question: question, store: widget.journal.store),
      if (question.isMultipleChoice && !answerShown)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(tr(widget.exam ? '多选题 · 选完后进入下一题' : '多选题 · 选完后提交')),
        ),
      if (question.answer != null)
        for (final option in question.options.entries)
          PracticeOption(
            question: question,
            option: option,
            answer: selected,
            revealed: answerShown,
            onPressed: answerShown || busy
                ? null
                : () {
                    if (q.id == question.id &&
                        !isViewingHistory &&
                        !revealed &&
                        !busy) {
                      setState(() => answers[question.id] =
                          question.choose(answers[question.id], option.key));
                    }
                  },
          )
      else if (answerShown)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '${tr('你的作答：')}${selected?.trim().isNotEmpty == true ? selected : tr('未作答')}',
          ),
        )
      else
        TextFormField(
          key: ValueKey(question.id),
          initialValue: selected,
          minLines: 3,
          maxLines: 6,
          enabled: !busy,
          decoration: InputDecoration(labelText: tr('写下你的分析要点')),
          onChanged: (value) {
            if (!busy) setState(() => answers[question.id] = value);
          },
        ),
      if (answerShown) ...[
        const SizedBox(height: 8),
        PracticeExplanation(
          question: question,
          result: Text(
            tr(question.answer == null
                ? '对照要点，自评掌握度'
                : wrong
                    ? '回答错误'
                    : isViewingHistory
                        ? '回答正确'
                        : '回答正确，再确认掌握度'),
            style: TextStyle(
              color: wrong ? colors.error : colors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (isViewingHistory)
        PracticeNavigation(
          previous: OutlinedButton(
            onPressed: previous == null
                ? null
                : () {
                    if (displayed.id == question.id) {
                      setState(() => viewingIndex = previous);
                    }
                  },
            child: Text(tr('再看上一题')),
          ),
          next: FilledButton(
            onPressed: () => setState(() => viewingIndex = null),
            child: Text(tr('回到当前题')),
          ),
        )
      else if (widget.exam) ...[
        const SizedBox(height: 12),
        PracticeNavigation(
          previous: OutlinedButton(
            onPressed: index == 0 || busy
                ? null
                : () {
                    if (q.id == question.id && !busy) setState(() => index--);
                  },
            child: Text(tr('上一题')),
          ),
          next: FilledButton(
            onPressed: busy
                ? null
                : () {
                    if (q.id != question.id || busy) return;
                    if (last) {
                      confirmSubmit();
                    } else {
                      setState(() => index++);
                    }
                  },
            child: Text(tr(last ? '交卷并分析' : '下一题')),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '已作答 ${answers.values.where((a) => a.trim().isNotEmpty).length} / ${widget.questions.length} · 到时自动交卷',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ] else if (revealed) ...[
        if (wrong)
          FilledButton(
            onPressed: busy ? null : () => grade(question, 'wrong'),
            child: Text(tr(last ? '标记做错并完成' : '标记做错并继续')),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              onPressed: busy ? null : () => grade(question, 'wrong'),
              child: Text(tr('做错')),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => grade(question, 'guessed'),
              child: Text(tr('蒙对 / 不稳')),
            ),
            FilledButton(
              onPressed: busy ? null : () => grade(question, 'mastered'),
              child: Text(tr('完全掌握')),
            ),
          ]),
        QuestionLearningSupport(
            question: question, store: widget.journal.store),
      ] else ...[
        const SizedBox(height: 8),
        FilledButton(
          onPressed: selected?.trim().isNotEmpty == true && !busy
              ? () {
                  if (q.id == question.id &&
                      !isViewingHistory &&
                      !busy &&
                      !revealed &&
                      answers[question.id]?.trim().isNotEmpty == true) {
                    FocusScope.of(context).unfocus();
                    setState(() => revealed = true);
                  }
                }
              : null,
          child: Text(tr('确认作答 · 查看解析')),
        ),
      ],
    ];
  }

  Future<void> confirmSubmit() async {
    if (busy || finished || confirmingExam) return;
    confirmingExam = true;
    try {
      final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text(tr('确认交卷')),
                  content: Text(
                      tr('未答客观题记 0 分。主观题对照要点自评，不计入自动得分。答对题目先按“蒙对 / 不稳”安排复习。')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text(tr('继续检查'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(tr('交卷')))
                  ]));
      if (ok == true && mounted) await submitExam();
    } finally {
      confirmingExam = false;
    }
  }

  List<Widget> report() {
    final colors = Theme.of(context).colorScheme;
    final objective = widget.questions.where((q) => q.answer != null).toList();
    final correct = objective.where((q) => answers[q.id] == q.answer).length;
    final total =
        objective.fold<int>(0, (sum, q) => sum + (q.data['points'] as int));
    final score = objective
        .where((q) => answers[q.id] == q.answer)
        .fold<int>(0, (sum, q) => sum + (q.data['points'] as int));
    return [
      box(Column(children: [
        Icon(Icons.task_alt, color: colors.primary, size: 48),
        SizedBox(height: 16),
        Text(tr(widget.exam ? '客观题 $score / $total 分' : '本次练习已完成'),
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        SizedBox(height: 10),
        Text(tr('客观题正确 $correct / ${objective.length} · 复习计划已更新')),
        if (widget.exam)
          Text(tr('主观题不包含在自动得分中；请在下方完成自评。'),
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))
      ])),
      heading(tr('逐题回顾')),
      ...widget.questions.map((question) => studyCard(
              child: ExpansionTile(
                  title: Text(question.stem, style: TextStyle(fontSize: 15)),
                  subtitle: Text(
                      '${tr('你的作答：')}${answers[question.id] ?? tr('未作答')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  children: [
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PracticeQuestionStem(question: question),
                          QuestionTools(
                              question: question, store: widget.journal.store),
                          PracticeExplanation(question: question),
                          if (widget.exam &&
                              question.answer == null &&
                              (answers[question.id]?.trim().isNotEmpty ??
                                  false) &&
                              !saved.contains(question.id)) ...[
                            SizedBox(height: 12),
                            Text(tr('对照要点后自评（仅保存一次）')),
                            Wrap(
                                spacing: 8,
                                children: ['wrong', 'guessed', 'mastered']
                                    .map((g) => TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => safely(context, () async {
                                                  setState(() => busy = true);
                                                  try {
                                                    await save(question, g,
                                                        mode: 'exam');
                                                  } finally {
                                                    if (mounted)
                                                      setState(
                                                          () => busy = false);
                                                  }
                                                }),
                                        child: Text(tr({
                                          'wrong': '做错',
                                          'guessed': '不稳',
                                          'mastered': '掌握'
                                        }[g]!))))
                                    .toList())
                          ],
                          if (saved.contains(question.id))
                            Text(
                                '下次复习：${widget.journal.store.learning.states[question.id]?.due ?? '—'}',
                                style: TextStyle(
                                    color: colors.primary, fontSize: 12))
                        ]))
              ]))),
      SizedBox(height: 20),
      FilledButton(
          onPressed: () => Navigator.pop(context), child: Text(tr('返回学习首页')))
    ];
  }
}
