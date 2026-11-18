import 'package:flutter/material.dart';

import '../../app/language_state.dart';
import '../../models.dart';
import 'question_tools.dart';

class PracticeScrollView extends StatelessWidget {
  final Object page;
  final List<Widget> children;

  const PracticeScrollView({
    super.key,
    required this.page,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              key: ValueKey(page),
              primary: false,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: children,
            ),
          ),
        ),
      );
}

class PracticeProgress extends StatelessWidget {
  final int index;
  final int count;
  final String? caption;

  const PracticeProgress({
    super.key,
    required this.index,
    required this.count,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text('${index + 1} / $count',
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.bold)),
              if (caption != null)
                Text(caption!,
                    style: TextStyle(color: colors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: LinearProgressIndicator(
              value: (index + 1) / count,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

class PracticeNavigation extends StatelessWidget {
  final Widget previous;
  final Widget next;

  const PracticeNavigation({
    super.key,
    required this.previous,
    required this.next,
  });

  @override
  Widget build(BuildContext context) => OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        spacing: 8,
        overflowSpacing: 8,
        overflowAlignment: OverflowBarAlignment.end,
        children: [previous, next],
      );
}

class PracticeQuestionStem extends StatelessWidget {
  final Question question;

  const PracticeQuestionStem({super.key, required this.question});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (question.sharedStem.isNotEmpty) ...[
            Text(question.sharedStem, style: const TextStyle(height: 1.7)),
            const SizedBox(height: 12),
          ],
          QuestionIllustrations(assets: question.data['sharedStemImages']),
          Text(
            question.stem,
            style: const TextStyle(
                fontSize: 21, height: 1.55, fontWeight: FontWeight.w600),
          ),
          QuestionIllustrations(assets: question.data['stemImages']),
        ],
      );
}

class QuestionIllustrations extends StatelessWidget {
  final Object? assets;

  const QuestionIllustrations({super.key, required this.assets});

  @override
  Widget build(BuildContext context) {
    final paths = assets;
    if (paths is! List) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final path in paths.whereType<String>())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Image.asset(
              path,
              fit: BoxFit.contain,
              semanticLabel: usesEnglish ? 'Question illustration' : '题目配图',
              errorBuilder: (context, error, stackTrace) =>
                  Text(usesEnglish ? 'Illustration unavailable' : '配图无法显示'),
            ),
          ),
      ],
    );
  }
}

class PracticeOption extends StatelessWidget {
  final Question question;
  final MapEntry<String, String> option;
  final String? answer;
  final bool revealed;
  final VoidCallback? onPressed;

  const PracticeOption({
    super.key,
    required this.question,
    required this.option,
    this.answer,
    this.revealed = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = question.hasChoice(answer, option.key);
    final correct = revealed && question.hasChoice(question.answer, option.key);
    final incorrect = revealed && selected && !correct;
    final isMarked = correct || selected;
    final color = incorrect
        ? colors.error
        : isMarked
            ? colors.primary
            : colors.outlineVariant;
    final icon = incorrect
        ? Icons.cancel_outlined
        : correct
            ? Icons.check_circle
            : question.isMultipleChoice
                ? (selected
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank)
                : (selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked);
    final status = incorrect
        ? (usesEnglish ? 'Incorrect selection' : '所选答案错误')
        : correct
            ? (usesEnglish ? 'Correct option' : '正确选项')
            : null;
    final images = question.data['optionImages'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: answer != null || !revealed ? selected : null,
        label: status,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: const Size.fromHeight(48),
            foregroundColor: colors.onSurface,
            disabledForegroundColor: colors.onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            backgroundColor: isMarked ? color.withAlpha(24) : colors.surface,
            disabledBackgroundColor:
                isMarked ? color.withAlpha(24) : colors.surface,
            side: BorderSide(color: color),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  size: 21, color: isMarked ? color : colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(option.key,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.value,
                        style: const TextStyle(fontSize: 16, height: 1.4)),
                    QuestionIllustrations(
                        assets: images is Map ? images[option.key] : null),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PracticeExplanation extends StatelessWidget {
  final Question question;
  final Widget? result;

  const PracticeExplanation({super.key, required this.question, this.result});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reference = question.answer ?? question.data['rubric'];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result != null) ...[
              Semantics(liveRegion: true, child: result),
              const SizedBox(height: 8),
            ],
            if (reference != null)
              Text('${tr('参考答案：')}$reference',
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.bold)),
            if (question.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(question.explanation, style: const TextStyle(height: 1.7)),
            ],
            QuestionIllustrations(assets: question.data['explanationImages']),
            SourceDetails(question: question),
          ],
        ),
      ),
    );
  }
}
