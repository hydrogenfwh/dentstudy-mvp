import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../app/shared.dart';
import '../../app/build_info.dart';
import '../../app/language_selector.dart';
import 'user_avatar.dart';
import 'profile_editor.dart';
import 'author_comments_page.dart';
import 'author_records_page.dart';
import 'settings_page.dart';
import 'question_bank_import_help.dart';
import 'imported_bank_practice.dart';
import 'question_bank_import_progress.dart';
import 'text_bank_converter.dart';
import 'alipay_checkout.dart';
import 'vip_emblem.dart';
import 'stone_wallet_page.dart';
import 'stone_reward_notice.dart';
import '../practice/practice_request.dart';
import '../social/social_inbox_page.dart';
import '../social/unread_dot.dart';

class ProfilePage extends StatefulWidget {
  final StartPractice onStart;
  const ProfilePage({super.key, required this.onStart});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String get _session => '${store.userId}:${store.token}';
  late String observedSession;
  bool importingBank = false;
  QuestionBankImportStage importStage = QuestionBankImportStage.idle;
  String importProgressDetail = '';
  bool isSubmissionAdmin = false;
  int? submissionCount;
  bool loadingProfile = false;
  Map<String, dynamic> accountProfile = {};
  Map<String, dynamic> paymentOffer = {};
  int? stoneBalance;
  int? dailyUploadRewardCount;
  bool openingAlipay = false;
  int? authorUserCount;
  // Keep the exact offset while this State survives a glass-style rebuild.
  // PageStorage is intentionally disabled: an ancestor PageStorage bucket is
  // also used by expandable profile tools and would otherwise restore the
  // ListView's numeric offset as their boolean expanded state.
  final ScrollController _scrollController =
      ScrollController(keepScrollOffset: false);

  bool get isPaymentAuthor => accountProfile['isPaymentAuthor'] == true;
  @override
  void initState() {
    super.initState();
    observedSession = _session;
    store.addListener(accountChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => refreshAccountData());
  }

