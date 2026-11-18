import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/shared.dart';
import 'alipay_checkout.dart';
import 'policy_page.dart';
import 'stone_leaderboard_page.dart';
import 'stone_reward_notice.dart';
import 'stone_share.dart';

String stoneMoney(int fen) =>
    '${fen ~/ 100}.${(fen % 100).toString().padLeft(2, '0')}';

String stoneTimeLabel(String value) {
  final t = DateTime.tryParse(value)?.toUtc().add(const Duration(hours: 8));
  if (t == null) return value;
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${pad(t.month)}-${pad(t.day)} ${pad(t.hour)}:${pad(t.minute)}';
}

class StoneIcon extends StoneCoinIcon {
  const StoneIcon({super.key, super.size});
}

class StoneWalletPage extends StatefulWidget {
  const StoneWalletPage({super.key});
  @override
  State<StoneWalletPage> createState() => _StoneWalletPageState();
}

class _StoneWalletPageState extends State<StoneWalletPage> {
  final accountId = store.userId;
  Map<String, dynamic>? wallet;
  String? error;
  bool loading = false, sharing = false;

  bool get hasSharedToday => wallet?['shareClaimedToday'] == true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await store.stoneWallet();
      if (!mounted || store.userId != accountId) return;
      setState(() {
        wallet = data;
      });
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> share(BuildContext buttonContext) async {
    if (sharing) return;
    setState(() => sharing = true);
    try {
      final renderBox = buttonContext.findRenderObject() as RenderBox;
      // Invoke directly from the gesture, before any network call: Web Share
      // requires transient user activation. Never use clipboard as proof.
      final result = await shareStones(
          title: tr('齿间 DentStudy'),
          text: tr('一起在齿间刷题，把知识学进脑袋，把石头攒进小金库。https://dentstudy.uno'),
          origin: renderBox.localToGlobal(Offset.zero) & renderBox.size);
      if (!mounted || store.userId != accountId) return;
      if (result == ShareResultStatus.success) {
        final claimed = await store.claimShareStone();
        if (mounted && (claimed['stoneRewards'] as List? ?? []).isEmpty) {
          message(context, tr('今天的分享石头已到账，明天再来挖一颗。'));
        }
        await load();
      } else if (result == ShareResultStatus.unavailable && mounted) {
        message(context, tr('当前设备无法确认系统分享，请换用支持分享的手机浏览器或 App。'));
      }
    } catch (_) {
      if (mounted) message(context, tr('这次分享没有完成，石头先等你一下。'));
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(tr('我的石头小金库'))),
          body: store.token.isEmpty || store.userId != accountId
              ? Center(child: Text(tr('账号已变更，请返回“我的”重新进入。')))
              : PageBody(children: [
                  const SizedBox(height: 20),
                  box(Stack(clipBehavior: Clip.none, children: [
                    Align(
                        alignment: Alignment.center,
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const StoneIcon(size: 76),
                                  const SizedBox(height: 8),
                                  Text(stoneName),
                                  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                            wallet == null
                                                ? '—'
                                                : '${wallet!['balance']}',
                                            style: TextStyle(
                                                fontSize: 44,
                                                fontWeight: FontWeight.w800,
                                                color: teal)),
                                        const SizedBox(width: 6),
                                        TextButton(
                                            key: const ValueKey(
                                                'stone-wallet-details'),
                                            onPressed: () async {
                                              await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (_) =>
                                                          StoneDetailPage(
                                                              initialWallet:
                                                                  wallet)));
                                              if (mounted) await load();
                                            },
                                            child: Text(tr('明细 >'))),
                                      ]),
                                  Text(tr('可用石头 · 一颗也是你努力的硬通货')),
                                  if ((wallet?['reserved'] as int? ?? 0) > 0)
                                    Text(tr(
                                        '另有 ${wallet!['reserved']} 颗已预扣，等待组合支付结果')),
                                  const SizedBox(height: 12),
                                  Text(tr('1 颗抵 ¥0.02'),
                                      style: TextStyle(color: Colors.blueGrey)),
                                  const SizedBox(height: 12),
                                  Builder(
                                      builder: (c) => OutlinedButton.icon(
                                          onPressed: sharing || hasSharedToday
                                              ? null
                                              : () => share(c),
                                          icon: const Icon(Icons.ios_share),
                                          label: Text(tr(sharing
                                              ? '分享处理中…'
                                              : hasSharedToday
                                                  ? '今日已分享'
                                                  : '系统分享 · 今日首次 +1')))),
                                ]))),
                    Positioned(
                        top: -10,
                        right: -10,
                        child: TextButton.icon(
                            key: const ValueKey('stone-leaderboard-entry'),
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const StoneLeaderboardPage())),
                            icon: const Icon(Icons.emoji_events_outlined,
                                size: 18),
                            label: Text(tr('排行榜')))),
                  ])),
                  if (error != null) ...[
                    Text(error!, style: const TextStyle(color: Colors.red)),
                    TextButton(
                        onPressed: loading ? null : load, child: Text(tr('重新加载'))),
                  ],
                  if (loading) const LinearProgressIndicator(),
                  heading(tr('怎么攒石头？')),
                  box(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('签到 +1：每天来露个牙。')),
                        Text(tr('连续签到每满 7 天，额外 +7；断签重新计数。')),
                        Text(tr('可补签过去未签到日期：5 颗/次，每天最多 3 次；补出第 7 天同样额外 +7。')),
                        Text(tr('每日首次完成学习目标 +1，首次完成复习目标 +1。')),
                        Text(tr('每日首次系统分享 +1；取消或单独复制链接不计。')),
                        Text(tr('成功上传有效题库，每份 +1，每日最多 +3；相同内容不重复奖励。')),
                        SizedBox(height: 10),
                        Text(tr(
                            '以上按北京时间每日结算。学习与复习以当天首次同步时锁定的服务器目标为准，需至少完成 1 题；重复刷同题不凑数，历史补同步和本机私有题库不补发。')),
                        SizedBox(height: 10),
                        Text(tr('石头是站内奖励，不是现金；不可转赠、充值或提现。组合支付先预扣石头，确认关闭或退款后原路返还。'),
                            style: TextStyle(color: Colors.blueGrey)),
                      ])),
                ])));
}

