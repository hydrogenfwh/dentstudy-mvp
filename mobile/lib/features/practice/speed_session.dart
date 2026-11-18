import 'session_journal.dart';
import 'session_summary.dart';
import 'question_tools.dart';
import 'practice_widgets.dart';
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../store.dart';
import '../../app/language_state.dart';

class SpeedStudySession extends StatefulWidget {
  final List<Question> questions;
  final StudyStore store;
  final bool review;
  final String checkpointKind;
  final SessionJournal journal;
  SpeedStudySession({
    super.key,
    required this.questions,
    required this.journal,
    required this.store,
    required this.review,
    this.checkpointKind = 'study',
  });

  @override
  State<SpeedStudySession> createState() => _SpeedStudySessionState();
}

class _SpeedStudySessionState extends State<SpeedStudySession> {
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
  int? viewingIndex;
  bool revealed = false;
  bool busy = false;
  bool finished = false;
  final Map<String, String> answers = {};
  final Set<String> saved = {};

  @override
  void initState() {
    super.initState();
    final data = widget.journal.data;
    index = (data['index'] as int? ?? 0).clamp(0, widget.questions.length - 1);
    answers.addAll(widget.journal.answers);
    saved.addAll(widget.journal.saved);
    finished = data['finished'] == true;
    // An autosave can land between selecting an option and recording its
    // review event. Only a committed event may unlock the explanation.
    while (!finished &&
        index < widget.questions.length &&
        saved.contains(widget.questions[index].id)) {
      if (answers[widget.questions[index].id] !=
          widget.questions[index].answer) {
        revealed = true;
        break;
      }
      index++;
      revealed = false;
    }
    if (index >= widget.questions.length) {
      finished = true;
      index = widget.questions.length - 1;
    }

    restoring = false;
    if (finished) widget.journal.capture({'finished': true});
  }

  Question get current => widget.questions[index];
  Question get displayed => widget.questions[viewingIndex ?? index];
  bool get isViewingHistory => viewingIndex != null;

  /// Completed questions are saved before the speed flow advances. Keep the
  /// active question separate from a read-only history view, so looking back
  /// never changes the question the learner is currently working on.
  int? get previousAnsweredIndex {
    final before = isViewingHistory ? viewingIndex! : index;
    for (var i = before - 1; i >= 0; i--) {
      final question = widget.questions[i];
      if (saved.contains(question.id)) return i;
    }
    return null;
  }

  Future<void> answer(Question question, [String? option]) async {
    if (busy ||
        finished ||
        revealed ||
        isViewingHistory ||
        current.id != question.id) {
      return;
    }
    final value = option ?? answers[question.id];
    if (value == null || value.isEmpty) return;
    final correct = value == question.answer;
    setState(() {
      busy = true;
      answers[question.id] = value;
    });
    try {
      if (!saved.contains(question.id)) {
        await widget.store.add(question.id, 'review', {
          'answer': value,
          'grade': correct ? 'mastered' : 'wrong',
          'mode': widget.review ? 'speed-review' : 'speed',
        });
        saved.add(question.id);
      }
      if (!mounted) return;
      if (!correct) {
        setState(() => revealed = true);
      } else if (index + 1 < widget.questions.length) {
        setState(() => index++);
        // The review event is durable before this point. Make the matching
        // position durable as well before another answer can be accepted.
        await widget.journal.capture(snapshot());
        if (widget.journal.error != null) {
          throw Exception(widget.journal.error);
        }
      } else {
        setState(() => revealed = true);
        await widget.journal.finish(snapshot());
        if (mounted) setState(() => finished = true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败，请重试：$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> nextAfterExplanation(Question question) async {
    if (busy ||
        finished ||
        !revealed ||
        isViewingHistory ||
        current.id != question.id) {
      return;
    }
    if (index + 1 < widget.questions.length) {
      setState(() {
        index++;
        revealed = false;
      });
      await widget.journal.capture(snapshot());
      if (widget.journal.error != null) {
        throw Exception(widget.journal.error);
      }
      return;
    }
    setState(() => busy = true);
    try {
      await widget.journal.finish(snapshot());
      if (mounted) setState(() => finished = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败，请重试：$error')));
      }
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
    return ValueListenableBuilder<bool>(
      valueListenable: widget.journal.checkpointReady,
      builder: (context, ready, child) => PopScope(
        canPop: !busy && (finished || leaving || ready),
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop && await leave() && context.mounted) {
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
                ? '速刷完成'
                : isViewingHistory
                    ? '已作答题目'
                    : '速刷模式'),
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
          ],
        ),
        body: PracticeScrollView(
          page: (finished, finished ? null : displayed.id, isViewingHistory),
          children: finished
              ? [SessionSummary(journal: widget.journal)]
              : _questionView(context),
        ),
      ),
    );
  }

  List<Widget> _questionView(BuildContext context) {
    final question = displayed;
    final selected = answers[question.id];
    final answerShown = isViewingHistory || revealed;
    final previous = previousAnsweredIndex;
    final colors = Theme.of(context).colorScheme;
    return [
      PracticeProgress(
        index: viewingIndex ?? index,
        count: widget.questions.length,
        caption: tr(isViewingHistory ? '已作答 · 仅查看' : '答对自动下一题'),
      ),
      PracticeQuestionStem(question: question),
      QuestionTools(question: question, store: widget.store),
      if (question.isMultipleChoice && !answerShown)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(tr('多选题 · 选完后提交')),
        ),
      for (final option in question.options.entries)
        PracticeOption(
          question: question,
          option: option,
          answer: selected,
          revealed: answerShown,
          onPressed: answerShown || busy
              ? null
              : () {
                  if (current.id != question.id ||
                      busy ||
                      revealed ||
                      isViewingHistory) return;
                  if (question.isMultipleChoice) {
                    setState(() => answers[question.id] =
                        question.choose(answers[question.id], option.key));
                  } else {
                    answer(question, option.key);
                  }
                },
        ),
      if (question.isMultipleChoice && !answerShown)
        FilledButton(
          onPressed:
              busy || (selected ?? '').isEmpty ? null : () => answer(question),
          child: Text(tr('确认多选答案')),
        ),
      if (answerShown) ...[
        const SizedBox(height: 8),
        PracticeExplanation(
          question: question,
          result: Text(
            tr(selected == question.answer ? '回答正确' : '回答错误'),
            style: TextStyle(
              color:
                  selected == question.answer ? colors.primary : colors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 12),
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
              child: Text(tr('再看上一道')),
            ),
            next: FilledButton(
              onPressed: () => setState(() => viewingIndex = null),
              child: Text(tr('回到当前题')),
            ),
          )
        else
          FilledButton(
            onPressed: busy ? null : () => nextAfterExplanation(question),
            child: Text(
                tr(index + 1 == widget.questions.length ? '完成速刷' : '继续下一题')),
          ),
        QuestionLearningSupport(question: question, store: widget.store),
      ],
    ];
  }
}
