import 'package:flutter/material.dart';
import '../../models.dart';
import '../../store.dart';
import '../../app/shared.dart' show message, pill, safely;
import '../../app/language_state.dart';
import '../library/catalog.dart';
import '../library/exam_year_catalog.dart';
import '../library/question_preview.dart';
import '../statistics/learning_metrics.dart';
import 'question_comments.dart';
import '../profile/user_avatar.dart';
export 'question_comments.dart';

class SourceDetails extends StatelessWidget {
  final Question question;
  const SourceDetails({super.key, required this.question});
  @override
  Widget build(BuildContext context) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
              '${QuestionCatalog.sourceLabel(question)} · ${QuestionCatalog.reviewLabel(question)}',
              style: const TextStyle(fontSize: 12)),
          children: [
            Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(tr('题目编号：${question.id}'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          const SizedBox(height: 6),
                          SelectableText(question.reference,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                          if (question.data['sourceType'] ==
                              'open_dataset') ...[
                            const SizedBox(height: 8),
                            SelectableText(
                                '来源链接：${question.data['sourceUrl'] ?? ''}\n'
                                '许可：${question.data['license']}\n'
                                '许可全文：https://dentstudy.uno/licenses/CMB-APACHE-2.0.txt\n'
                                '解析：${question.data['explanationSource'] ?? '见来源说明'}\n'
                                '练习资料，非历年真题；未完成专业医学审核。',
                                style:
                                    const TextStyle(fontSize: 12, height: 1.6)),
                          ]
                        ])))
          ]);
}

class QuestionTools extends StatelessWidget {
  final Question question;
  final StudyStore store;
  const QuestionTools({super.key, required this.question, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final favorite = store.learning.states[question.id]?.favorite == true;
        const toolSize = BoxConstraints.tightFor(width: 48, height: 48);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tr(question.subject)} · ${question.chapter}',
                  style:
                      TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
              if (ExamYearCatalog.yearLabel(question) case final String label)
                Padding(
                    padding: const EdgeInsets.only(top: 6), child: pill(label)),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(label: Text(question.type)),
                  IconButton(
                    constraints: toolSize,
                    tooltip: tr(favorite ? '取消收藏' : '收藏题目'),
                    icon: const Icon(Icons.bookmark_border),
                    selectedIcon: const Icon(Icons.bookmark),
                    isSelected: favorite,
                    onPressed: () => safely(
                        context,
                        () => store.add(
                            question.id,
                            'favorite',
                            store.learning.states[question.id]?.favorite !=
                                true)),
                  ),
                  IconButton(
                    constraints: toolSize,
                    tooltip: tr('题目笔记'),
                    icon: const Icon(Icons.edit_note),
                    onPressed: () => _note(context),
                  ),
                  IconButton(
                    constraints: toolSize,
                    tooltip: tr('题目讨论'),
                    icon: const Icon(Icons.forum_outlined),
                    onPressed: () => _comments(context),
                  ),
                  IconButton(
                    constraints: toolSize,
                    tooltip: tr('分享给好友'),
                    icon: const Icon(Icons.ios_share_outlined),
                    onPressed: () => _share(context),
                  ),
                ],
              ),
            ],
          ),
        );
      });

  Future<void> _note(BuildContext context) async {
    var draft = store.learning.states[question.id]?.note ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Text(tr('题目笔记')),
        content: TextFormField(
          initialValue: draft,
          minLines: 2,
          maxLines: 5,
          maxLength: 10000,
          decoration: InputDecoration(labelText: tr('记录你的理解与易混点')),
          onChanged: (value) => draft = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draft),
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) {
      await safely(context, () => store.add(question.id, 'note', result));
    }
  }

  Future<void> _comments(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: FractionallySizedBox(
          heightFactor: .85,
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [QuestionComments(question: question)],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    if (store.token.isEmpty) {
      message(context, '登录后即可分享题目');
      return;
    }
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _QuestionShareSheet(
            question: question, store: store, hostContext: context));
  }
}

/// The picker deliberately lists only accepted friendships.  The server makes
/// the same check on submit, so a stale list can never share a question into a
/// stranger's one-message introduction thread.
class _QuestionShareSheet extends StatefulWidget {
  final Question question;
  final StudyStore store;
  final BuildContext hostContext;
  const _QuestionShareSheet(
      {required this.question, required this.store, required this.hostContext});

  @override
  State<_QuestionShareSheet> createState() => _QuestionShareSheetState();
}

