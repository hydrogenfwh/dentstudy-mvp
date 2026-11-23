import 'package:flutter/foundation.dart';

/// Kept separate from the account profile: a visitor must be able to choose a
/// language before signing in, and the choice should remain available after a
/// sign-out.
final appLanguage = ValueNotifier<String>('zh');

bool get usesEnglish => appLanguage.value == 'en';

void setAppLanguage(String code) {
  appLanguage.value = code == 'en' ? 'en' : 'zh';
}

/// Translates application chrome only. Question-bank material, user names,
/// comments and private messages deliberately remain in their source language
/// instead of being machine-translated as medical content.
String tr(String source) {
  if (!usesEnglish) return source;
  final exact = _english[source];
  if (exact != null) return exact;

  final trackBank = RegExp(r'^(考研|本科期末|执医)题库$').firstMatch(source);
  if (trackBank != null) return '${tr(trackBank.group(1)!)} Question Bank';
  final catalog = RegExp(r'^本机 (\d+) 题 · (考研|本科期末|执医)可练 (\d+) 题$').firstMatch(source);
  if (catalog != null) return '${catalog.group(1)} questions on this device · ${catalog.group(3)} available for ${tr(catalog.group(2)!)}';
  final trackCount = RegExp(r'^(\d+) 道可练 · (\d+) 个学科$').firstMatch(source);
  if (trackCount != null) return '${trackCount.group(1)} questions · ${trackCount.group(2)} subjects';
  final priority = RegExp(r'^今日订正 (\d+) 题 · 反复错 (\d+) 题 · 其他错题 (\d+) 题 · 已掌握待归档 (\d+) 题$').firstMatch(source);
  if (priority != null) return 'Missed today: ${priority.group(1)} · repeated: ${priority.group(2)} · other: ${priority.group(3)} · mastered: ${priority.group(4)}';
  final emptyNotebook = RegExp(r'^还没有(错题|收藏|疑问题|笔记)$').firstMatch(source);
  if (emptyNotebook != null) return 'No ${tr(emptyNotebook.group(1)!).toLowerCase()} yet';
  final daysMetric = RegExp(r'^(\d+) 天$').firstMatch(source);
  if (daysMetric != null) return '${daysMetric.group(1)} days';
  final durationMetric = RegExp(r'^(\d+)分(\d+)秒$').firstMatch(source);
  if (durationMetric != null) return '${durationMetric.group(1)} min ${durationMetric.group(2)} sec';
  final schoolCount = RegExp(r'^(\d+) 份资料 · (.+)$').firstMatch(source);
  if (schoolCount != null) return '${schoolCount.group(1)} resources · ${tr(schoolCount.group(2)!)}';
  final bundleCount = RegExp(r'^(\d+) 个合并资料包 · 按科目整理$').firstMatch(source);
  if (bundleCount != null) return '${bundleCount.group(1)} combined resource packs · organized by subject';
  final durationPlan = RegExp(r'^(\d+) 个月有效，不自动续费$').firstMatch(source);
  if (durationPlan != null) return 'Valid for ${durationPlan.group(1)} months; no automatic renewal';
  final stoneCount = RegExp(r'^(\d+) 颗石头$').firstMatch(source);
  if (stoneCount != null) return '${stoneCount.group(1)} tokens';
  final ranking = RegExp(r'^第 (\d+|50\+) 名(?: · (\d+) 题)?$').firstMatch(source);
  if (ranking != null) return 'Rank ${ranking.group(1)}${ranking.group(2) == null ? '' : ' · ${ranking.group(2)} questions'}';

  final streak = RegExp(r'^连续学习 (\d+) 天$').firstMatch(source);
  if (streak != null) return '${streak.group(1)}-day learning streak';
  final signed = RegExp(r'^(\d+) 天已签到$').firstMatch(source);
  if (signed != null) return '${signed.group(1)} days checked in';
  final reviewAndNew = RegExp(r'^待复习 (\d+) 题 · 新题 (\d+) 题$').firstMatch(source);
  if (reviewAndNew != null) {
    return '${reviewAndNew.group(1)} due · ${reviewAndNew.group(2)} new';
  }
  final planProgress =
      RegExp(r'^今日计划已完成 (\d+) / (\d+) 题 · 预计还需 (\d+) 分钟$').firstMatch(source);
  if (planProgress != null) {
    return "Today’s plan: ${planProgress.group(1)} / ${planProgress.group(2)} complete · about ${planProgress.group(3)} min left";
  }
  final planStart =
      RegExp(r'^(开始|继续)今日计划 · (?:剩余 )?(\d+) 题$').firstMatch(source);
  if (planStart != null) {
    return '${planStart.group(1) == '开始' ? 'Start' : 'Continue'} today’s plan · ${planStart.group(2)} questions';
  }
  final yesterdayReview =
      RegExp(r'^(继续昨日复习|复习昨日题目) · (?:剩余 )?(\d+) 题$').firstMatch(source);
  if (yesterdayReview != null) {
    return '${yesterdayReview.group(1) == '继续昨日复习' ? 'Continue' : 'Review'} yesterday’s questions · ${yesterdayReview.group(2)} questions';
  }
  final practiceDuration =
      RegExp(r'^练习 (\d+) 题 · 预计 (\d+) 分钟$').firstMatch(source);
  if (practiceDuration != null) {
    return 'Practice ${practiceDuration.group(1)} questions · about ${practiceDuration.group(2)} min';
  }
  final completion = RegExp(r'^完成 (\d+) 题$').firstMatch(source);
  if (completion != null) return '${completion.group(1)} questions complete';
  final vipValidity = RegExp(r'^会员有效至 (.+)（北京时间）$').firstMatch(source);
  if (vipValidity != null) {
    return 'VIP valid until ${vipValidity.group(1)} (Beijing time)';
  }
  final remaining = RegExp(r'^剩余 (\d+) 题$').firstMatch(source);
  if (remaining != null) return '${remaining.group(1)} remaining';
  final checkinStreak = RegExp(r'^连续签到 (\d+) 天$').firstMatch(source);
  if (checkinStreak != null) return '${checkinStreak.group(1)}-day check-in streak';
  final month = RegExp(r'^(\d{4}) 年 (\d+) 月$').firstMatch(source);
  if (month != null) return '${month.group(2)}/${month.group(1)}';
  final makeup = RegExp(r'^补签 (.+) · 消耗 5 颗$').firstMatch(source);
  if (makeup != null) return 'Make up ${makeup.group(1)} · use 5 tokens';
  final makeupPrompt = RegExp(r'^补签 (.+)？$').firstMatch(source);
  if (makeupPrompt != null) return 'Make up ${makeupPrompt.group(1)}?';
  final questionId = RegExp(r'^题目编号：(.*)$').firstMatch(source);
  if (questionId != null) return 'Question ID: ${questionId.group(1)}';
  final currentBalance = RegExp(r'^当前 (\d+) 颗$').firstMatch(source);
  if (currentBalance != null) return 'Current balance: ${currentBalance.group(1)} tokens';
  final availableBalance = RegExp(r'^可用余额：(\d+) 颗$').firstMatch(source);
  if (availableBalance != null) return 'Available: ${availableBalance.group(1)} tokens';
  final keyPointCount = RegExp(r'^查看 (\d+) 道同考点题解析$').firstMatch(source);
  if (keyPointCount != null) return 'View ${keyPointCount.group(1)} related explanations';
  final notesCount = RegExp(r'^共 (\d+) 道题留下笔记；下方按题目自带考点聚合，便于考前回看。$')
      .firstMatch(source);
  if (notesCount != null) {
    return '${notesCount.group(1)} questions have notes. They are grouped by key point below for review.';
  }
  final companion = RegExp(r'^(.+) · 备考搭子$').firstMatch(source);
  if (companion != null) return '${companion.group(1)} · Study companion';
  final dailyGoal = RegExp(r'^新题上限可自主设置，当前 (\d+) · 复习目标 (.+)$').firstMatch(source);
  if (dailyGoal != null) {
    return 'Set your new-question limit. Current: ${dailyGoal.group(1)} · review goal: ${tr(dailyGoal.group(2)!)}';
  }
  final offlineCatalog = RegExp(r'^(.+)；断网可答题$').firstMatch(source);
  if (offlineCatalog != null) return '${tr(offlineCatalog.group(1)!)} · available offline';
  final scale = RegExp(r'^缩放 ([\d.]+)×$').firstMatch(source);
  if (scale != null) return 'Scale ${scale.group(1)}×';
  final opacity = RegExp(r'^背景图片透明度 (\d+)%（0% 完全透明，100% 完整显示）$').firstMatch(source);
  if (opacity != null) return 'Background opacity ${opacity.group(1)}% (0% transparent, 100% fully visible)';
  final savedTheme = RegExp(r'^背景已保存，并按图片主色匹配为(.+)主题$').firstMatch(source);
  if (savedTheme != null) return 'Background saved and matched to the ${tr(savedTheme.group(1)!)} theme.';
  final matchedTheme = RegExp(r'^图片主色已自动匹配为(.+)；可继续调整。$').firstMatch(source);
  if (matchedTheme != null) return 'The image color was matched to ${tr(matchedTheme.group(1)!)}. You can keep adjusting it.';
  final currentTheme = RegExp(r'^当前：(.+)$').firstMatch(source);
  if (currentTheme != null) return 'Current: ${tr(currentTheme.group(1)!)}';
  final customTheme = RegExp(r'^主色：(.+) · 背景：淡(.+)$').firstMatch(source);
  if (customTheme != null) {
    return 'Primary: ${tr(customTheme.group(1)!)} · background: pale ${tr(customTheme.group(2)!)}';
  }
  final makeupLeft = RegExp(r'^可选择过去未签到日期补签：5 颗/次，今天还可补 (\d+) 次。$').firstMatch(source);
  if (makeupLeft != null) return 'Choose an earlier missed day to make up: 5 tokens each. ${makeupLeft.group(1)} left today.';
  final makeupSuccess = RegExp(r'^补签成功，已消耗 5 颗(.+)。$').firstMatch(source);
  if (makeupSuccess != null) return 'Make-up check-in successful. Used 5 ${makeupSuccess.group(1)}.';
  final checkedDate = RegExp(r'^(.+) 已签到，获得(.+)$').firstMatch(source);
  if (checkedDate != null) return '${checkedDate.group(1)} checked in; earned ${checkedDate.group(2)}';
  final missedDate = RegExp(r'^(.+) 未签到，选择补签$').firstMatch(source);
  if (missedDate != null) return '${missedDate.group(1)} not checked in; choose make-up';
  final failedSubmit = RegExp(r'^提交失败，作答仍保留在本页：(.*)$').firstMatch(source);
  if (failedSubmit != null) return 'Submission failed. Your answers remain on this page: ${failedSubmit.group(1)}';
  final score = RegExp(r'^客观题 (\d+) / (\d+) 分$').firstMatch(source);
  if (score != null) return 'Objective score: ${score.group(1)} / ${score.group(2)}';
  final correctCount = RegExp(r'^客观题正确 (\d+) / (\d+) · 复习计划已更新$').firstMatch(source);
  if (correctCount != null) return 'Objective correct: ${correctCount.group(1)} / ${correctCount.group(2)} · review plan updated';
  final searchSummary = RegExp(r'^当前(.+)方向共 (\d+) 题。搜索题干、选项、解析和考点；多个关键词用空格分隔。$')
      .firstMatch(source);
  if (searchSummary != null) {
    return 'The ${tr(searchSummary.group(1)!)} track has ${searchSummary.group(2)} questions. Search stems, options, explanations, and key points; separate keywords with spaces.';
  }
  final resultCount = RegExp(r'^找到 (\d+) 道题$').firstMatch(source);
  if (resultCount != null) return '${resultCount.group(1)} questions found';
  final reserved = RegExp(r'^另有 (\d+) 颗已预扣，等待组合支付结果$').firstMatch(source);
  if (reserved != null) return '${reserved.group(1)} tokens are pre-deducted while mixed payment is confirmed.';
  final maxToken = RegExp(r'^使用石头数量（最多 (\d+)）$').firstMatch(source);
  if (maxToken != null) return 'Tokens to use (maximum ${maxToken.group(1)})';
  final mixedDue = RegExp(r'^抵扣 ¥([\d.]+)，还需支付宝支付 ¥([\d.]+)$').firstMatch(source);
  if (mixedDue != null) return 'Discount ¥${mixedDue.group(1)}; pay ¥${mixedDue.group(2)} with Alipay';
  final tokenRange = RegExp(r'^请填写 1–(\d+) 之间的整数$').firstMatch(source);
  if (tokenRange != null) return 'Enter a whole number between 1 and ${tokenRange.group(1)}';
  final redeemCount = RegExp(r'^使用 (\d+) 颗兑换$').firstMatch(source);
  if (redeemCount != null) return 'Redeem with ${redeemCount.group(1)} tokens';
  final missingToken = RegExp(r'^还差 (\d+) 颗，学习一下，小金库就长大一点。$').firstMatch(source);
  if (missingToken != null) return '${missingToken.group(1)} more tokens needed. Keep learning to grow your wallet.';
  final draftRemaining = RegExp(r'^剩余 (\d+) 题 · (.+)$').firstMatch(source);
  if (draftRemaining != null) return '${draftRemaining.group(1)} remaining · ${tr(draftRemaining.group(2)!)}';
  final dueCount = RegExp(r'^共 (\d+) 道到期题。可优先复习，也可以先继续今日新题。$').firstMatch(source);
  if (dueCount != null) return '${dueCount.group(1)} questions are due. Review them first, or continue today’s new questions.';
  final materialsCount = RegExp(r'^(\d+) 题 · 按资料浏览$').firstMatch(source);
  if (materialsCount != null) return '${materialsCount.group(1)} questions · browse resources';
  final yearsCount = RegExp(r'^(\d+) 个年份 · 按年份浏览$').firstMatch(source);
  if (yearsCount != null) return '${yearsCount.group(1)} years · browse by year';
  final schoolsCount = RegExp(r'^(\d+) 所院校 · 按学校查找真题与资料$').firstMatch(source);
  if (schoolsCount != null) return '${schoolsCount.group(1)} schools · find past papers and resources';
  return source;
}