  @override
  void dispose() {
    store.removeListener(accountChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void accountChanged() {
    if (!mounted || observedSession == _session) return;
    observedSession = _session;
    setState(() {
      accountProfile = {};
      paymentOffer = {};
      stoneBalance = null;
      dailyUploadRewardCount = null;
      isSubmissionAdmin = false;
      submissionCount = null;
      authorUserCount = null;
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void updateImportProgress(QuestionBankImportStage stage, String detail) {
    if (!mounted) return;
    setState(() {
      importStage = stage;
      importProgressDetail = detail;
    });
  }

  void clearImportProgress() =>
      updateImportProgress(QuestionBankImportStage.idle, '');

  String readableImportError(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  Future<void> refreshSubmissionInbox() async {
    if (store.token.isEmpty) {
      if (mounted)
        setState(() {
          isSubmissionAdmin = false;
          submissionCount = null;
          authorUserCount = null;
        });
      return;
    }
    try {
      final result = await store.questionBankSubmissions();
      if (!mounted) return;
      setState(() {
        isSubmissionAdmin = result['isAdmin'] == true;
        submissionCount = (result['submissions'] as List).length;
      });
      if (isSubmissionAdmin) await refreshAuthorUserDirectory();
    } catch (_) {
      // The personal learning experience stays usable if the optional inbox
      // endpoint is unavailable while an older server is being updated.
    }
  }

  Future<void> refreshAccountData() async {
    await refreshProfile();
    await Future.wait([
      refreshSubmissionInbox(),
      refreshPaymentOffer(),
      refreshSocialBadge(),
      refreshStoneBalance(),
    ]);
  }

  /// The account card is the quick way back to the stone wallet.  Fetch the
  /// current balance independently of the profile so a rolling server update
  /// cannot make an otherwise usable profile disappear.
  Future<void> refreshStoneBalance() async {
    if (store.token.isEmpty) {
      if (mounted) {
        setState(() {
          stoneBalance = null;
          dailyUploadRewardCount = null;
        });
      }
      return;
    }
    final accountId = store.userId;
    try {
      final wallet = await store.stoneWallet();
      if (mounted && store.userId == accountId) {
        setState(() {
          stoneBalance = (wallet['balance'] as num?)?.toInt();
          dailyUploadRewardCount = _uploadRewardCount(wallet);
        });
      }
    } catch (_) {
      // Stone rewards are an optional enhancement to the profile. Keep the
      // entry useful even if an old server has not exposed the wallet yet.
      if (mounted && store.userId == accountId) {
        setState(() {
          stoneBalance = null;
          dailyUploadRewardCount = null;
        });
      }
    }
  }

  /// New servers supply an authoritative total that is independent of wallet
  /// pagination.  Keep the ledger calculation only for an older server during
  /// a rolling release, so the import affordance remains useful either way.
  int _uploadRewardCount(Map<String, dynamic> wallet) {
    final reported = wallet['uploadRewardCountToday'];
    if (reported is num) {
      final count = reported.toInt();
      return count < 0 ? 0 : (count > 3 ? 3 : count);
    }
    return _uploadsRewardedToday(wallet);
  }

  /// A backward-compatible fallback for servers that predate
  /// ``uploadRewardCountToday``. A temporarily unavailable wallet deliberately
  /// renders an ellipsis rather than claiming a made-up "0/3".
  int _uploadsRewardedToday(Map<String, dynamic> wallet) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final entries = wallet['items'];
    if (entries is! List) return 0;
    var count = 0;
    for (final raw in entries.whereType<Map>()) {
      final entry = Map<String, dynamic>.from(raw);
      if (entry['reason'] != '上传题库') continue;
      final createdAt = DateTime.tryParse(entry['createdAt'] as String? ?? '')
          ?.toUtc()
          .add(const Duration(hours: 8));
      if (createdAt != null &&
          createdAt.year == now.year &&
          createdAt.month == now.month &&
          createdAt.day == now.day) {
        count++;
      }
    }
    return count > 3 ? 3 : count;
  }

  Future<void> refreshProfile() async {
    if (store.token.isEmpty) {
      if (mounted) {
        setState(() {
          accountProfile = {};
          paymentOffer = {};
        });
      }
      return;
    }
    if (mounted) setState(() => loadingProfile = true);
    try {
      final result = await store.profile();
      if (mounted) setState(() => accountProfile = result);
    } catch (_) {
      // An older API must not block access to locally stored learning data.
    } finally {
      if (mounted) setState(() => loadingProfile = false);
    }
  }

  Future<void> refreshPaymentOffer() async {
    if (store.token.isEmpty || !isPaymentAuthor) {
      if (mounted) setState(() => paymentOffer = {});
      return;
    }
    try {
      final result = await store.alipayOffer();
      if (mounted) setState(() => paymentOffer = result);
    } catch (_) {
      // A rolling deployment or incomplete merchant configuration must not
      // expose a payable control. The server is authoritative here.
      if (mounted) setState(() => paymentOffer = {});
    }
  }

  Future<void> showAlipayCheckout(Map<String, dynamic> plan) async {
    if (openingAlipay || store.token.isEmpty) return;
    if (paymentOffer['available'] != true) await refreshPaymentOffer();
    if (!mounted || paymentOffer['available'] != true) {
      if (mounted) message(context, '支付宝会员服务暂未开放');
      return;
    }
    final planId = plan['id'] as String? ?? '';
    final price = plan['displayPrice'] as String? ?? '';
    final title = tr(plan['name'] as String? ?? 'VIP');
    final description = tr(plan['description'] as String? ?? '');
    var agreed = false;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
                    title: Text(tr('确认前往支付宝')),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text('DentStudy VIP · $title · ¥$price\n'
                              '$description\n\n'
                              '点击“前往支付宝”后会跳转至支付宝收银台；是否付款、扣款金额和支付结果均以支付宝页面为准。支付成功后将返回本站确认会员状态。')),
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: agreed,
                          onChanged: (value) =>
                              setDialogState(() => agreed = value ?? false),
                          title: Text(tr('我已阅读会员服务说明与退款规则'),
                              style: TextStyle(fontSize: 13))),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(tr('取消'))),
                      FilledButton(
                          onPressed: agreed
                              ? () => Navigator.pop(dialogContext, true)
                              : null,
                          child: Text(tr('前往支付宝'))),
                    ])));
    if (confirmed != true || !mounted) return;
    setState(() => openingAlipay = true);
    try {
      final result = await store.createAlipayCheckout(planId,
          mobileWeb: shouldUseAlipayWap());
      final checkoutUrl = result['checkoutUrl'];
      if (checkoutUrl is! String || !checkoutUrl.startsWith('https://')) {
        throw Exception('支付链接无效，请稍后重试');
      }
      openAlipayCheckout(checkoutUrl);
    } catch (error) {
      if (mounted) message(context, readableImportError(error));
    } finally {
      if (mounted) setState(() => openingAlipay = false);
    }
  }

  Future<void> refreshSocialBadge() => store.refreshSocialUnread();

  Future<void> openSocialInbox() async {
    if (store.token.isEmpty) {
      await showAccountDialog(context, onSuccess: refreshAccountData);
      if (!mounted || store.token.isEmpty) return;
    }
    await Navigator.push<void>(
        context, MaterialPageRoute(builder: (_) => const SocialInboxPage()));
    if (mounted) await refreshSocialBadge();
  }

  Future<void> showPaymentOptions() async {
    if (store.token.isEmpty) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const StoneVipPage()));
    if (mounted) await refreshAccountData();
  }

  Future<void> refreshAuthorUserDirectory() async {
    if (!isSubmissionAdmin || store.token.isEmpty) return;
    try {
      final result = await store.authorUsers();
      if (mounted)
        setState(() {
          authorUserCount =
              result['totalCount'] as int? ?? (result['users'] as List).length;
        });
    } catch (_) {
      // The author inbox remains optional while a rolling deployment updates.
    }
  }

  Future<void> openAuthorRecords(AuthorRecordKind kind) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => AuthorRecordsPage(kind: kind)));
    if (mounted) await refreshSubmissionInbox();
  }

  Future<bool> ensureUploadAccount() async {
    if (store.token.isNotEmpty) return true;
    await showAccountDialog(context, onSuccess: refreshAccountData);
    return mounted && store.token.isNotEmpty;
  }

  Future<void> importAndSyncQuestionBank(
      {required String filename, required String content}) async {
    updateImportProgress(QuestionBankImportStage.validating, '正在核对题干、选项与答案…');
    // Yield to the event loop before the synchronous normalisation work. The
    // staged UI is therefore visible, while each transition still maps to real
    // work instead of a fabricated upload percentage.
    final prepared =
        await Future(() => store.prepareQuestionBankImport(content));
    final alreadyImported = store.hasImportedQuestionBank(prepared);
    updateImportProgress(
        QuestionBankImportStage.saving,
        alreadyImported
            ? '已发现相同题库，正在恢复本机练习…'
            : '正在保存 ${prepared.questions.length} 道题到本机练习…');
    final imported = alreadyImported
        ? prepared.questions.length
        : await store.importPreparedQuestionBank(prepared);
    updateImportProgress(QuestionBankImportStage.syncing, '正在完成导入保存…');
    try {
      final submitted = await store.submitQuestionBank(
          filename: filename, content: prepared.content);
      updateImportProgress(
          QuestionBankImportStage.complete,
          submitted['duplicate'] == true
              ? '已恢复 $imported 道题；这份题库此前已保存。'
              : '已导入 $imported 道题，现在可以开始练习。');
      if (mounted) {
        message(
            context,
            submitted['duplicate'] == true
                ? '已导入 $imported 道题；这份题库此前已保存。'
                : '已导入 $imported 道题，现在可以开始练习。');
      }
      await Future.wait([refreshSubmissionInbox(), refreshStoneBalance()]);
    } catch (error) {
      updateImportProgress(
          QuestionBankImportStage.partial, '已导入 $imported 道题，但云端保存暂未完成。');
      if (mounted) {
        message(
            context, '已导入 $imported 道题；云端保存未完成：${readableImportError(error)}');
      }
    }
  }

  Future<void> pickQuestionBank() async {
    setState(() {
      importingBank = true;
      importStage = QuestionBankImportStage.reading;
      importProgressDetail = '请选择需要导入的 JSON 题库…';
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['json'],
          withData: true);
      if (picked == null) {
        clearImportProgress();
        return;
      }
      final file = picked.files.single;
      if (!file.name.toLowerCase().endsWith('.json') || file.bytes == null) {
        throw Exception('请选择可以读取的 .json 题库文件');
      }
      updateImportProgress(
          QuestionBankImportStage.reading, '正在读取 ${file.name}…');
      final content = utf8.decode(file.bytes!, allowMalformed: false);
      if (!await ensureUploadAccount()) {
        clearImportProgress();
        return;
      }
      await importAndSyncQuestionBank(filename: file.name, content: content);
    } on FormatException {
      updateImportProgress(
          QuestionBankImportStage.failed, '文件编码无法识别，请保存为 UTF-8 后重试。');
      if (mounted) message(context, '文件编码无法识别，请保存为 UTF-8 后重试。');
    } catch (error) {
      updateImportProgress(
          QuestionBankImportStage.failed, readableImportError(error));
      if (mounted) message(context, readableImportError(error));
    } finally {
      if (mounted) setState(() => importingBank = false);
    }
  }

  Future<void> importFromWordOrText() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('从 Word / 纯文字生成题库',
                      style:
                          TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('支持 .docx、.txt 或直接粘贴文字；请先确认文件能按题目格式读取。',
                      style: TextStyle(color: Colors.blueGrey)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, 'file'),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text('选择 Word / 文本文件')),
                  TextButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, 'paste'),
                      icon: const Icon(Icons.paste_outlined),
                      label: Text('直接粘贴纯文字'))
                ]))));
    if (choice == null || !mounted) return;
    setState(() {
      importingBank = true;
      importStage = QuestionBankImportStage.reading;
      importProgressDetail =
          choice == 'file' ? '请选择 Word 或 TXT 文件…' : '正在准备文字转换…';
    });
    try {
      String sourceText;
      String sourceName;
      if (choice == 'file') {
        final picked = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const ['docx', 'txt'],
            withData: true);
        if (picked == null) {
          clearImportProgress();
          return;
        }
        final file = picked.files.single;
        final extension = file.extension?.toLowerCase();
        if (file.bytes == null || !const ['docx', 'txt'].contains(extension)) {
          throw Exception('仅支持 .docx 或 .txt；暂不支持 .doc、PDF、图片');
        }
        if (file.bytes!.length > maxTextSourceBytes) {
          throw Exception('Word / 文本文件不能超过 5 MB');
        }
        updateImportProgress(
            QuestionBankImportStage.reading, '正在读取 ${file.name}…');
        sourceText = extension == 'docx'
            ? await Future(() => extractDocxText(file.bytes!))
            : utf8.decode(file.bytes!, allowMalformed: false);
        sourceName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      } else {
        sourceText = '';
        sourceName = '文字转换题库';
      }
      updateImportProgress(
          QuestionBankImportStage.validating, '已读取内容，请确认题目格式…');
      if (!await ensureUploadAccount()) {
        clearImportProgress();
        return;
      }
      final converted = await showTextBankConverter(context,
          initialText: sourceText,
          initialName: sourceName, aiConvert: (request) async {
        updateImportProgress(
            QuestionBankImportStage.validating, 'AI 正在核对原文中的题干、选项与答案…');
        final result = await store.prepareQuestionBankWithAi(
            text: request.text,
            name: request.name,
            subject: request.subject,
            chapter: request.chapter,
            mode: request.mode);
        return TextBankConversion(
            filename: result['filename'] as String,
            content: result['content'] as String);
      });
      if (converted == null || !mounted) {
        clearImportProgress();
        return;
      }
      await importAndSyncQuestionBank(
          filename: converted.filename, content: converted.content);
    } on FormatException {
      updateImportProgress(
          QuestionBankImportStage.failed, '文本编码无法识别，请保存为 UTF-8 后重试。');
      if (mounted) message(context, '文本编码无法识别，请保存为 UTF-8 后重试。');
    } catch (error) {
      updateImportProgress(
          QuestionBankImportStage.failed, readableImportError(error));
      if (mounted) message(context, readableImportError(error));
    } finally {
      if (mounted) setState(() => importingBank = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      PageBody(controller: _scrollController, children: profile());
  List<Widget> profile() => [
        const SizedBox(height: 24),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            final colors = Theme.of(context).colorScheme;
            final nickname = accountProfile['nickname'] as String? ?? '齿间同学';
            final university = accountProfile['university'] as String? ?? '';
            final identity = Row(children: [
              UserAvatar(
                  value: accountProfile['avatar'] as String? ?? 'book',
                  radius: 34,
                  vip: accountProfile['isVip'] == true),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        store.needsSignIn
                            ? tr('登录已过期')
                            : (store.token.isEmpty ? '访客同学' : nickname),
                        style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface)),
                    const SizedBox(height: 5),
                    Text(
                        store.needsSignIn
                            ? tr('学习记录保存在本机，重新登录后继续同步。')
                            : store.token.isEmpty
                                ? '把进步留在每一天'
                                : (university.isEmpty ? '填写你的就读院校' : university),
                        style: TextStyle(color: colors.onSurfaceVariant)),
                  ])),
            ]);
            final actions = Row(mainAxisSize: MainAxisSize.min, children: [
              _StoneWalletEntry(
                  balance: stoneBalance,
                  onPressed: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const StoneWalletPage()));
                    if (mounted) await refreshStoneBalance();
                  }),
              _ProfileMessageButton(onPressed: openSocialInbox),
              IconButton(
                  tooltip: tr('编辑个人资料'),
                  onPressed: loadingProfile ? null : editProfile,
                  icon: const Icon(Icons.edit_outlined))
            ]);
            if (constraints.maxWidth < 460) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    if (store.token.isNotEmpty)
                      Align(alignment: Alignment.centerRight, child: actions),
                  ]);
            }
            return Row(children: [
              Expanded(child: identity),
              if (store.token.isNotEmpty) actions
            ]);
          }),
          if (store.email.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: Text(store.email,
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
              TextButton(
                  onPressed: store.syncing
                      ? null
                      : () async {
                          await safely(context, store.logout);
                          await refreshAccountData();
                        },
                  child: Text(tr(store.needsSignIn ? '切换到访客' : '退出登录')))
            ])
          ],
          if (store.token.isEmpty) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: () =>
                    showAccountDialog(context, onSuccess: refreshAccountData),
                icon: const Icon(Icons.person_outline),
                label: Text(tr(store.needsSignIn ? '重新登录' : '登录 / 注册')))
          ]
        ])),
        if (store.token.isNotEmpty) ...[
          const SizedBox(height: 16),
          _AuthorPaymentEntryCard(
              isVip: accountProfile['isVip'] == true,
              vipTrial: accountProfile['vipTrial'] == true,
              vipExpiresAt: accountProfile['vipExpiresAt'] as String?,
              vipLifetime: accountProfile['vipLifetime'] == true,
              onOpen: showPaymentOptions),
        ],
        const SizedBox(height: 16),
        box(ListTile(
            key: const ValueKey('profile-settings-entry'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined, color: teal),
            title: Text(tr('设置')),
            subtitle: Text(tr('主题与外观、学习设置、服务与规则')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsPage())))),
        heading('导入题库'),
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('上传一次即可导入本机练习，并同步到仅作者可见的私密审核箱。')),
          const SizedBox(height: 8),
          Text(tr('不会自动进入公开题库。请仅上传你有权分享的资料；不要上传含个人隐私、受限或来源不明的内容。'),
              style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          const QuestionBankImportHelp(),
          const TextBankSourceRequirements(),
          const SizedBox(height: 14),
          Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                    onPressed: importingBank ? null : pickQuestionBank,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(tr(importingBank ? '正在处理…' : '上传 JSON 题库'))),
                _UploadStoneRewardHint(used: dailyUploadRewardCount),
              ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: importingBank ? null : importFromWordOrText,
              icon: const Icon(Icons.description_outlined),
              label: Text(tr('我只有 Word / 纯文字'))),
          if (importStage != QuestionBankImportStage.idle)
            QuestionBankImportProgress(
                stage: importStage, detail: importProgressDetail),
        ])),
        if (store.importedQuestions.isNotEmpty)
          ImportedBankPractice(onStart: widget.onStart),
        if (isSubmissionAdmin) ...[
          heading('作者管理'),
          box(Column(children: [
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.people_outline),
                title: Text(
                    '用户目录${authorUserCount == null ? '' : ' · $authorUserCount 人'}'),
                subtitle: Text('查看昵称、院校与邮箱'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openAuthorRecords(AuthorRecordKind.users)),
            const Divider(),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(
                    '题库投稿箱${submissionCount == null ? '' : ' · $submissionCount 份'}'),
                subtitle: Text('查看用户提交的题库'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openAuthorRecords(AuthorRecordKind.submissions)),
            const Divider(),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.forum_outlined),
                title: Text(tr('评论管理')),
                subtitle: Text(tr('查看发布者、题目与评论')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AuthorCommentsPage()))),
          ]))
        ],
        const SizedBox(height: 20),
        const Text(
            '齿间 DentStudy · ${BuildInfo.version}\n更新于 ${BuildInfo.builtAt}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
      ];

  Future<void> editProfile() async {
    await showProfileEditor(context, initialProfile: accountProfile);
    if (mounted) await refreshAccountData();
  }
}

