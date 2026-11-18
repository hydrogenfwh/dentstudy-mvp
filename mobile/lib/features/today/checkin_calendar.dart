import 'package:flutter/material.dart';

import '../../app/shared.dart';
import '../profile/stone_reward_notice.dart';

Future<void> showCheckinCalendar(BuildContext context) => showDialog<void>(
    context: context, builder: (_) => const _CheckinCalendarDialog());

class _CheckinCalendarDialog extends StatefulWidget {
  const _CheckinCalendarDialog();

  @override
  State<_CheckinCalendarDialog> createState() => _CheckinCalendarDialogState();
}

class _CheckinCalendarDialogState extends State<_CheckinCalendarDialog> {
  DateTime month = DateTime(2026, 1);
  Set<String> signedDays = {};
  String? today;
  String? selectedMakeupDay;
  String? rewardPraise;
  String? error;
  int streak = 0, yearCount = 0, makeupRemaining = 3, rewardAmount = 0;
  bool loading = true, signing = false, makingUp = false, signedInToday = false;
  bool _initializedMonth = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _year => month.year.toString().padLeft(4, '0');

  int _earnedStones(Map<String, dynamic> data) =>
      (data['stoneRewards'] as List? ?? const []).whereType<Map>().fold<int>(0,
          (sum, reward) {
        final amount = reward['amount'];
        return sum + (amount is int && amount > 0 ? amount : 0);
      });

  int _makeupRemaining(Map<String, dynamic> data) {
    final limit = data['makeupDailyLimit'] as int? ?? 3;
    final used = data['makeupUsedToday'] as int? ?? 0;
    final remaining = limit - used;
    return remaining < 0
        ? 0
        : remaining > limit
            ? limit
            : remaining;
  }

  void _showReward(Map<String, dynamic> data) {
    final amount = _earnedStones(data);
    if (amount > 0) {
      rewardAmount = amount;
      rewardPraise = randomStonePraise();
    }
  }

