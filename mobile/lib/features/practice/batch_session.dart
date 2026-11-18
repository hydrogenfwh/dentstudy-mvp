import 'session_journal.dart';
import 'session_summary.dart';
import 'question_tools.dart';
import 'practice_widgets.dart';
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../store.dart';
import '../../app/language_state.dart';

class BatchStudySession extends StatefulWidget {
  final List<Question> questions;
  final StudyStore store;
  final bool review;
  final String checkpointKind;
  final SessionJournal journal;
  BatchStudySession({
    super.key,
    required this.questions,
    required this.journal,
    required this.store,
    this.review = false,
    this.checkpointKind = 'study',
  });

  @override
  State<BatchStudySession> createState() => _BatchStudySessionState();
}

class _BatchStudySessionState extends State<BatchStudySession> {
  bool leaving = false;
  bool restoring = true;
  Map<String, dynamic> snapshot() => {
        'index': index,
        'finished': finished,
        'answers': Map<String, String>.from(answers),
        'reviewing': reviewing,
        'grades': Map<String, String>.from(grades),
      };
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!restoring && !leaving) {
      widget.journal.capture(snapshot());
    }
  }

  int index = 0;
  bool reviewing = false, busy = false, finished = false;
  final Map<String, String> answers = {};
  final Map<String, String> grades = {};

  @override
  void initState() {
    super.initState();
    final data = widget.journal.data;
    index = (data['index'] as int? ?? 0).clamp(0, widget.questions.length - 1);
    answers.addAll(widget.journal.answers);
    reviewing = data['reviewing'] == true;
    final saved = widget.journal.saved;
    finished = data['finished'] == true ||
        widget.questions.every((item) => saved.contains(item.id));
    final firstUnanswered = _firstUnanswered;
    if (reviewing && !finished && firstUnanswered != -1) {
      reviewing = false;
      index = firstUnanswered;
    } else if (reviewing && !finished) {
      final previousGrades = data['grades'] as Map? ?? {};
      for (final item in widget.questions) {
        final grade = previousGrades[item.id];
        if (item.answer != null && answers[item.id] != item.answer) {
          grades[item.id] = 'wrong';
        } else if (grade == 'wrong' ||
            grade == 'guessed' ||
            grade == 'mastered') {
          grades[item.id] = grade as String;
        }
      }
    }
    restoring = false;
    widget.journal.capture(snapshot());
  }

  Question get question => widget.questions[index];
  int get _firstUnanswered => widget.questions
      .indexWhere((item) => (answers[item.id] ?? '').trim().isEmpty);

  Future<bool> _confirmLeave() async {
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

  Future<void> _nextQuestion(Question expected) async {
    if (busy ||
        finished ||
        reviewing ||
        expected.id != question.id ||
        (answers[expected.id] ?? '').trim().isEmpty) {
      return;
    }
    if (index + 1 < widget.questions.length) {
      setState(() {
        busy = true;
        index++;
      });
      try {
        await widget.journal.capture(snapshot());
        if (widget.journal.error != null) {
          throw Exception(widget.journal.error);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('续练记录保存失败，请重试：$error')));
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    final firstUnanswered = _firstUnanswered;
    if (firstUnanswered != -1) {
      setState(() => index = firstUnanswered);
      return;
    }
    for (final item in widget.questions) {
      if (item.answer != null && answers[item.id] != item.answer) {
        grades[item.id] = 'wrong';
      }
    }
    setState(() {
      reviewing = true;
      index = 0;
    });
  }

  Future<void> _nextReviewQuestion(Question expected) async {
    if (busy ||
        finished ||
        !reviewing ||
        expected.id != question.id ||
        !grades.containsKey(expected.id)) {
      return;
    }
    if (index + 1 < widget.questions.length) {
      setState(() {
        busy = true;
        index++;
      });
      try {
        await widget.journal.capture(snapshot());
        if (widget.journal.error != null) {
          throw Exception(widget.journal.error);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('续练记录保存失败，请重试：$error')));
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    final ungraded =
        widget.questions.indexWhere((item) => !grades.containsKey(item.id));
    if (ungraded == -1) {
      _submit();
    } else {
      setState(() => index = ungraded);
    }
  }

  Future<void> _submit() async {
    setState(() => busy = true);
    try {
      final saved = widget.journal.saved;
      final additions = widget.questions
          .where((item) => !saved.contains(item.id))
          .map((item) => <String, dynamic>{
                'questionId': item.id,
                'kind': 'review',
                'value': {
                  'answer': answers[item.id],
                  'grade': grades[item.id],
                  'mode': widget.review ? 'review' : 'practice',
                },
              })
          .toList();
      // These are the same review events as deep mode. StudyStore's existing
      // reducer schedules them offline; the server reducer recalculates them
      // on sync. No scheduling algorithm is duplicated here.
      if (additions.isNotEmpty) await widget.store.addMany(additions);
      if (!mounted) return;
      await widget.journal.finish(snapshot());
      if (!mounted) return;
      setState(() {
        busy = false;
        finished = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('整批保存失败，请重试：$error')));
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: widget.journal.checkpointReady,
        builder: (context, ready, child) => PopScope(
          canPop: !busy && (finished || leaving || ready),
          onPopInvokedWithResult: (didPop, result) async {
            if (!didPop && await _confirmLeave() && context.mounted) {
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
                  ? '批量刷题完成'
                  : reviewing
                      ? '统一查看解析'
                      : '批量刷题'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: PracticeScrollView(
            page: (finished, reviewing, finished ? null : question.id),
            children: finished
                ? [SessionSummary(journal: widget.journal)]
                : reviewing
                    ? _reviewView(context)
                    : _answerView(),
          ),
        ),
      );

  List<Widget> _answerView() {
    final item = question;
    final selected = answers[item.id];
    return [
      PracticeProgress(
        index: index,
        count: widget.questions.length,
        caption: tr('完成作答后统一看解析'),
      ),
      PracticeQuestionStem(question: item),
      QuestionTools(question: item, store: widget.store),
      if (item.isMultipleChoice)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(tr('多选题 · 选完后进入下一题')),
        ),
      if (item.answer != null)
        for (final option in item.options.entries)
          PracticeOption(
            question: item,
            option: option,
            answer: selected,
            onPressed: () {
              if (question.id == item.id && !reviewing && !busy) {
                setState(() => answers[item.id] =
                    item.choose(answers[item.id], option.key));
              }
            },
          )
      else
        TextFormField(
          key: ValueKey(item.id),
          initialValue: selected,
          minLines: 3,
          maxLines: 6,
          enabled: !busy,
          decoration: InputDecoration(labelText: tr('写下你的分析要点')),
          onChanged: (value) {
            if (!busy) setState(() => answers[item.id] = value);
          },
        ),
      const SizedBox(height: 12),
      PracticeNavigation(
        previous: _previous(item, review: false),
        next: FilledButton(
          onPressed: busy || (selected ?? '').trim().isEmpty
              ? null
              : () => _nextQuestion(item),
          child:
              Text(tr(index + 1 == widget.questions.length ? '完成作答' : '下一题')),
        ),
      ),
    ];
  }

  List<Widget> _reviewView(BuildContext context) {
    final item = question;
    final answer = answers[item.id] ?? '';
    final wrong = item.answer != null && answer != item.answer;
    final grade = grades[item.id];
    final colors = Theme.of(context).colorScheme;
    final last = index + 1 == widget.questions.length;
    final nextLabel = !last
        ? '下一题解析'
        : grades.length == widget.questions.length
            ? '整批提交'
            : '继续评级';
    return [
      PracticeProgress(
        index: index,
        count: widget.questions.length,
        caption: tr('解析与评级'),
      ),
      PracticeQuestionStem(question: item),
      QuestionTools(question: item, store: widget.store),
      if (item.answer != null)
        for (final option in item.options.entries)
          PracticeOption(
              question: item, option: option, answer: answer, revealed: true),
      Text('${tr('你的作答：')}${answer.isEmpty ? tr('未作答') : answer}'),
      const SizedBox(height: 8),
      PracticeExplanation(
        question: item,
        result: item.answer == null
            ? null
            : Text(
                tr(wrong ? '客观题答错，已自动标记“做错”' : '回答正确'),
                style: TextStyle(
                  color: wrong ? colors.error : colors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      if (!wrong) ...[
        const SizedBox(height: 12),
        Text(tr('请确认掌握程度'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          for (final choice in const [
            ('做错', 'wrong'),
            ('蒙对 / 不稳', 'guessed'),
            ('完全掌握', 'mastered'),
          ])
            ChoiceChip(
              label: Text(tr(choice.$1)),
              selected: grade == choice.$2,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: busy
                  ? null
                  : (_) {
                      if (!busy && question.id == item.id && reviewing) {
                        setState(() => grades[item.id] = choice.$2);
                      }
                    },
            ),
        ]),
      ],
      const SizedBox(height: 12),
      PracticeNavigation(
        previous: _previous(item, review: true),
        next: FilledButton(
          onPressed:
              busy || grade == null ? null : () => _nextReviewQuestion(item),
          child: Text(tr(busy ? '保存中…' : nextLabel)),
        ),
      ),
      QuestionLearningSupport(question: item, store: widget.store),
    ];
  }

  Widget _previous(Question item, {required bool review}) => OutlinedButton(
        onPressed: index == 0 || busy
            ? null
            : () {
                if (!busy && reviewing == review && question.id == item.id) {
                  setState(() => index--);
                }
              },
        child: Text(tr('上一题')),
      );
}