/// Membership details are available to every signed-in learner.  Checkout is
/// intentionally unavailable while the question bank is being prepared.
class _AuthorPaymentEntryCard extends StatelessWidget {
  final bool isVip;
  final bool vipTrial;
  final String? vipExpiresAt;
  final bool vipLifetime;
  final VoidCallback onOpen;
  const _AuthorPaymentEntryCard(
      {required this.isVip,
      required this.vipTrial,
      required this.vipExpiresAt,
      required this.vipLifetime,
      required this.onOpen});

  String get _validity {
    if (vipLifetime) return tr('终身有效');
    final moment = DateTime.tryParse(vipExpiresAt ?? '')?.toUtc();
    if (moment == null) return tr('会员有效期正在确认');
    final beijing = moment.add(const Duration(hours: 8));
    return tr(
        '会员有效至 ${beijing.year}年${beijing.month}月${beijing.day}日 ${beijing.hour.toString().padLeft(2, '0')}:${beijing.minute.toString().padLeft(2, '0')}（北京时间）');
  }

  @override
  Widget build(BuildContext context) =>
      box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const VipEmblem(size: 30),
          const SizedBox(width: 9),
          Expanded(
              child: Text(
                  tr(vipTrial
                      ? '新用户 7 天 VIP 体验'
                      : (isVip ? '你已经是 VIP 会员' : '会员支付')),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800))),
          Text(tr('会员详情'),
              style: TextStyle(fontSize: 11.5, color: Colors.blueGrey))
        ]),
        const SizedBox(height: 10),
        if (isVip) ...[
          Text(_validity, style: const TextStyle(color: Colors.blueGrey)),
          const SizedBox(height: 10),
        ],
        if (!isVip) ...[
          Text(tr('题库还在搭建，请勿充值。'),
              style: TextStyle(color: Colors.deepOrange, fontSize: 12.5)),
          const SizedBox(height: 10),
        ],
        SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
                onPressed: onOpen,
                icon: const VipEmblem(size: 23),
                label: Text(tr(isVip ? '查看续费方案' : '了解会员详情'))))
      ]));
}