const _english = <String, String>{
  '儿童口腔医学': 'Pediatric Dentistry',
  '口腔临床药物学': 'Clinical Dental Pharmacology',
  '口腔修复学': 'Prosthodontics',
  '口腔内科学': 'Oral Medicine',
  '口腔材料学': 'Dental Materials',
  '口腔正畸学': 'Orthodontics',
  '口腔生物学': 'Oral Biology',
  '口腔科学综合试卷': 'Comprehensive Dentistry Papers',
  '口腔组织病理学': 'Oral Histology and Pathology',
  '口腔解剖生理学': 'Oral Anatomy and Physiology',
  '口腔预防医学': 'Preventive Dentistry',
  '口腔颌面医学影像诊断学': 'Oral and Maxillofacial Radiology',
  '口腔颌面外科学': 'Oral and Maxillofacial Surgery',
  '口腔黏膜病学': 'Oral Mucosal Diseases',
  '基础医学': 'Basic Medical Sciences',
  '牙体牙髓病学': 'Cariology and Endodontics',
  '牙周病学': 'Periodontology',
  '𬌗学': 'Occlusion',
  '温州医科大学': 'Wenzhou Medical University',
  '大连医科大学': 'Dalian Medical University',
  '历年真题': 'Past exam papers',
  '历年真题（回忆版）': 'Past exam papers (recalled)',
  '资料包': 'Resource packs',
  '合并资料包': 'Combined resource pack',
  '合并阅读': 'Combined reading',
  '考研资料': 'Postgraduate entrance resources',
  '月卡': 'Monthly plan',
  '季卡': 'Quarterly plan',
  '半年卡': 'Six-month plan',
  '年卡': 'Annual plan',
  '终身 VIP': 'Lifetime VIP',
  '首月 ¥1；之后每月 ¥6.9，手动续费，不自动扣款': 'First month ¥1; ¥6.9 per month thereafter. Manual renewal; no automatic charge.',
  '每月 ¥6.9，手动续费，不自动扣款': '¥6.9 per month. Manual renewal; no automatic charge.',
  '一次付费，永久有效，不自动续费': 'One payment, valid for life; no automatic renewal.',
  '暂无作答': 'No answers yet',
  '尚未开始': 'Not started',
  '需巩固': 'Needs review',
  '学习中': 'In progress',
  '待复习': 'Due for review',
  '较稳定': 'On track',
  '本周': 'This week',
  '本月': 'This month',
  '累计': 'All time',
  '羟基磷灰石排行榜': 'Hydroxyapatite leaderboard',
  '把努力攒成一座小山': 'Turn your effort into a mountain of rewards',
  '榜单还在热身。先完成一次学习、复习或签到吧！': 'The leaderboard is warming up. Study, review, or check in to join!',
  '刷题排行榜': 'Practice leaderboard',
  '每次服务器确认的学习或复习答题计 1；0 题暂不排名。': 'Each server-confirmed study or review answer counts once; zero answers are not ranked.',
  '刷题榜还在热身。完成一道学习或复习题就能上榜！': 'Complete a study or review question to join the practice leaderboard!',
  '月榜小奖励': 'Monthly leaderboard rewards',
  '每月按北京时间结算上月榜单：第 1 名 +30，第 2 名 +20，第 3 名 +10。': 'The previous month is settled in Beijing time: first place +30, second +20, third +10.',
  '第 4–10 名各 +5，第 11–50 名各 +2。': 'Places 4–10 receive +5 each; places 11–50 receive +2 each.',
  '榜单只计算有效任务奖励；补签消耗、消费及月榜奖励不计入竞争分。': 'Only eligible task rewards count. Make-up check-in costs, purchases, and monthly prizes do not count toward the ranking.',
  '未参与 · 可在设置开启': 'Not participating · enable in Settings',
  '暂未获得石头 · 50+': 'No tokens earned yet · 50+',
  '暂未刷题 · 50+': 'No practice yet · 50+',
  '搜索题目关键词': 'Search question keywords',
  '搜索本章题目': 'Search this chapter',
  '搜索本学科题目': 'Search this subject',
  '真题/模拟题': 'Past and mock papers',
  '考研 · 按学校分类': 'Postgraduate entrance · browse by school',
  '院校资料正在整理中。': 'School resources are being prepared.',
  '整理中 · 按年份浏览': 'Being prepared · browse by year',
  '历年真题来源：真题；科目讲义来源：人卫讲义。按年份整理并区分复试，资料包按科目合并；能够明确配对的答案直接附在题目后。主观题不自动判分。':
      'Past exam papers and People’s Medical Publishing House subject notes are organized by year and subject. Matched answers follow their questions. Subjective questions are not automatically graded.',
  '历年题为回忆整理；资料包含本科课程及其他院校练习，保留各自来源，不代表官方试卷。':
      'Past questions are reconstructed from recollections. Materials include undergraduate coursework and exercises from other schools, with sources retained; they are not official papers.',
  // Shared navigation and entry.
  '齿间': 'DentStudy',
  '今日': 'Today',
  '题库': 'Question Bank',
  '题本': 'Notebook',
  '学情': 'Progress',
  '我的': 'Me',
  '联系作者': 'Contact author',
  '每天学一点，记牢一点。': 'Learn a little every day. Remember it for good.',
  '登录后会安全保持登录状态，不保存明文密码。':
      'Your sign-in stays secure. Plain-text passwords are never stored.',
  '访客模式': 'Continue as guest',
  '登录 / 注册': 'Sign in / Register',
  '语言': 'Language',
  '界面语言': 'Interface language',
  '选择界面语言': 'Choose interface language',
  '中文': 'Chinese',
  '英文': 'English',
  '切换后立即生效；题库题干、昵称和用户发布内容保留原文。':
      'Takes effect immediately. Question text, names, and user content stay in their original language.',

  // Authentication.
  '创建学习账号': 'Create your account',
  '登录学习账号': 'Sign in',
  '邮箱': 'Email',
  '密码（至少10位）': 'Password (at least 10 characters)',
  '确认密码': 'Confirm password',
  '务必记住密码，目前忘记密码无法找回！！！':
      'Please keep your password safe. Password recovery is not available yet.',
  '记住登录状态': 'Keep me signed in',
  '密码仅交由浏览器或系统密码管理器保存':
      'Passwords are saved only by your browser or system password manager.',
  '账号学习进度会自动同步；访客记录保留在本机。':
      'Account progress syncs automatically; guest progress stays on this device.',
  '已有账号？登录': 'Already have an account? Sign in',
  '没有账号？注册': 'New here? Create an account',
  '取消': 'Cancel',
  '连接中…': 'Connecting…',
  '继续': 'Continue',
  '两次输入的密码不一致': 'The two passwords do not match.',
  '个人资料暂时无法加载，可在“我的”中稍后完善':
      'Profile details are temporarily unavailable. You can finish them later in Me.',

  // Account and settings.
  '退出登录': 'Sign out',
  '登录已过期': 'Session expired',
  '登录已过期，请重新登录。': 'Your session expired. Please sign in again.',
  '学习记录保存在本机，重新登录后继续同步。': 'Your progress is saved on this device. Sign in again to resume syncing.',
  '重新登录': 'Sign in again',
  '切换到访客': 'Switch to guest',
  '设置': 'Settings',
  '主题与外观、学习设置、服务与规则': 'Theme, learning preferences, services and policies',
  '主题与外观': 'Theme & appearance',
  '学习设置': 'Learning preferences',
  '服务与规则': 'Services & policies',
  '搭子形象': 'Study companion appearance',
  '在互动空间与当前角色聊天并听取回复': 'Chat with your selected character and hear their reply',
  '进入 LivLiv 互动空间': 'Open the LivLiv room',
  '在互动空间切换角色、试听问候语': 'Switch characters and play their greetings in the room',
  '搭子形象保存在这台设备上。': 'Your companion selection is saved on this device.',
  '大肥鱼': 'Dafeiyu',
  '小齿': 'Xiaochi',
  '大肥鱼互动语音': 'Dafeiyu voice',
  '手动播放': 'Play manually',
  '自动播放': 'Autoplay',
  '关闭语音': 'Turn voice off',
  '每日学习目标': 'Daily learning goal',
  '下载 / 更新离线题库': 'Download / update offline question bank',
  '断网可答题': 'Available offline',
  '离线题库已更新': 'Offline question bank updated.',
  '参与羟基磷灰石排行榜': 'Join the hydroxyapatite leaderboard',
  '删除账号': 'Delete account',
  '确认身份后永久删除账号及关联数据':
      'Permanently delete your account and associated data after verification.',
  '用户协议、隐私说明、版权投诉与数据删除': 'Terms, privacy, copyright notices and data deletion',
  '保存': 'Save',
  '关闭': 'Close',
  '重试': 'Try again',
  '排行榜': 'Leaderboard',
  '默认参与：头像、昵称和获得石头数会公开展示；0 颗暂不排名。':
      'On by default: your avatar, nickname, and earned stones are public. Zero stones are not ranked.',
  '已关闭：不会公开上榜；随时可以重新开启。':
      'Off: you will not appear publicly. You can turn it back on anytime.',
  '备考搭子': 'Study companion',
  '本地互动免费；AI 聊天仅作者可用，聊天不保存记录':
      'Local interactions are free. AI chat is author-only and is not saved.',
  '默认大肥鱼，可切换小齿；本地互动不调用 AI、不扣费，形象仅保存在本机。':
      'Dafeiyu is the default. Switch to Xiaochi anytime. Local interactions do not use AI or charge credits; the choice stays on this device.',
  '互动台词可点气泡中的喇叭播放；自动播放受浏览器设置影响。语音来源：尹紫鹭幻想社。':
      'Tap the speaker in a bubble to play companion lines. Autoplay depends on browser settings. Voice source: Yin Zilu Fantasy Club.',
  '新题上限可自主设置，当前 ': 'You can set your new-question limit. Current: ',
  '无限制': 'Unlimited',
  '新题上限可自主设置': 'Set your new-question limit',

  // Today and practice entry.
  '今天，学一点，记牢一点。': 'Today: learn a little, remember it for good.',
  '每日签到 · 查看日历与连续签到': 'Daily check-in · calendar and streak',
  '今日计划': "Today's plan",
  'Review': 'Review',
  '昨日巩固': 'Review yesterday',
  '自定义练习': 'Custom practice',
  '开始今日计划': "Start today's plan",
  '继续上次练习': 'Continue last session',
  '上次练习': 'Last session',
  '考研': 'Postgraduate entrance exam',
  '本科期末': 'Undergraduate finals',
  '执医': 'Medical practitioner exam',
  '待复习提醒': 'Review reminders',
  '最近错题': 'Recent incorrect answers',
  '薄弱章节': 'Weak chapters',
  '优先订正': 'Priority correction',
  '先把刚错和反复错的知识点补牢，再扩展新题':
      'Strengthen recently and repeatedly missed points before expanding to new questions.',
  '暂无错题。完成练习后会自动归集。':
      'No incorrect answers yet. They will be collected automatically after practice.',
  '完成一些练习后，这里会出现章节建议。':
      'Chapter recommendations will appear here after you complete some practice.',
  '全部分类': 'All categories',
  '选择学习方向': 'Choose a learning track',
  '按学校分类': 'Browse by school',
  '查看各院校历年回忆题与资料包': 'Browse recalled exam questions and study packs by school.',
  '当前未收录内置题目。你仍可在“我的”导入自己的 JSON、Word 或 TXT 题库后练习。':
      'No built-in questions are available yet. You can still import your own JSON, Word, or TXT question bank from Me.',
  '按学科练习': 'Practice by subject',
  '题库建设中': 'Question bank in progress',
  '当前方向资料题不足 50 道，暂未开放常规练习':
      'This track has fewer than 50 source questions, so regular practice is not open yet.',
  '查看已收录': 'View available questions',
  '套卷练习': 'Mock-paper practice',
  '全部学科': 'All subjects',
  '章节目录': 'Chapter list',
  '开始练习': 'Start practice',
  '选择练习模式': 'Choose a practice mode',
  '顺序练习': 'Practice in order',
  '章节复习': 'Chapter review',
  '资料练习卷，不等于历年真题': 'Source-material practice papers; not official past papers.',
  '我的题本': 'My notebook',
  '疑问题为最近一次标记“蒙对／不稳”的题目':
      'Questionable answers are those most recently marked as guessed or uncertain.',
  '错题': 'Incorrect',
  '收藏': 'Saved',
  '疑问题': 'Uncertain',
  '笔记': 'Notes',
  '错题优先级': 'Incorrect-answer priority',
  '列表已按“今日刚错 → 反复错 → 其他 → 已掌握待归档”排序。移出错题本只改变你的题本标记，不会删除作答记录或复习排期。':
      'This list is ordered as: missed today → repeated mistakes → others → mastered/archive. Removing an item only changes your notebook marker; it does not delete answer records or review scheduling.',
  '收起筛选': 'Hide filters',
  '搜索题干、选项、解析或考点': 'Search questions, options, explanations, or key points',
  '学科': 'Subject',
  '章节': 'Chapter',
  '题型': 'Question type',
  '标签': 'Tags',
  '院校': 'School',
  '年份': 'Year',
  '全部': 'All',
  '练习': 'Practice',
  '还没有': 'Nothing here yet',
  '没有匹配的题目': 'No matching questions',
  '学习中的标记会保存在这里。': 'Your learning markers will be saved here.',
  '清空筛选': 'Clear filters',
  '知识点笔记': 'Key-point notes',
  '这些题暂未配置考点标签，仍可逐题回看笔记。':
      'These questions do not have key-point tags yet; you can still review their notes one by one.',
  '移出错题本，保留复习排期': 'Remove from incorrect notebook; keep review schedule',
  '学习看得见': 'Make learning visible',
  '本周按北京时间周一开始 · 跨学习方向统计':
      'This week starts Monday, Beijing time · across all learning tracks',
  '本周题数（去重）': 'Questions this week (unique)',
  '客观题正确率（按次）': 'Objective-question accuracy (per attempt)',
  '本周本机会话用时': 'On-device session time this week',
  '连续学习': 'Learning streak',
  '未记录': 'Not recorded',
  '用时从新版开始记录，按会话开始日期归属；旧记录与其他设备用时未计入。':
      'Time is recorded in the current version by session start date; legacy records and other devices are not included.',
  '近 7 天': 'Last 7 days',
  '近 7 天还没有作答记录': 'No answers recorded in the last 7 days',
  '完成一次练习后，这里会显示每天学过的题数。':
      'After a practice session, this will show how many questions you studied each day.',
  '下一步复盘': 'Next review',
  '根据错题、到期复习和正确率排序；从最需要补的章节开始':
      'Ordered by mistakes, due reviews, and accuracy. Start with the chapter that needs the most work.',
  '还没有需要优先复盘的章节。完成练习后会按你的真实作答生成建议。':
      'No priority chapters yet. Recommendations will use your actual answers after practice.',
  '已作答客观题正确率低于 80%': 'Objective-question accuracy below 80%',
  '暂无薄弱章节，完成练习后会生成建议。':
      'No weak chapters yet. Recommendations will appear after practice.',
  '复习已学题目': 'Review studied questions',
  '还没有聊天': 'No conversations yet',
  '添加好友后，就可以在这里开始对话。': 'Add a friend to start a conversation here.',
  '开始聊天吧': 'Start chatting',
  '输入消息…': 'Type a message…',
  '消息': 'Messages',
  '聊天': 'Chats',
  '好友': 'Friends',
  '通知': 'Notifications',
  '添加好友': 'Add friend',
  '搜索': 'Search',
  '发送': 'Send',
  '刷新': 'Refresh',
  '全部已读': 'Mark all as read',
  '还没有消息': 'No notifications yet',
  '收到点赞、评论、好友申请或聊天时会显示在这里。':
      'Likes, comments, friend requests, and chats appear here.',
  '发送一条消息，和好友交流学习心得。': 'Send a message and share what you are learning.',
  '选择一个对话': 'Choose a conversation',
  '从左侧选择好友开始聊天。': 'Choose a friend on the left to start chatting.',
  '未送达': 'Not delivered',
  '已发送': 'Sent',
  '忽略': 'Ignore',
  '通过': 'Accept',
  '处理中…': 'Processing…',
  '查看原题': 'View question',
  '输入昵称后按搜索键': 'Enter a nickname, then press Search.',
  '还没有好友': 'No friends yet',
  '本机暂未收录这道题，请先更新离线题库':
      'This question is not available on this device. Please update the offline question bank first.',
  '分享了一道题': 'Shared a question',
  '好友申请': 'Friend request',
  '已同意你的好友申请': 'Accepted your friend request',
  '给你点了赞': 'Liked your post',
  '评论了你的内容': 'Commented on your content',

  // Common study controls.
  '上一题': 'Previous',
  '下一题': 'Next',
  '完成': 'Finish',
  '完成作答': 'Finish answers',
  '继续下一题': 'Continue',
  '确认多选答案': 'Confirm selected answers',
  '多选题 · 选完后提交': 'Multiple choice · submit when ready',
  '多选题 · 选完后进入下一题': 'Multiple choice · continue when ready',
  '写下你的分析要点': 'Write the main points of your answer',
  '回答正确': 'Correct',
  '回答错误': 'Incorrect',
  '标记做错并完成': 'Record mistake and finish',
  '标记做错并继续': 'Record mistake and continue',
  '完成作答后统一看解析': 'Review explanations after answering the batch',
  '已作答题目': 'Answered question',
  '速刷模式': 'Speed practice',
  '速刷完成': 'Speed practice complete',
  '完成速刷': 'Finish speed practice',
  '批量刷题': 'Batch practice',
  '批量刷题完成': 'Batch practice complete',
  '统一查看解析': 'Review explanations',
  '下一题解析': 'Next explanation',
  '整批提交': 'Submit batch',
  '保存中…': 'Saving…',
  '继续评级': 'Continue rating',
  '参考答案：': 'Answer: ',
  '你的作答：': 'Your answer: ',
  '解析与评级': 'Explanation & rating',
  '连续作答': 'Continuous answers',
  '题目笔记': 'Question notes',
  '筛选': 'Filter',
  '再显示 20 题': 'Show 20 more',
  '学习巩固': 'Learning review',
  '本题考点': 'Key point',
  '写评论': 'Write a comment',
  '回复': 'Reply',
  '发布评论': 'Post comment',
  '发布中…': 'Posting…',
  '删除': 'Delete',
  '结束': 'End',
  '结束练习': 'End practice',
  '继续刷题': 'Keep practicing',
  '回到当前题': 'Return to current question',
  '再看上一道': 'View previous question',
  '答对自动下一题': 'Automatically continue after a correct answer',
  '逐题深度': 'Deep question-by-question',
  '批量练习': 'Batch practice',
  '速刷': 'Speed practice',
  '已作答 · 仅查看': 'Answered · view only',
  '保存失败，请重试：': 'Save failed. Please try again: ',
  '结束批量刷题？': 'End batch practice?',
  '答案和当前进度会保留；整批提交后才更新复习排期。':
      'Your answers and progress will be kept. The review schedule updates after the whole batch is submitted.',
  '整批保存失败，请重试：': 'Could not save the batch. Please try again: ',
  '请确认掌握程度': 'Confirm your mastery level',
  '客观题答错，已自动标记“做错”':
      'Incorrect objective answer: marked as incorrect automatically.',
  '整批提交后进入复习队列，无需再次确认。':
      'It will enter the review queue after batch submission; no further confirmation needed.',
  '题目讨论': 'Question discussion',
  '暂时还没有讨论，留下你的理解吧。': 'No discussion yet. Share your understanding.',
  '删除这条评论？': 'Delete this comment?',
  '删除后不再显示评论内容，其他同学的回复会保留。':
      'The comment will no longer be visible; other students’ replies will remain.',
  '学习用时': 'Study time',
  '继续学习': 'Keep learning',
  '返回今日': 'Back to Today',
  '本次暂无低于 80% 的客观题章节。': 'No objective-question chapter is below 80% this time.',
  '本次练习完成': 'Practice complete',
  '本次薄弱章节': 'Weak chapters in this session',
  '旧版未记录的答案和用时不计入本次统计。': 'Answers and time not recorded in older versions are excluded from this summary.',

  // Check-in and summary.
  '每日签到': 'Daily check-in',
  '今日已签到': 'Checked in today',
  '签到 +1': 'Check in +1',
  '签到中…': 'Checking in…',
  '补签': 'Make-up check-in',
  '再想想': 'Not now',
  '消耗 5 颗补签': 'Use 5 make-up tokens',
  '补签中…': 'Checking in…',

  // Membership and contact.
  '会员详情': 'Membership details',
  '查看续费方案': 'View renewal options',
  '你已经是 VIP 会员': 'You are a VIP member',
  '仅作者': 'Author only',
  '微信': 'WeChat',
  '支付宝': 'Alipay',
  '未绑定': 'Not connected',
  '会员支付': 'VIP membership',
  '了解会员详情': 'Learn about VIP',
  '题库还在搭建，请勿充值。':
      'The question bank is still being built. Please do not make a payment yet.',
  '查看充值方案': 'View payment options',
  '会员有效至': 'VIP valid until',
  '终身有效': 'Valid for life',
  '会员有效期正在确认': 'Confirming your VIP validity…',
  '会员服务说明': 'Membership details',
  '支付宝支付': 'Pay with Alipay',
  '微信支付': 'Pay with WeChat',
  '前往支付宝': 'Continue to Alipay',
  '确认前往支付宝': 'Confirm Alipay checkout',
  '我已阅读会员服务说明与退款规则': 'I have read the membership details and refund policy.',
  '支付已确认，VIP 服务已开通': 'Payment confirmed. Your VIP service is active.',
  '该支付订单已关闭': 'This payment order has been closed.',
  '支付结果正在确认，请稍后在“我的”查看':
      'Your payment is being confirmed. Please check Me shortly.',
  '暂未确认支付结果，请稍后在“我的”查看':
      'We have not confirmed the payment yet. Please check Me shortly.',
  '支付状态：': 'Payment status: ',

  // Settings and appearance.
  '淡背景色': 'Pale background',
  '主色调': 'Primary color',
  '请选择 JPG、PNG 或 WebP 格式的图片': 'Please choose a JPG, PNG, or WebP image.',
  '背景已保存，并按图片主色匹配为': 'Background saved and matched to its primary color: ',
  '玻璃预览': 'Glass preview',
  '自定义图片背景': 'Custom image background',
  '仅保存在本设备，不上传服务器、不参与账号同步。支持 JPG / PNG / WebP；原图不超过 8 MB，建议 16:9 或 9:16 图片。系统会压缩为适合网页本机保存的背景，暂不支持 HEIC、GIF、PDF 或截图文件夹。':
      'Stored only on this device; never uploaded or synced. JPG, PNG, and WebP are supported (up to 8 MB); 16:9 or 9:16 works best. Images are compressed for browser storage. HEIC, GIF, PDF, and screenshot folders are not supported.',
  '移除图片背景': 'Remove image background',
  '选择主题，或自由搭配主色与淡背景。': 'Choose a theme or freely combine a primary color and pale background.',
  '自定义': 'Custom',
  '自定义配色已启用': 'Custom colors are enabled',
  '正在处理图片…': 'Processing image…',
  '更换背景图片': 'Change background image',
  '选择背景图片': 'Choose a background image',
  '玻璃质感': 'Glass effect',
  '透出背景的清澈折射卡片与半透明导航':
      'Translucent cards and navigation that reveal the background.',
  '每日新题上限（0–1,000,000）': 'Daily new-question limit (0–1,000,000)',
  '复习题不设上限': 'No review-question limit',
  '每日复习题目标（0–200）': 'Daily review-question goal (0–200)',
  '复习与学习新题可自主安排；新题上限只限制当天新增题数。':
      'Arrange reviews and new questions freely; the new-question limit applies only to new questions added today.',
  '新题上限为 0–1,000,000；复习目标为 0–200':
      'The new-question limit is 0–1,000,000 and the review goal is 0–200.',

  // Calendar, practice, search and notes.
  '上个月': 'Previous month',
  '下个月': 'Next month',
  '一': 'Mon',
  '二': 'Tue',
  '三': 'Wed',
  '四': 'Thu',
  '五': 'Fri',
  '六': 'Sat',
  '日': 'Sun',
  '今日已签到，已获得 1 颗': 'Checked in today; earned 1 ',
  '补签成功，已消耗 5 颗': 'Make-up check-in successful. Used 5 ',
  '可选择过去未签到日期补签：5 颗/次，今天还可补 ': 'Choose an earlier missed day to make up: 5 tokens each. Remaining today: ',
  '今天的补签次数已用完，明天再来。': 'You have used all make-up check-ins for today. Please come back tomorrow.',
  '题目编号：': 'Question ID: ',
  '收藏题目': 'Save question',
  '取消收藏': 'Remove saved question',
  '分享给好友': 'Share with a friend',
  '分享题目给好友': 'Share question with a friend',
  '还没有好友。添加好友后就能把题目送进聊天框。':
      'You have no friends yet. Add a friend to send questions in chat.',
  '搜索题目': 'Search questions',
  '搜索已开放题库': 'Search the available question bank',
  '全部已开放学科': 'All available subjects',
  '输入疾病、关键词或题目编号': 'Enter a condition, keyword, or question ID',
  '清空搜索': 'Clear search',
  '清空范围筛选': 'Clear scope filters',
  '例如：牙周炎、种植、咬合、RPA': 'For example: periodontitis, implants, occlusion, RPA',
  '没有同时包含这些关键词的题目。可以减少关键词或扩大搜索范围。':
      'No questions contain all of these keywords. Try fewer keywords or a wider scope.',
  '搜索结果解析': 'Search result explanation',
  '共 ': 'Total ',
  '结束本次练习？': 'End this practice session?',
  '写下你的分析要点，再对照参考答案自评':
      'Write down your reasoning, then compare it with the reference answer.',
  '确认作答 · 查看解析': 'Confirm answer · view explanation',
  '答错将排入次日复习；只有标记掌握度后才保存本题。':
      'Incorrect answers enter tomorrow’s review. This question is saved only after you rate your mastery.',
  '写题目笔记': 'Write a question note',
  '交卷并分析': 'Submit & analyze',
  '你的作答': 'Your answer',
  '未作答': 'Not answered',
  '再看上一题': 'View previous question',
  '个人笔记': 'Personal note',
  '记录你的理解与易混点': 'Record your understanding and tricky points',
  '确认交卷': 'Confirm submission',
  '继续检查': 'Keep checking',
  '交卷': 'Submit',
  '本次练习已完成': 'Practice complete',
  '返回学习首页': 'Back to learning home',
  '反复错题会优先出现在错题本和今日建议中；完成订正后仍按原有间隔复习安排。':
      'Repeated mistakes are prioritized in your notebook and today’s suggestions. Their original review schedule remains after correction.',
  '旧版记录仅保留题目，答案未记录。':
      'Legacy records keep the questions only; answers were not recorded.',
  '今天没有到期题，按计划学习新题即可。':
      'No questions are due today. Continue with planned new questions.',
  '提交失败，作答仍保留在本页：': 'Submission failed. Your answers remain on this page: ',
  '保存当前作答与原截止时间，恢复后继续计时。':
      'Save your answers and original deadline; the timer continues after you resume.',
  '已标记掌握度的题目已保存，当前答案和进度会保存，稍后可继续。':
      'Questions with a mastery rating are saved. Your current answers and progress will also be saved so you can continue later.',
  '本次练习分析': 'Practice analysis',
  '限时模考': 'Timed mock exam',
  '今日巩固': 'Today’s review',
  '专注练习': 'Focused practice',
  '对照要点，自评掌握度': 'Compare key points and rate your mastery',
  '回答正确，再确认掌握度': 'Correct answer — now confirm your mastery',
  '这道题值得再巩固': 'This question deserves another review',
  '做错': 'Incorrect',
  '蒙对 / 不稳': 'Guessed / uncertain',
  '完全掌握': 'Mastered',
  '未答客观题记 0 分。主观题对照要点自评，不计入自动得分。答对题目先按“蒙对 / 不稳”安排复习。':
      'Unanswered objective questions receive 0 points. Self-rate subjective questions against the key points; they are not auto-scored. Correct answers are initially scheduled as guessed/uncertain for review.',
  '客观题正确 ': 'Objective questions correct: ',
  '主观题不包含在自动得分中；请在下方完成自评。':
      'Subjective questions are not included in automatic scoring. Please self-rate below.',
  '逐题回顾': 'Question-by-question review',
  '对照要点后自评（仅保存一次）': 'Self-rate after comparing key points (saved once)',
  '不稳': 'Uncertain',
  '掌握': 'Mastered',

  // Profile, social and token wallet.
  '编辑个人资料': 'Edit profile',
  '支付宝会员服务暂未开放': 'Alipay VIP service is not available yet.',
  '支付链接无效，请稍后重试': 'The payment link is invalid. Please try again later.',
  '点击“前往支付宝”后会跳转至支付宝收银台；是否付款、扣款金额和支付结果均以支付宝页面为准。支付成功后将返回本站确认会员状态。':
      'Selecting “Continue to Alipay” opens the Alipay checkout. Payment, charges, and results are determined on Alipay. After successful payment, you will return here to confirm membership.',
  '正在处理…': 'Processing…',
  '上传 JSON 题库': 'Upload JSON question bank',
  '我只有 Word / 纯文字': 'I only have Word / plain text',
  '上传一次即可导入本机练习，并同步到仅作者可见的私密审核箱。':
      'Upload once to import practice questions on this device and sync them to a private, author-only review inbox.',
  '不会自动进入公开题库。请仅上传你有权分享的资料；不要上传含个人隐私、受限或来源不明的内容。':
      'Uploads never enter the public question bank automatically. Only upload materials you are authorized to share; do not upload personal, restricted, or unknown-source content.',
  '查看发布者、题目与评论': 'View authors, questions, and comments',
  '评论管理': 'Comment management',
  '发送给': 'Send to ',
  '青绿': 'Teal',
  '湖蓝': 'Lake blue',
  '紫藤': 'Wisteria',
  '暖橙': 'Warm orange',
  '玫瑰': 'Rose',
  '靛蓝': 'Indigo',
  '绛红': 'Crimson',
  '可可': 'Cocoa',
  '松绿': 'Forest green',
  '橄榄': 'Olive',
  '洋红': 'Magenta',
  '石墨': 'Graphite',
  '羟基磷灰石': 'Hydroxyapatite',
  '恭喜': 'Great!',
  '真棒': 'Well done!',
  '真厉害': 'Amazing!',
  '再接再厉': 'Keep going!',
  '今天也在发光': 'You are shining today!',
  '我的石头小金库': 'My token wallet',
  '账号已变更，请返回“我的”重新进入。':
      'The account changed. Return to Me and open this page again.',
  '明细 >': 'History >',
  '可用石头 · 一颗也是你努力的硬通货': 'Available tokens · every one represents your effort',
  '1 颗抵 ¥0.02': '1 token = ¥0.02',
  '重新加载': 'Reload',
  '石头明细': 'Token history',
  '北京时间 · 每一颗石头都有来路': 'Beijing time · every token has a record',
  '还没有明细。第一颗石头，正在等你签到。':
      'No history yet. Your first token is waiting for your check-in.',
  '再翻一页': 'Load more',
  '确认这笔石头开销？': 'Confirm this token payment?',
  'VIP · 石头也能买单': 'VIP · pay with tokens too',
  '查看服务与规则': 'View services & policies',
  '同考点解析': 'Related key-point explanations',
  '重选方案': 'Choose another option',
  '使用最大可抵扣数量': 'Use the maximum discount',
  '兑换与支付正在准备中，请勿充值。规则和数量先给你安排明白。':
      'Redemption and payment are being prepared. Please do not top up yet.',
  '齿间 DentStudy': 'DentStudy',
  '一起在齿间刷题，把知识学进脑袋，把石头攒进小金库。https://dentstudy.uno':
      'Practice with DentStudy, build knowledge, and collect tokens. https://dentstudy.uno',
  '今天的分享石头已到账，明天再来挖一颗。':
      'Today’s share token has been credited. Come back tomorrow for another one.',
  '当前设备无法确认系统分享，请换用支持分享的手机浏览器或 App。':
      'This device cannot confirm a system share. Try a mobile browser or app that supports sharing.',
  '这次分享没有完成，石头先等你一下。':
      'The share was not completed this time. Your token will wait for you.',
  '签到 +1：每天来露个牙。': 'Check in +1: show up every day.',
  '连续签到每满 7 天，额外 +7；断签重新计数。':
      'Every 7 consecutive check-ins earns an extra +7; a missed day resets the streak.',
  '可补签过去未签到日期：5 颗/次，每天最多 3 次；补出第 7 天同样额外 +7。':
      'Make up a previously missed day for 5 tokens, up to 3 times daily; making up the 7th day also earns +7.',
  '每日首次完成学习目标 +1，首次完成复习目标 +1。':
      'Your first completed learning goal each day earns +1; your first completed review goal earns +1.',
  '每日首次系统分享 +1；取消或单独复制链接不计。':
      'Your first system share each day earns +1; cancelled shares and copied links do not count.',
  '成功上传有效题库，每份 +1，每日最多 +3；相同内容不重复奖励。':
      'Each valid question-bank upload earns +1, up to +3 daily; identical content is not rewarded again.',
  '石头是站内奖励，不是现金；不可转赠、充值或提现。组合支付先预扣石头，确认关闭或退款后原路返还。':
      'Tokens are in-app rewards, not cash. They cannot be transferred, topped up, or withdrawn. Mixed payment pre-deducts tokens and returns them if the order closes or is refunded.',
  '分享处理中…': 'Sharing…',
  '今日已分享': 'Shared today',
  '系统分享 · 今日首次 +1': 'System share · first today +1',
  '怎么攒石头？': 'How to earn tokens',
  '以上按北京时间每日结算。学习与复习以当天首次同步时锁定的服务器目标为准，需至少完成 1 题；重复刷同题不凑数，历史补同步和本机私有题库不补发。':
      'These rewards settle daily in Beijing time. Learning and review use the server goals locked at the first sync that day; complete at least one question. Repeating the same question does not count, and no retroactive reward is issued for historical syncs or local private question banks.',
  '石头数量不合适，请检查余额与抵扣数量。':
      'That token amount is not valid. Check your balance and discount amount.',
  '石头出发，VIP 到家！': 'Tokens sent — VIP is on its way!',
  '努力攒的石头，现在派上用场': 'Put your hard-earned tokens to use',
  '1 羟基磷灰石抵 ¥0.02；例如 ¥6.90 = 345 颗。':
      '1 hydroxyapatite token = ¥0.02; for example, ¥6.90 = 345 tokens.',
  'VIP 权益：全题库学习、每日新题不限量、小齿深度思考及跨设备学习记录同步。':
      'VIP includes the full question bank, unlimited new questions each day, Xiaochi deep thinking, and cross-device learning-record sync.',
};
