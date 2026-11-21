import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../app/shared.dart';
import '../../app/language_selector.dart';
import '../assistant/livliv_window_stub.dart'
    if (dart.library.js_interop) '../assistant/livliv_window_web.dart';
import 'appearance_settings.dart';
import 'policy_page.dart';
import 'account_deletion_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _scrollController = ScrollController(keepScrollOffset: false);
  bool _leaderboardParticipation = true;
  bool _loadingLeaderboardParticipation = false;

  @override
  void initState() {
    super.initState();
    _loadLeaderboardParticipation();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLeaderboardParticipation() async {
    if (store.token.isEmpty ||
        store.baseUrl.trim().isEmpty ||
        _loadingLeaderboardParticipation) {
      return;
    }
    final accountId = store.userId;
    setState(() => _loadingLeaderboardParticipation = true);
    try {
      final board = await store.stoneLeaderboard('all');
      if (!mounted || store.userId != accountId) return;
      final me = Map<String, dynamic>.from(
          board['me'] as Map? ?? const <String, dynamic>{});
      setState(() => _leaderboardParticipation = me['participating'] != false);
    } catch (_) {
      // Ranking privacy is an optional preference.  Keep the default-on UI
      // usable during a rolling deployment or a temporary network outage.
    } finally {
      if (mounted && store.userId == accountId) {
        setState(() => _loadingLeaderboardParticipation = false);
      }
    }
  }

  Future<void> _setLeaderboardParticipation(bool enabled) async {
    if (_loadingLeaderboardParticipation) return;
    final accountId = store.userId;
    setState(() => _loadingLeaderboardParticipation = true);
    try {
      final result = await store.setStoneLeaderboardParticipation(enabled);
      if (!mounted || store.userId != accountId) return;
      setState(() => _leaderboardParticipation = result['enabled'] != false);
    } catch (exception) {
      if (mounted) {
        message(context,
            exception.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
      }
    } finally {
      if (mounted && store.userId == accountId) {
        setState(() => _loadingLeaderboardParticipation = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(tr('设置'))),
          body: PageBody(controller: _scrollController, children: [
            heading(tr('主题与外观')),
            box(const AppearanceSettings()),
            heading(tr('学习设置')),
            box(Column(children: [
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.smart_toy_outlined, color: teal),
                  title: Text(tr('${store.companionName} · 备考搭子')),
                  subtitle: Text(tr(store.usesLivlivPreview
                      ? '在互动空间切换角色、试听问候语'
                      : store.usesGuga
                      ? '本地互动免费；咕嘎暂不支持 AI 聊天和语音'
                      : '本地互动免费；AI 聊天仅作者可用，聊天不保存记录')),
                  value: store.xiaochiEnabled,
                  onChanged: (value) =>
                      safely(context, () => store.setXiaochiEnabled(value))),
              Padding(
                  key: const ValueKey('companion-appearance-setting'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('搭子形象')),
                        const SizedBox(height: 8),
                        Wrap(spacing: 12, runSpacing: 8, children: [
                          for (final option in const {
                            'dafeiyu': '大肥鱼',
                            'xiaochi': '小齿',
                            'guga': '咕嘎',
                            if (kIsWeb) 'livliv-preview': 'LivLiv',
                          }.entries)
                            ChoiceChip(
                                key: ValueKey('companion-${option.key}'),
                                label: Text(tr(option.value)),
                                selected:
                                    store.companionAppearance == option.key,
                                onSelected: (_) => safely(
                                    context,
                                    () => store
                                        .setCompanionAppearance(option.key)))
                        ]),
                        if (kIsWeb)
                          TextButton.icon(
                              icon: const Icon(Icons.record_voice_over_outlined),
                              label: Text(tr('进入 LivLiv 互动空间')),
                              onPressed: openLivLivConversation),
                        const SizedBox(height: 6),
                        Text(tr('搭子形象保存在这台设备上。'),
                            style:
                                TextStyle(color: Colors.blueGrey, fontSize: 12))
                      ])),
              Padding(
                  key: const ValueKey('dafeiyu-voice-setting'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('大肥鱼互动语音')),
                        const SizedBox(height: 8),
                        Wrap(spacing: 12, runSpacing: 8, children: [
                          for (final option in const {
                            'manual': '手动播放',
                            'auto': '自动播放',
                            'off': '关闭语音'
                          }.entries)
                            ChoiceChip(
                                key: ValueKey('dafeiyu-voice-${option.key}'),
                                label: Text(tr(option.value)),
                                selected: store.dafeiyuVoiceMode == option.key,
                                onSelected: (_) => safely(
                                    context,
                                    () =>
                                        store.setDafeiyuVoiceMode(option.key)))
                        ]),
                        const SizedBox(height: 6),
                        Text(tr('互动台词可点气泡中的喇叭播放；自动播放受浏览器设置影响。语音来源：尹紫鹭幻想社。'),
                            style:
                                TextStyle(color: Colors.blueGrey, fontSize: 12))
                      ])),
              const Divider(),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.flag_outlined),
                  title: Text(tr('每日学习目标')),
                  subtitle: Text(tr(
                      '新题上限可自主设置，当前 ${store.dailyNewLimit} · 复习目标 ${store.dailyReviewTarget == null ? '无限制' : store.dailyReviewTarget}')),
                  onTap: goalsDialog),
              Divider(),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_for_offline_outlined),
                  title: Text(tr('下载 / 更新离线题库')),
                  subtitle: Text(tr('${store.catalog.countLabel}；断网可答题')),
                  onTap: () => safely(context, () async {
                        await store.download();
                        if (mounted) message(context, tr('离线题库已更新'));
                      })),
            ])),
            heading(tr('语言')),
            box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('选择界面语言')),
              const SizedBox(height: 6),
              Text(tr('切换后立即生效；题库题干、昵称和用户发布内容保留原文。'),
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              const SizedBox(height: 12),
              LanguageSelector(
                  value: store.languageCode,
                  onChanged: (value) => store.setLanguage(value)),
            ])),
            if (store.token.isNotEmpty) ...[
              heading(tr('排行榜')),
              box(SwitchListTile.adaptive(
                  key:
                      const ValueKey('stone-leaderboard-participation-setting'),
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(Icons.emoji_events_outlined, color: teal),
                  title: Text(tr('参与羟基磷灰石排行榜')),
                  subtitle: Text(_leaderboardParticipation
                      ? tr('默认参与：头像、昵称和获得石头数会公开展示；0 颗暂不排名。')
                      : tr('已关闭：不会公开上榜；随时可以重新开启。')),
                  value: _leaderboardParticipation,
                  onChanged: _loadingLeaderboardParticipation
                      ? null
                      : _setLeaderboardParticipation)),
            ],
            heading(tr('服务与规则')),
            if (store.token.isNotEmpty)
              box(ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: Text(tr('删除账号')),
                  subtitle: Text(tr('确认身份后永久删除账号及关联数据')),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AccountDeletionPage())))),
            box(ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.policy_outlined, color: teal),
                title: Text(tr('服务与规则')),
                subtitle: Text(tr('用户协议、隐私说明、版权投诉与数据删除')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PolicyPage())))),
          ])));

  Future<void> goalsDialog() async {
    final newField = TextEditingController(text: '${store.dailyNewLimit}');
    final reviewField =
        TextEditingController(text: '${store.dailyReviewTarget ?? 20}');
    var unlimited = store.dailyReviewTarget == null;
    final result = await showDialog<(int, int?)>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: Text(tr('每日学习目标')),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: newField,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: tr('每日新题上限（0–1,000,000）'))),
                      SizedBox(height: 12),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr('复习题不设上限')),
                          value: unlimited,
                          onChanged: (v) => set(() => unlimited = v)),
                      if (!unlimited)
                        TextField(
                            controller: reviewField,
                            keyboardType: TextInputType.number,
                            decoration:
                                InputDecoration(labelText: tr('每日复习题目标（0–200）'))),
                      SizedBox(height: 8),
                      Text(tr('复习与学习新题可自主安排；新题上限只限制当天新增题数。'),
                          style:
                              TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c), child: Text(tr('取消'))),
                      FilledButton(
                          onPressed: () {
                            final n = int.tryParse(newField.text),
                                r = unlimited
                                    ? null
                                    : int.tryParse(reviewField.text);
                            if (n == null ||
                                n < 0 ||
                                n > 1000000 ||
                                (!unlimited &&
                                    (r == null || r < 0 || r > 200))) {
                              message(c, tr('新题上限为 0–1,000,000；复习目标为 0–200'));
                              return;
                            }
                            Navigator.pop(c, (n, r));
                          },
                          child: Text(tr('保存')))
                    ])));
    if (result != null && mounted)
      await safely(context, () async {
        await store.setGoals(result.$1, result.$2);
      });
  }
}
