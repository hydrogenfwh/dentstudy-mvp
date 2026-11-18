import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../store.dart';

class AccountDeletionPage extends StatefulWidget {
  final StudyStore? accountStore;
  final Future<void> Function(BuildContext)? onLogin;
  const AccountDeletionPage({super.key, this.accountStore, this.onLogin});

  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  final password = TextEditingController();
  StudyStore get account => widget.accountStore ?? store;
  bool acknowledged = false,
      busy = false,
      complete = false,
      filesPending = false;
  String? error;

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !acknowledged || password.text.isEmpty) return;
    final confirmedAccount = account.userId;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('永久删除这个账号？'),
              content: Text('即将删除 ${account.email}。所有设备将退出登录，账号及学习数据无法恢复。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('确认永久删除')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    if (account.userId != confirmedAccount) {
      setState(() => error = '当前账号已变更，请重新确认');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final pending = await account.deleteAccount(password.text);
      // Notifications scheduled by an earlier version may still be present.
      // Their cleanup is independent of the already committed server deletion.
      try {
        await reminders.disable();
      } catch (_) {/* OS may deny plugin access. */}
      if (!mounted) return;
      password.clear();
      setState(() {
        complete = true;
        filesPending = pending;
      });
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(title: Text('删除账号')),
          body: PageBody(children: [
            const SizedBox(height: 20),
            if (complete) ...[
              const Icon(Icons.check_circle_outline, size: 48),
              Text('账号已删除',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 22)),
              Text(filesPending
                  ? '账号已无法登录。投稿文件正在后台清理，服务会自动重试。'
                  : '账号、服务器中的个人学习与交流数据及当前设备的账号缓存已清理。'),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  child: Text('返回访客模式')),
            ] else ...[
              Text(account.email.isEmpty
                  ? '请先登录要删除的账号，再进入此页面。'
                  : '当前账号：${account.email}'),
              if (account.token.isEmpty && widget.onLogin != null)
                OutlinedButton(
                    onPressed: () async {
                      await widget.onLogin!(context);
                      if (mounted) setState(() {});
                    },
                    child: Text('登录要删除的账号')),
              const SizedBox(height: 16),
              Text('此操作不可恢复',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  '将删除账号资料、学习记录、笔记、收藏、签到、评论、好友关系、涉及你的私聊和投稿文件，并撤销所有登录会话。当前设备中该账号的离线题库与练习断点也会清理。其他人的账号和独立评论会保留。'),
              const SizedBox(height: 12),
              const Text(
                  '会员权益随账号移除；删除账号不会自动退款。为对账、退款与争议处理保留必要的订单编号、金额和交易状态，并解除其与账号的关联。已有受限备份不在本次即时清理范围内；其他设备的离线缓存需在该设备清除。'),
              const SizedBox(height: 20),
              TextField(
                  controller: password,
                  obscureText: true,
                  enabled: !busy && account.token.isNotEmpty,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: '输入当前密码', helperText: '仅用于确认本人操作，不会保存')),
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: acknowledged,
                  onChanged: busy
                      ? null
                      : (value) =>
                          setState(() => acknowledged = value ?? false),
                  title: Text('我已了解删除范围及不可恢复的后果')),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: !busy &&
                          acknowledged &&
                          password.text.isNotEmpty &&
                          account.token.isNotEmpty
                      ? submit
                      : null,
                  child: Text(busy ? '正在删除…' : '永久删除账号')),
              const SizedBox(height: 12),
              Text('网络中断时可重新提交，系统会确认上一次删除结果。',
                  style: TextStyle(color: Colors.blueGrey)),
            ],
          ]),
        ),
      );
}