class _ProfileMessageButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ProfileMessageButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (_, __) => IconButton(
          tooltip: tr('消息'),
          onPressed: onPressed,
          icon: UnreadDot(
              visible: store.socialUnreadCount > 0,
              dotKey: const ValueKey('profile-message-unread-dot'),
              child: const Icon(Icons.forum_outlined))));
}

/// Keeps the question-bank reward rule beside the action that earns it.  The
/// count comes from the signed-in user's stone ledger and never exposes a
/// submission or reward record belonging to somebody else.
class _UploadStoneRewardHint extends StatelessWidget {
  final int? used;

  const _UploadStoneRewardHint({required this.used});

  @override
  Widget build(BuildContext context) {
    final count = used == null ? '…' : '$used';
    return Semantics(
        label: '每日上传题库成功获得一颗羟基磷灰石，今日已获得 $count 颗，上限 3 颗',
        child: Container(
            key: const ValueKey('question-bank-upload-stone-reward'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
                color: const Color(0xfffff6d9),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xffd9a42a).withAlpha(110))),
            child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 4,
                children: [
                  Text('每日上传成功',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const StoneCoinIcon(size: 18),
                  const SizedBox(width: 2),
                  Text('+1',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  Text(' · 上限 ', style: TextStyle(fontSize: 12)),
                  Text('$count/3',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                ])));
  }
}