class _QuestionShareSheetState extends State<_QuestionShareSheet> {
  List<Map<String, dynamic>> friends = [];
  String? error;
  String? sendingTo;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await widget.store.friends();
      if (!mounted) return;
      final raw = response['friends'];
      setState(() {
        friends = raw is List
            ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
    } catch (exception) {
      if (mounted) {
        setState(() => error =
            exception.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _send(Map<String, dynamic> friend) async {
    final friendId = friend['id'] as String? ?? '';
    if (friendId.isEmpty || sendingTo != null) return;
    setState(() => sendingTo = friendId);
    try {
      await widget.store
          .shareQuestionInConversation(friendId, widget.question.id);
      if (!mounted) return;
      Navigator.pop(context);
      if (widget.hostContext.mounted) {
        message(widget.hostContext, '已把这道题分享给 ${_friendName(friend)}');
      }
    } catch (exception) {
      if (mounted) {
        message(context,
            exception.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
      }
    } finally {
      if (mounted) setState(() => sendingTo = null);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .62,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('分享题目给好友'),
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(
                        '${tr(widget.question.subject)} · ${widget.question.chapter}',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const SizedBox(height: 12),
                    Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : error != null
                                ? Center(
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                        Text(error!,
                                            textAlign: TextAlign.center),
                                        const SizedBox(height: 8),
                                        OutlinedButton.icon(
                                            onPressed: _load,
                                            icon: const Icon(Icons.refresh),
                                            label: Text(tr('重试')))
                                      ]))
                                : friends.isEmpty
                                    ? Center(
                                        child: Text(
                                            tr('还没有好友。添加好友后就能把题目送进聊天框。'),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant)))
                                    : ListView.separated(
                                        itemCount: friends.length,
                                        separatorBuilder: (_, __) =>
                                            const Divider(height: 1),
                                        itemBuilder: (_, index) {
                                          final friend = friends[index];
                                          final id =
                                              friend['id'] as String? ?? '';
                                          final busy = sendingTo == id;
                                          return ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: UserAvatar(
                                                  value: friend['avatar']
                                                          as String? ??
                                                      'book',
                                                  vip: friend['vipBadge'] ==
                                                      true),
                                              title: Text(_friendName(friend)),
                                              subtitle: (friend['university']
                                                              as String? ??
                                                          '')
                                                      .trim()
                                                      .isEmpty
                                                  ? null
                                                  : Text(friend['university']
                                                      as String),
                                              trailing: busy
                                                  ? const SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                          strokeWidth: 2))
                                                  : const Icon(
                                                      Icons.send_outlined),
                                              onTap: busy ? null : () => _send(friend));
                                        }))
                  ]))));
}

String _friendName(Map<String, dynamic> friend) =>
    (friend['nickname'] as String?)?.trim().isNotEmpty == true
        ? (friend['nickname'] as String).trim()
        : '齿间同学';

/// Shown with an explanation.  It uses the existing bank as a small,
/// transparent follow-up rather than claiming that a new recommendation model
/// knows medical facts that are not present in the question data.
class QuestionLearningSupport extends StatelessWidget {
  final Question question;
  final StudyStore store;
  const QuestionLearningSupport(
      {super.key, required this.question, required this.store});

  List<Question> get _related {
    final tags = question.tags.toSet();
    final peers = store.catalog.material(question.subject).where((candidate) {
      if (candidate.id == question.id) return false;
      return candidate.chapter == question.chapter ||
          candidate.tags.any(tags.contains);
    }).toList();
    peers.sort((a, b) {
      final aTag = a.tags.any(tags.contains) ? 0 : 1;
      final bTag = b.tags.any(tags.contains) ? 0 : 1;
      return aTag.compareTo(bTag);
    });
    return peers.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = LearningMetrics(store.learning, store.questions);
    final related = _related;
    final mistakes = metrics.wrongAttempts(question);
    if (question.tags.isEmpty && related.isEmpty && mistakes < 2) {
      return const SizedBox.shrink();
    }
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('学习巩固'),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          if (question.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('本题考点'),
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 5),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: question.tags.map(pill).toList()),
          ],
          if (mistakes >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('这道题已错 $mistakes 次')),
            ),
          if (related.isNotEmpty)
            TextButton.icon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => QuestionPreviewPage(
                            questions: related,
                            title: '${tr('同考点解析')} · ${question.chapter}'))),
                icon: const Icon(Icons.auto_stories_outlined),
                label: Text(tr('查看 ${related.length} 道同考点题解析'))),
        ]));
  }
}