class StoneDetailPage extends StatefulWidget {
  final Map<String, dynamic>? initialWallet;
  const StoneDetailPage({super.key, this.initialWallet});

  @override
  State<StoneDetailPage> createState() => _StoneDetailPageState();
}

class _StoneDetailPageState extends State<StoneDetailPage> {
  final accountId = store.userId;
  Map<String, dynamic>? wallet;
  final List<Map<String, dynamic>> entries = [];
  String? error;
  bool loading = false;
  int? cursor;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialWallet;
    if (initial == null) {
      load();
    } else {
      _applyPage(initial);
    }
  }

  void _applyPage(Map<String, dynamic> data, {bool more = false}) {
    wallet = data;
    if (!more) entries.clear();
    final rawItems = data['items'];
    if (rawItems is List) {
      entries.addAll(rawItems
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item)));
    }
    cursor = data['nextCursor'] is int ? data['nextCursor'] as int : null;
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await store.stoneWallet(before: more ? cursor : null);
      if (!mounted || store.userId != accountId) return;
      setState(() => _applyPage(data, more: more));
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(tr('石头明细'))),
          body: store.token.isEmpty || store.userId != accountId
              ? Center(child: Text(tr('账号已变更，请返回“我的”重新进入。')))
              : PageBody(children: [
                  const SizedBox(height: 20),
                  if (wallet != null)
                    box(Row(children: [
                      const StoneIcon(size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(tr('当前 ${wallet!['balance']} 颗'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 20)),
                            Text(tr('北京时间 · 每一颗石头都有来路'),
                                style: TextStyle(color: Colors.blueGrey)),
                          ])),
                    ])),
                  if (error != null) ...[
                    Text(error!, style: const TextStyle(color: Colors.red)),
                    TextButton(
                        onPressed: loading ? null : load, child: Text(tr('重新加载'))),
                  ],
                  if (loading && entries.isEmpty)
                    const LinearProgressIndicator(),
                  if (entries.isEmpty && !loading && error == null)
                    box(Text(tr('还没有明细。第一颗石头，正在等你签到。'))),
                  for (final item in entries)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item['reason'] as String),
                        subtitle:
                            Text(stoneTimeLabel(item['createdAt'] as String)),
                        trailing: Text(
                            '${item['amount'] > 0 ? '+' : ''}${item['amount']}',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: item['amount'] > 0
                                    ? teal
                                    : Colors.deepOrange))),
                  if (cursor != null)
                    TextButton(
                        onPressed: loading ? null : () => load(more: true),
                        child: Text(tr('再翻一页'))),
                ])));
}

class StoneVipPage extends StatefulWidget {
  const StoneVipPage({super.key});
  @override
  State<StoneVipPage> createState() => _StoneVipPageState();
}

