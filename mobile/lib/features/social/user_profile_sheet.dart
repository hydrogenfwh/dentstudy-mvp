import 'package:flutter/material.dart';

import '../../app/shared.dart';
import '../library/question_preview.dart';
import '../profile/user_avatar.dart';

typedef UserProfileChatOp = void Function(Map<String, dynamic> profile);

/// Opens the small, privacy-filtered card behind an avatar.
///
/// The card deliberately receives only an opaque account ID.  All profile
/// fields, relationship controls and the author-only email field come from
/// the server, so a browser cannot grant itself author privileges by changing
/// a local flag.
Future<void> showUserProfileSheet(BuildContext context, String userId,
    {UserProfileChatOp? onOpenChat}) async {
  if (userId.trim().isEmpty) return;
  await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
          heightFactor: .9,
          child: UserProfileSheet(userId: userId, onOpenChat: onOpenChat)));
}

class UserProfileSheet extends StatefulWidget {
  final String userId;
  final UserProfileChatOp? onOpenChat;
  const UserProfileSheet({super.key, required this.userId, this.onOpenChat});

  @override
  State<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<UserProfileSheet> {
  Map<String, dynamic>? card;
  String? loadError;
  bool loading = true;
  bool changingRelationship = false;

  Map<String, dynamic> get profile => _map(card?['profile']);
  Map<String, dynamic> get relationship => _map(card?['relationship']);
  String get relationshipStatus => relationship['status'] as String? ?? 'none';
  String get profileId => profile['id'] as String? ?? widget.userId;

  List<Map<String, dynamic>> get comments => (card?['comments'] as List? ?? [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        loadError = null;
      });
    }
    try {
      final result = await store.userCard(widget.userId);
      if (mounted) setState(() => card = result);
    } catch (error) {
      if (mounted) setState(() => loadError = _readableError(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _changeRelationship(
      Future<Map<String, dynamic>> Function() operation,
      String successMessage) async {
    if (changingRelationship) return;
    setState(() => changingRelationship = true);
    try {
      await operation();
      if (mounted) message(context, successMessage);
      await _load();
    } catch (error) {
      if (mounted) message(context, _readableError(error));
    } finally {
      if (mounted) setState(() => changingRelationship = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    return await showDialog<bool>(
            context: context,
            builder: (dialog) =>
                AlertDialog(title: Text(title), content: Text(body), actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: Text(action))
                ])) ==
        true;
  }

  void _openChat() {
    if (profile.isEmpty) return;
    if (widget.onOpenChat == null) {
      message(context, '请从“消息”页面发起聊天');
      return;
    }
    final target = Map<String, dynamic>.from(profile);
    Navigator.pop(context);
    // The route that owns the sheet stays mounted after the sheet is gone.
    // Deferring one frame prevents the pop from accidentally closing the
    // newly pushed chat route on compact navigators.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onOpenChat?.call(target);
    });
  }

  void _openQuestion(Map<String, dynamic> comment) {
    final questionId = comment['questionId'] as String? ?? '';
    final questions = store.resolveQuestions([questionId]);
    if (questions.isEmpty) {
      message(context, '本机暂未收录这道题，请先更新离线题库');
      return;
    }
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => QuestionPreviewPage(
                questions: questions, initialQuestionId: questionId)));
  }

  Widget _profileHeader() => box(Column(children: [
        UserAvatar(
            value: profile['avatar'] as String? ?? 'book',
            radius: 38,
            vip: profile['vipBadge'] == true),
        const SizedBox(height: 10),
        Text(_name(profile),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        if (_university(profile).isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(_university(profile),
              style: const TextStyle(color: Colors.blueGrey))
        ],
        // This key is absent for everyone except the configured author.  It
        // is intentionally not synthesized from any client-side account data.
        if ((profile['email'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          SelectableText(profile['email'] as String,
              style: TextStyle(fontSize: 12, color: teal))
        ]
      ]));

  Widget _relationshipActions() {
    if (profileId == store.userId || relationshipStatus == 'self') {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 6), child: Text('这是你自己。'));
    }
    final canMessage = relationship['canMessage'] == true;
    final canSendIntro = relationship['canSendIntro'] == true;
    if (relationshipStatus == 'blocked') {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: changingRelationship
                ? null
                : () => _changeRelationship(
                    () => store.unblockUser(profileId), '已解除拉黑'),
            icon: const Icon(Icons.lock_open_outlined),
            label: Text('解除拉黑'))
      ]);
    }
    if (relationshipStatus == 'unavailable') {
      return Text('当前无法与这位同学互动。', style: TextStyle(color: Colors.blueGrey));
    }
    if (relationshipStatus == 'incoming' || relationshipStatus == 'outgoing') {
      return Text(
          relationshipStatus == 'incoming'
              ? '对方想加你为好友，请到“消息 · 好友”处理。'
              : '好友申请已发送，等待对方通过后即可聊天。',
          style: const TextStyle(color: Colors.blueGrey));
    }
    if (relationshipStatus == 'friend') {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text('去聊天')),
        OutlinedButton.icon(
            onPressed: changingRelationship
                ? null
                : () async {
                    if (!await _confirm(
                        '删除好友？', '删除后双方都不能继续发送消息；重新添加需等待对方通过。', '删除')) {
                      return;
                    }
                    await _changeRelationship(
                        () => store.removeFriend(profileId), '已删除好友');
                  },
            icon: const Icon(Icons.person_remove_outlined),
            label: Text('删除好友')),
        TextButton.icon(
            onPressed: changingRelationship
                ? null
                : () async {
                    if (!await _confirm(
                        '拉黑这位同学？', '拉黑后双方都无法发送消息或添加好友。', '拉黑')) {
                      return;
                    }
                    await _changeRelationship(
                        () => store.blockUser(profileId), '已拉黑该用户');
                  },
            icon: const Icon(Icons.block_outlined),
            label: Text('拉黑')),
      ]);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (canMessage || canSendIntro)
        OutlinedButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(canSendIntro ? '先聊一句' : '去聊天')),
      FilledButton.tonalIcon(
          onPressed: changingRelationship
              ? null
              : () => _changeRelationship(
                  () => store.sendFriendRequest(profileId), '好友申请已发送'),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: Text('添加好友')),
      TextButton.icon(
          onPressed: changingRelationship
              ? null
              : () async {
                  if (!await _confirm('拉黑这位同学？', '拉黑后双方都无法发送消息或添加好友。', '拉黑')) {
                    return;
                  }
                  await _changeRelationship(
                      () => store.blockUser(profileId), '已拉黑该用户');
                },
          icon: const Icon(Icons.block_outlined),
          label: Text('拉黑')),
    ]);
  }

  Widget _commentList() {
    if (comments.isEmpty) {
      return Text('这位同学暂时还没有公开评论。', style: TextStyle(color: Colors.blueGrey));
    }
    return Column(children: [
      for (final comment in comments)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: box(ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _openQuestion(comment),
                leading: Icon(Icons.forum_outlined, color: teal),
                title: Text(comment['body'] as String? ?? '评论内容暂不可用',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${_commentQuestion(comment)} · ${_commentLikes(comment)} 赞',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.blueGrey)),
                trailing: const Icon(Icons.chevron_right))))
    ]);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: loading && card == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                  if (loadError != null) ...[
                    const SizedBox(height: 28),
                    Text(loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    Center(
                        child: OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: Text('重试')))
                  ] else ...[
                    _profileHeader(),
                    const SizedBox(height: 12),
                    box(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('互动',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 10),
                          _relationshipActions(),
                        ])),
                    const SizedBox(height: 22),
                    Text('发表过的评论 · ${card?['commentCount'] ?? comments.length}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    _commentList(),
                  ]
                ]));
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String _name(Map<String, dynamic> profile) =>
    (profile['nickname'] as String?)?.trim().isNotEmpty == true
        ? (profile['nickname'] as String).trim()
        : '齿间同学';

String _university(Map<String, dynamic> profile) =>
    (profile['university'] as String?)?.trim() ?? '';

String _commentQuestion(Map<String, dynamic> comment) {
  final question = _map(comment['question']);
  final subject = question['subject'] as String? ?? '';
  final chapter = question['chapter'] as String? ?? '';
  return [subject, chapter].where((part) => part.trim().isNotEmpty).join(' · ');
}

int _commentLikes(Map<String, dynamic> comment) =>
    (comment['likes'] as num?)?.toInt() ?? 0;

String _readableError(Object error) =>
    error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