  Future<void> _load() async {
    final requestedYear = month.year;
    final loadVersion = ++_loadVersion;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await store.checkinCalendar(requestedYear);
      if (!mounted ||
          loadVersion != _loadVersion ||
          month.year != requestedYear) {
        return;
      }
      final responseToday = data['today'];
      final current =
          responseToday is String ? DateTime.tryParse(responseToday) : null;
      final initialMonth =
          current != null && current.year >= 2026 && current.year <= 2035
              ? DateTime(current.year, current.month)
              : null;
      if (!_initializedMonth &&
          initialMonth != null &&
          initialMonth.year != requestedYear) {
        setState(() {
          _initializedMonth = true;
          month = initialMonth;
        });
        await _load();
        return;
      }
      setState(() {
        signedDays =
            (data['dates'] as List? ?? const []).cast<String>().toSet();
        today = data['today'] as String?;
        if (!_initializedMonth) {
          if (initialMonth != null) {
            month = initialMonth;
          }
          _initializedMonth = true;
        }
        streak = data['currentStreak'] as int? ?? 0;
        yearCount = data['yearCount'] as int? ?? 0;
        makeupRemaining = _makeupRemaining(data);
        signedInToday = data['checkedInToday'] == true;
        loading = false;
      });
    } catch (exception) {
      if (!mounted ||
          loadVersion != _loadVersion ||
          month.year != requestedYear) {
        return;
      }
      setState(() {
        error =
            exception.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        loading = false;
      });
    }
  }

  Future<void> _checkin() async {
    if (signing || signedInToday) return;
    setState(() {
      signing = true;
      // Keep the celebration tied to the action that just happened rather
      // than letting yesterday's success message linger while a request runs.
      rewardAmount = 0;
      rewardPraise = null;
    });
    try {
      final data = await store.checkinToday();
      if (!mounted) return;
      final responseYear = data['year'];
      final reportedStreak = data['currentStreak'] as int? ?? streak;
      // A check-in is always for the server's current Beijing date.  When the
      // learner is browsing a different year, its response must not replace
      // that year's dates/count with the current year's snapshot.
      if (responseYear is! int || responseYear != month.year) {
        await _load();
        if (!mounted) return;
        setState(() => _showReward(data));
        return;
      }
      setState(() {
        signedDays =
            (data['dates'] as List? ?? const []).cast<String>().toSet();
        today = data['today'] as String?;
        streak = reportedStreak;
        yearCount = data['yearCount'] as int? ?? 0;
        makeupRemaining = _makeupRemaining(data);
        signedInToday = data['checkedInToday'] == true;
        _showReward(data);
      });
    } catch (exception) {
      if (mounted)
        message(context,
            exception.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => signing = false);
    }
  }

  Future<void> _makeup() async {
    final target = selectedMakeupDay;
    if (target == null || makingUp || makeupRemaining < 1) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(title: Text(tr('补签 $target？')), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr('再想想'))),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr('消耗 5 颗补签')))
            ]));
    if (confirmed != true || !mounted) return;
    setState(() {
      makingUp = true;
      rewardAmount = 0;
      rewardPraise = null;
    });
    try {
      final data = await store.makeupCheckin(target);
      if (!mounted) return;
      setState(() {
        selectedMakeupDay = null;
        makeupRemaining = _makeupRemaining(data);
        _showReward(data);
      });
      await _load();
      if (mounted && _earnedStones(data) == 0) {
        message(context, tr('补签成功，已消耗 5 颗$stoneName。'));
      }
    } catch (exception) {
      if (mounted) {
        message(context,
            exception.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
      }
    } finally {
      if (mounted) setState(() => makingUp = false);
    }
  }

  /// A completed check-in deserves more than a disabled button.  This status
  /// remains visible for the rest of the calendar session, while the fuller
  /// celebration directly below it keeps the actual just-earned total (for
  /// example, the extra streak reward) in context.
  Widget _checkinControl() {
    if (signedInToday) {
      return Semantics(
          label: usesEnglish ? 'Checked in today; earned 1 $stoneName' : '今日已签到，已获得 1 颗$stoneName',
          child: Container(
              key: const ValueKey('checkin-complete-status'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xfffff6d9),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                      color: const Color(0xffd9a42a).withAlpha(120))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const StoneCoinIcon(size: 21),
                const SizedBox(width: 5),
                Text(tr('今日已签到'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(width: 4),
                const Text('+1',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xffa36b16)))
              ])));
    }
    return FilledButton(
        key: const ValueKey('checkin-action'),
        onPressed: signing || loading ? null : _checkin,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (signing)
            const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
          else
            const StoneCoinIcon(size: 19),
          const SizedBox(width: 5),
          Text(tr(signing ? '签到中…' : '签到 +1'))
        ]));
  }

  void _changeMonth(int delta) {
    final next = DateTime(month.year, month.month + delta);
    if (next.year < 2026 || next.year > 2035) return;
    setState(() {
      month = next;
      selectedMakeupDay = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 730),
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                      child: Text(tr('每日签到'),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800))),
                  IconButton(
                      tooltip: tr('关闭'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: teal.withAlpha(12),
                        borderRadius: BorderRadius.circular(16)),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxWidth < 300;
                      final summary = Row(children: [
                        Icon(Icons.local_fire_department_outlined,
                            color: teal, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(tr('连续签到 $streak 天'),
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700)),
                              Text(tr('$yearCount 天已签到'),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.blueGrey))
                            ])),
                        if (!compact) _checkinControl()
                      ]);
                      if (!compact) return summary;
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            summary,
                            const SizedBox(height: 8),
                            Align(
                                alignment: Alignment.centerRight,
                                child: _checkinControl())
                          ]);
                    })),
                AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    child: rewardAmount < 1 || rewardPraise == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: StoneRewardNotice(
                                amount: rewardAmount, praise: rewardPraise!))),
                const SizedBox(height: 12),
                Row(children: [
                  IconButton(
                      tooltip: tr('上个月'),
                      onPressed: month.year == 2026 && month.month == 1
                          ? null
                          : () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left)),
                  Expanded(
                      child: Text(tr('$_year 年 ${month.month} 月'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700))),
                  IconButton(
                      tooltip: tr('下个月'),
                      onPressed: month.year == 2035 && month.month == 12
                          ? null
                          : () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right))
                ]),
                Row(
                    children: ['一', '二', '三', '四', '五', '六', '日']
                        .map((day) => Expanded(
                            child: Center(
                                child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 5),
                                    child: Text(tr(day),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blueGrey))))))
                        .toList()),
                if (loading)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (error != null)
                  Expanded(
                      child: Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(error!, textAlign: TextAlign.center),
                    TextButton(onPressed: _load, child: Text(tr('重试')))
                  ])))
                else
                  Expanded(child: _calendarGrid()),
                _makeupPanel()
              ]))));

  Widget _makeupPanel() {
    final target = selectedMakeupDay;
    if (target == null) {
      return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              tr(makeupRemaining > 0
                  ? '可选择过去未签到日期补签：5 颗/次，今天还可补 $makeupRemaining 次。'
                  : '今天的补签次数已用完，明天再来。'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey)));
    }
    return Container(
        margin: const EdgeInsets.only(top: 5),
        padding: const EdgeInsets.fromLTRB(10, 7, 7, 7),
        decoration: BoxDecoration(
            color: teal.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: teal.withAlpha(38))),
        child: Row(children: [
          Expanded(
              child: Text(tr('补签 $target · 消耗 5 颗'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700))),
          TextButton(
              onPressed: makingUp
                  ? null
                  : () => setState(() => selectedMakeupDay = null),
              child: Text(tr('取消'))),
          FilledButton(
              onPressed: makingUp ? null : _makeup,
              child: Text(tr(makingUp ? '补签中…' : '补签'))),
        ]));
  }

  Widget _calendarGrid() {
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = DateTime(month.year, month.month, 1).weekday - 1;
    final rows = ((offset + count + 6) ~/ 7);
    return GridView.builder(
        // Short viewports or enlarged fonts can leave less than one month's
        // height. Keep every date reachable rather than clipping the last row.
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, childAspectRatio: 1.25),
        itemCount: rows * 7,
        itemBuilder: (context, index) {
          final day = index - offset + 1;
          if (day < 1 || day > count) return const SizedBox.shrink();
          final dateKey = '$_year-${month.month.toString().padLeft(2, '0')}-'
              '${day.toString().padLeft(2, '0')}';
          final checked = signedDays.contains(dateKey);
          final isToday = today == dateKey;
          final isPastUnsigned =
              today != null && dateKey.compareTo(today!) < 0 && !checked;
          final canMakeup = isPastUnsigned && makeupRemaining > 0;
          final selected = selectedMakeupDay == dateKey;
          final content = Stack(clipBehavior: Clip.none, children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: checked
                        ? teal
                        : selected
                            ? teal.withAlpha(18)
                            : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isToday && !checked
                        ? Border.all(color: teal, width: 1.5)
                        : selected || canMakeup
                            ? Border.all(color: teal.withAlpha(130), width: 1.2)
                            : null),
                alignment: Alignment.center,
                child: Text('$day',
                    style: TextStyle(
                        fontWeight: isToday || checked || selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: checked ? Colors.white : null))),
            if (checked)
              const Positioned(
                  right: -3,
                  bottom: -3,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Padding(
                          padding: EdgeInsets.all(1),
                          child: StoneCoinIcon(size: 16)))),
          ]);
          return Center(
              child: Semantics(
                  label: checked
                      ? tr('$dateKey 已签到，获得$stoneName')
                      : canMakeup
                          ? tr('$dateKey 未签到，选择补签')
                          : dateKey,
                  button: canMakeup,
                  selected: selected,
                  child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: canMakeup
                              ? () => setState(() =>
                                  selectedMakeupDay = selected ? null : dateKey)
                              : null,
                          child: content))));
        });
  }
}