class _StoneVipPageState extends State<StoneVipPage> {
  final accountId = store.userId;
  Map<String, dynamic>? wallet, selected;
  String? error;
  String method = 'stones';
  bool busy = false;
  final countField = TextEditingController(text: '0');
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    countField.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final data = await store.stoneWallet();
      if (mounted && store.userId == accountId)
        setState(() {
          wallet = data;
          error = null;
        });
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> pay() async {
    if (busy || selected == null || wallet == null) return;
    final plan = selected!;
    final price = plan['priceFen'] as int;
    final count = method == 'stones'
        ? price ~/ 2
        : method == 'mixed'
            ? int.tryParse(countField.text)
            : 0;
    if (count == null ||
        count < 0 ||
        count > (wallet!['balance'] as int) ||
        (method == 'mixed' && (count < 1 || count * 2 >= price))) {
      message(context, tr('石头数量不合适，请检查余额与抵扣数量。'));
      return;
    }
    final currentMethod = method;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(tr('确认这笔石头开销？')),
                content: Text(
                    '${plan['name']}：$count 颗石头${currentMethod == 'stones' ? '' : ' + ¥${stoneMoney(price - count * 2)}'}。\n${plan['description']}\n'
                    '${currentMethod == 'stones' ? '确认后扣除石头并开通 VIP。' : '石头先预扣，现金到账后开通；订单确认关闭或退款时返还石头。'}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(tr('再想想'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(tr('确认')))
                ]));
    if (confirmed != true || !mounted || store.userId != accountId) return;
    setState(() => busy = true);
    try {
      if (currentMethod == 'stones') {
        await store.redeemStones(plan['id'] as String, price);
        if (mounted) message(context, tr('石头出发，VIP 到家！'));
        await load();
        if (mounted) setState(() => selected = null);
      } else {
        final data = await store.request('/v1/payments/alipay/checkout', {
          'planId': plan['id'],
          'stoneCount': count,
          'expectedPriceFen': price,
          'checkoutMode': shouldUseAlipayWap() ? 'mobile_web' : 'desktop',
        });
        openAlipayCheckout(data['checkoutUrl'] as String);
      }
    } catch (e) {
      if (mounted)
        message(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final price = selected?['priceFen'] as int? ?? 0;
        final balance = wallet?['balance'] as int? ?? 0;
        final maxMixed = min(balance, max(0, (price - 1) ~/ 2));
        final count = int.tryParse(countField.text) ?? 0;
        final enabled = method == 'stones'
            ? (wallet?['redemptionOpen'] == true)
            : (kIsWeb && wallet?['mixedPaymentOpen'] == true);
        return Scaffold(
            appBar: AppBar(title: Text(tr('VIP · 石头也能买单'))),
            body: store.token.isEmpty || store.userId != accountId
                ? Center(child: Text(tr('账号已变更，请返回重新进入。')))
                : PageBody(children: [
                    heading(tr('努力攒的石头，现在派上用场')),
                    Text(tr('1 羟基磷灰石抵 ¥0.02；例如 ¥6.90 = 345 颗。')),
                    const SizedBox(height: 8),
                    Text(tr('VIP 权益：全题库学习、每日新题不限量、小齿深度思考及跨设备学习记录同步。')),
                    TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PolicyPage())),
                        child: Text(tr('查看服务与规则'))),
                    const SizedBox(height: 12),
                    Text(tr('可用余额：$balance 颗')),
                    if (error != null) ...[
                      Text(error!),
                      TextButton(onPressed: load, child: Text(tr('重试')))
                    ],
                    if (wallet == null && error == null)
                      const LinearProgressIndicator(),
                    if (wallet != null && selected == null)
                      for (final raw in wallet!['plans'] as List)
                        box(ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const StoneIcon(),
                            title: Text(
                                '${tr(raw['name'] as String)} · ¥${raw['displayPrice']}'),
                            subtitle: Text(
                                '${tr('${(raw['priceFen'] as int) ~/ 2} 颗石头')}\n${tr(raw['description'] as String)}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => setState(() {
                                  selected = Map<String, dynamic>.from(raw);
                                  countField.text = '0';
                                }))),
                    if (selected != null) ...[
                      heading('${tr(selected!['name'] as String)} · ¥${stoneMoney(price)}'),
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => selected = null),
                          child: Text(tr('重选方案'))),
                      for (final option in [
                        ('stones', '羟基磷灰石支付 · ${price ~/ 2} 颗'),
                        ('mixed', '组合支付 · 石头 + 支付宝'),
                        ('cash', '支付宝支付 · ¥${stoneMoney(price)}')
                      ])
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                                method == option.$1
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: teal),
                            title: Text(option.$2),
                            onTap: busy
                                ? null
                                : () => setState(() => method = option.$1)),
                      if (method == 'mixed') ...[
                        TextField(
                            controller: countField,
                            keyboardType: TextInputType.number,
                            enabled: !busy,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                            labelText: tr('使用石头数量（最多 $maxMixed）'))),
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(
                                    () => countField.text = '$maxMixed'),
                            child: Text(tr('使用最大可抵扣数量'))),
                        Text(count >= 0 && count <= maxMixed
                            ? tr('抵扣 ¥${stoneMoney(count * 2)}，还需支付宝支付 ¥${stoneMoney(price - count * 2)}')
                            : tr('请填写 1–$maxMixed 之间的整数')),
                      ],
                      if (!enabled)
                        Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(tr('兑换与支付正在准备中，请勿充值。规则和数量先给你安排明白。'))),
                      const SizedBox(height: 14),
                      FilledButton(
                          onPressed: enabled &&
                                  !busy &&
                                  (method != 'stones' || balance >= price ~/ 2)
                              ? pay
                              : null,
                          child: Text(tr(busy
                              ? '正在处理…'
                              : method == 'stones'
                                  ? '使用 ${price ~/ 2} 颗兑换'
                                  : '确认组合与金额'))),
                      if (method == 'stones' && balance < price ~/ 2)
                        Text(tr('还差 ${price ~/ 2 - balance} 颗，学习一下，小金库就长大一点。')),
                    ],
                  ]));
      });
}
