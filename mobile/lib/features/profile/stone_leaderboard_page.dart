import 'package:flutter/material.dart';

import '../../app/shared.dart';
import '../social/social_inbox_page.dart' show ChatThreadPage;
import '../social/user_profile_sheet.dart';
import 'stone_reward_notice.dart';
import 'user_avatar.dart';

const _leaderboardScopes = [
  ('today', '今日'),
  ('week', '本周'),
  ('month', '本月'),
  ('all', '累计'),
];

class StoneLeaderboardPage extends StatefulWidget {
  const StoneLeaderboardPage({super.key});

  @override
  State<StoneLeaderboardPage> createState() => _StoneLeaderboardPageState();
}

class _StoneLeaderboardPageState extends State<StoneLeaderboardPage> {
  final accountId = store.userId;
  String scope = 'today';
  Map<String, dynamic>? data;
  Map<String, dynamic>? practiceData;
  String? error;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        store.stoneLeaderboard(scope),
        store.practiceLeaderboard(scope),
      ]);
      if (!mounted || store.userId != accountId) return;
      setState(() {
        data = results[0];
        practiceData = results[1];
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

  Map<String, dynamic> get _me =>
      Map<String, dynamic>.from(data?['me'] as Map? ?? const {});

  Map<String, dynamic> get _practiceMe =>
      Map<String, dynamic>.from(practiceData?['me'] as Map? ?? const {});

  @override
  Widget build(BuildContext context) {
    final entries = (data?['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry));
    final practiceEntries = (practiceData?['entries'] as List? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry));
    return AnimatedBuilder(
        animation: store,
        builder: (context, _) => Scaffold(
            appBar: AppBar(title: Text(tr('羟基磷灰石排行榜'))),
            body: store.token.isEmpty || store.userId != accountId
                ? Center(child: Text(tr('账号已变更，请返回“我的”重新进入。')))
                : PageBody(children: [
                    const SizedBox(height: 20),
                    box(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const StoneCoinIcon(size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(tr('把努力攒成一座小山'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18))),
                          ]),
                        ])),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                        segments: _leaderboardScopes
                            .map((item) => ButtonSegment(
                                value: item.$1, label: Text(tr(item.$2))))
                            .toList(),
                        selected: {scope},
                        onSelectionChanged: loading
                            ? null
                            : (selected) {
                                final next = selected.first;
                                if (next == scope) return;
                                setState(() => scope = next);
                                _load();
                              }),
                    if (loading && data == null && practiceData == null)
                      const Padding(
                          padding: EdgeInsets.only(top: 28),
                          child: Center(child: CircularProgressIndicator()))
                    else if (error != null)
                      box(Column(children: [
                        Text(error!, textAlign: TextAlign.center),
                        TextButton(onPressed: _load, child: Text(tr('重试'))),
                      ]))
                    else if (entries.isEmpty)
                      box(Column(children: [
                        const Icon(Icons.emoji_events_outlined, size: 36),
                        const SizedBox(height: 8),
                        Text(tr('榜单还在热身。先完成一次学习、复习或签到吧！')),
                      ]))
                    else ...[
                      const SizedBox(height: 8),
                      for (final entry in entries) _entry(entry),
                    ],
                    const SizedBox(height: 12),
                    _myRank(),
                    heading('刷题排行榜', sub: '每次服务器确认的学习或复习答题计 1；0 题暂不排名。'),
                    if (practiceEntries.isEmpty)
                      box(Column(children: [
                        const Icon(Icons.menu_book_outlined, size: 36),
                        const SizedBox(height: 8),
                        Text(tr('刷题榜还在热身。完成一道学习或复习题就能上榜！')),
                      ]))
                    else ...[
                      for (final entry in practiceEntries)
                        _practiceEntry(entry),
                    ],
                    const SizedBox(height: 12),
                    _practiceMyRank(),
                    heading('月榜小奖励'),
                    box(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('每月按北京时间结算上月榜单：第 1 名 +30，第 2 名 +20，第 3 名 +10。')),
                          Text(tr('第 4–10 名各 +5，第 11–50 名各 +2。')),
                          const SizedBox(height: 8),
                          Text(tr('榜单只计算有效任务奖励；补签消耗、消费及月榜奖励不计入竞争分。'),
                              style: const TextStyle(color: Colors.blueGrey)),
                        ])),
                  ])));
  }

  Widget _entry(Map<String, dynamic> entry) {
    final rank = entry['rank'] as int? ?? 0;
    final name = entry['nickname'] as String? ?? '努力的同学';
    final avatar = entry['avatar'] as String? ?? 'book';
    final score = entry['score'] as int? ?? 0;
    final medalColor = switch (rank) {
      1 => const Color(0xffbd8500),
      2 => const Color(0xff7d8b94),
      3 => const Color(0xffae6f3b),
      _ => Colors.blueGrey,
    };
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: SizedBox(
            width: 72,
            child: Row(children: [
              SizedBox(
                  width: 30,
                  child: Center(
                      child: rank < 4
                          ? Icon(Icons.emoji_events,
                              color: medalColor, size: 21)
                          : Text('$rank',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: medalColor)))),
              const SizedBox(width: 6),
              _leaderboardAvatar(entry, avatar),
            ])),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          const StoneCoinIcon(size: 20),
          const SizedBox(width: 4),
          Text('$score', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]));
  }

  Widget _myRank() {
    final participating = _me['participating'] != false;
    final score = _me['score'] as int? ?? 0;
    final rank = _me['rank'] as int?;
    final nickname = ((_me['nickname'] as String?) ?? '').trim();
    final avatar = _me['avatar'] as String? ?? 'book';
    final displayRank = rank == null || rank > 50 ? '50+' : '$rank';
    final text = !participating
        ? '未参与 · 可在设置开启'
        : score < 1
            ? '暂未获得石头 · 50+'
            : '第 $displayRank 名';
    return box(Row(children: [
      UserAvatar(value: avatar, radius: 22, vip: _me['vipBadge'] == true),
      const SizedBox(width: 10),
      Expanded(
          child: Text(nickname.isEmpty ? '齿间同学' : nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
      Text(tr(text), style: TextStyle(color: teal, fontWeight: FontWeight.w800)),
    ]));
  }

  Widget _practiceEntry(Map<String, dynamic> entry) {
    final rank = entry['rank'] as int? ?? 0;
    final name = entry['nickname'] as String? ?? '努力的同学';
    final avatar = entry['avatar'] as String? ?? 'book';
    final score = entry['score'] as int? ?? 0;
    final medalColor = switch (rank) {
      1 => const Color(0xffbd8500),
      2 => const Color(0xff7d8b94),
      3 => const Color(0xffae6f3b),
      _ => Colors.blueGrey,
    };
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: SizedBox(
            width: 72,
            child: Row(children: [
              SizedBox(
                  width: 30,
                  child: Center(
                      child: rank < 4
                          ? Icon(Icons.emoji_events,
                              color: medalColor, size: 21)
                          : Text('$rank',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: medalColor)))),
              const SizedBox(width: 6),
              _leaderboardAvatar(entry, avatar),
            ])),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.menu_book_outlined, size: 19),
          const SizedBox(width: 4),
          Text(usesEnglish ? '$score questions' : '$score 题', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]));
  }

  Widget _practiceMyRank() {
    final participating = _practiceMe['participating'] != false;
    final score = _practiceMe['score'] as int? ?? 0;
    final rank = _practiceMe['rank'] as int?;
    final nickname = ((_practiceMe['nickname'] as String?) ?? '').trim();
    final avatar = _practiceMe['avatar'] as String? ?? 'book';
    final displayRank = rank == null || rank > 50 ? '50+' : '$rank';
    final text = !participating
        ? '未参与 · 可在设置开启'
        : score < 1
            ? '暂未刷题 · 50+'
            : '第 $displayRank 名 · $score 题';
    return box(Row(children: [
      UserAvatar(
          value: avatar, radius: 22, vip: _practiceMe['vipBadge'] == true),
      const SizedBox(width: 10),
      Expanded(
          child: Text(nickname.isEmpty ? '齿间同学' : nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
      Text(tr(text), style: TextStyle(color: teal, fontWeight: FontWeight.w800)),
    ]));
  }

  /// Entries expose an opaque userId, never an email.  A tap fetches the
  /// server-filtered card so the same interaction works for both the stone
  /// and practice boards without duplicating user information in rankings.
  Widget _leaderboardAvatar(Map<String, dynamic> entry, String avatar) {
    final picture =
        UserAvatar(value: avatar, radius: 16, vip: entry['vipBadge'] == true);
    final userId = entry['userId'] as String? ?? '';
    if (userId.isEmpty) return picture;
    return Semantics(
        button: true,
        label: '查看 ${entry['nickname'] ?? '齿间同学'} 的资料',
        child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showUserProfileSheet(context, userId,
                onOpenChat: _openProfileChat),
            child: picture));
  }

  void _openProfileChat(Map<String, dynamic> profile) {
    if (!mounted) return;
    Navigator.push<void>(context,
        MaterialPageRoute(builder: (_) => ChatThreadPage(friend: profile)));
  }
}