/// A compact balance affordance in the profile card.  It deliberately uses
/// the supplied tooth-coin artwork rather than a generic material icon, so
/// the same currency is recognizable before the learner opens the wallet.
class _StoneWalletEntry extends StatelessWidget {
  final int? balance;
  final VoidCallback onPressed;

  const _StoneWalletEntry({required this.balance, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final label = balance == null ? '羟基磷灰石' : '羟基磷灰石余额 $balance 颗';
    return Semantics(
        button: true,
        label: label,
        child: Tooltip(
            message: label,
            child: Material(
                color: Colors.transparent,
                child: InkWell(
                    key: const ValueKey('stone-wallet-entry'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: onPressed,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 7),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 30,
                              height: 30,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                  color: const Color(0xfffff4c9),
                                  borderRadius: BorderRadius.circular(15)),
                              child: const StoneIcon(size: 26)),
                          const SizedBox(width: 5),
                          Text(balance?.toString() ?? '…',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800)),
                        ]))))));
  }
}

Future<void> showAccountDialog(BuildContext context,
    {Future<void> Function()? onSuccess}) async {
  bool remember = store.prefs.getBool('rememberPassword') ?? true;
  final email = TextEditingController(
          text: store.needsSignIn
              ? store.email
              : (remember ? store.prefs.getString('rememberedEmail') ?? '' : '')),
      password = TextEditingController(),
      confirmPassword = TextEditingController();
  bool register = false,
      busy = false,
      authenticated = false,
      justRegistered = false;
  String? error;
  await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
                  title: Text(tr(register ? '创建学习账号' : '登录学习账号')),
                  content: AutofillGroup(
                      onDisposeAction: AutofillContextAction.cancel,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        Align(
                            alignment: Alignment.centerLeft,
                            child: LanguageSelector(
                                compact: true,
                                value: store.languageCode,
                                onChanged: busy
                                    ? null
                                    : (value) async {
                                        await store.setLanguage(value);
                                        if (c.mounted) set(() {});
                                      })),
                        const SizedBox(height: 12),
                        TextField(
                            controller: email,
                            autofillHints: remember
                                ? const [
                                    AutofillHints.username,
                                    AutofillHints.email
                                  ]
                                : null,
                            autocorrect: false,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(labelText: tr('邮箱'))),
                        SizedBox(height: 10),
                        TextField(
                            controller: password,
                            autofillHints: remember
                                ? [
                                    register
                                        ? AutofillHints.newPassword
                                        : AutofillHints.password
                                  ]
                                : null,
                            enableSuggestions: false,
                            autocorrect: false,
                            obscureText: true,
                            decoration:
                                InputDecoration(labelText: tr('密码（至少10位）'))),
                        if (register) ...[
                          SizedBox(height: 10),
                          TextField(
                              controller: confirmPassword,
                              autofillHints: remember
                                  ? const [AutofillHints.newPassword]
                                  : null,
                              obscureText: true,
                              decoration:
                                  InputDecoration(labelText: tr('确认密码'))),
                          SizedBox(height: 10),
                          Text(tr('务必记住密码，目前忘记密码无法找回！！！'),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.deepOrange))
                        ],
                        SizedBox(height: 10),
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(tr('记住登录状态')),
                            subtitle: Text(tr('密码仅交由浏览器或系统密码管理器保存'),
                                style: TextStyle(fontSize: 12)),
                            value: remember,
                            onChanged: busy
                                ? null
                                : (value) =>
                                    set(() => remember = value ?? false)),
                        Text(tr('账号学习进度会自动同步；访客记录保留在本机。'),
                            style: TextStyle(fontSize: 12)),
                        if (error != null)
                          Text(tr(error!), style: TextStyle(color: Colors.red)),
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => set(() => register = !register),
                            child: Text(tr(register ? '已有账号？登录' : '没有账号？注册')))
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: busy ? null : () => Navigator.pop(c),
                        child: Text(tr('取消'))),
                    FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (register &&
                                    password.text != confirmPassword.text) {
                                  set(() => error = '两次输入的密码不一致');
                                  return;
                                }
                                set(() => busy = true);
                                try {
                                  await store.login(
                                      email.text, password.text, register);
                                  TextInput.finishAutofillContext(
                                      shouldSave: remember);
                                  await store.prefs
                                      .setBool('rememberPassword', remember);
                                  if (remember) {
                                    await store.prefs.setString(
                                        'rememberedEmail', email.text.trim());
                                  } else {
                                    await store.prefs.remove('rememberedEmail');
                                  }
                                  authenticated = true;
                                  justRegistered = register;
                                  if (c.mounted) Navigator.pop(c);
                                } catch (e) {
                                  if (c.mounted)
                                    set(() {
                                      error = e.toString();
                                      busy = false;
                                    });
                                }
                              },
                        child: Text(tr(busy ? '连接中…' : '继续')))
                  ])));
  Future.delayed(const Duration(milliseconds: 400), () {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
  });
  if (!authenticated || !context.mounted) return;
  if (justRegistered) {
    try {
      final profile = await store.profile();
      if (context.mounted)
        await showProfileEditor(context,
            initialProfile: profile, onboarding: true);
    } catch (_) {
      if (context.mounted) message(context, '个人资料暂时无法加载，可在“我的”中稍后完善');
    }
  }
  if (context.mounted) await onSuccess?.call();
}
