import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../library/question_preview.dart';
import '../profile/user_avatar.dart';
import 'user_profile_sheet.dart';

/// A private, account-only space for friend requests, notifications and chat.
///
/// Profile records supplied by the social endpoints intentionally contain no
/// email address.  The server also checks friendship before it returns or
/// accepts conversation messages; this screen only presents that result.
class SocialInboxPage extends StatefulWidget {
  final int initialTab;
  final ValueChanged<int>? onUnreadChanged;
  const SocialInboxPage({super.key, this.initialTab = 0, this.onUnreadChanged});

  @override
  State<SocialInboxPage> createState() => _SocialInboxPageState();
}

class _SocialInboxPageState extends State<SocialInboxPage>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> incomingRequests = [];
  List<Map<String, dynamic>> outgoingRequests = [];
  List<Map<String, dynamic>> notifications = [];
  bool loadingConversations = true;
  bool loadingFriends = true;
  bool loadingNotifications = true;
  bool respondingToRequest = false;
  String? conversationError;
  String? friendError;
  String? notificationError;
  int unreadCount = 0;
  bool markingAllRead = false;
  Map<String, dynamic>? selectedConversation;

  /// Chat red dots belong to the chat entry and each conversation, rather
  /// than the general notification tab.  The backend returns an exact unread
  /// count per accepted conversation, which is also resilient to notification
  /// pagination.
  int get chatUnreadCount => conversations.fold<int>(0,
      (total, item) => total + ((item['unreadCount'] as num?)?.toInt() ?? 0));

  @override
  void initState() {
    super.initState();
    tabs = TabController(
        length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
    tabs.addListener(_onTabChanged);
    _loadConversations();
    _loadFriends();
    _loadNotifications(markRead: tabs.index == 2);
  }

  @override
  void dispose() {
    tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (tabs.indexIsChanging) return;
    if (mounted) setState(() {});
    if (tabs.index == 0) _loadConversations();
    if (tabs.index == 1) _loadFriends();
    if (tabs.index == 2) _loadNotifications(markRead: true);
  }

  List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : <Map<String, dynamic>>[];

  /// Updates the sidebar without replacing an already-open desktop thread.
  ///
  /// A thread marks itself read as it opens. That mark refreshes the
  /// conversation list, so showing a full-page progress indicator here would
  /// temporarily dispose the inline thread and immediately create it again.
  Future<void> _loadConversations({bool showBlockingLoading = true}) async {
    if (store.token.isEmpty) return;
    final showLoading = showBlockingLoading && conversations.isEmpty;
    if (mounted && showLoading) {
      setState(() {
        loadingConversations = true;
        conversationError = null;
      });
    } else if (mounted && conversationError != null) {
      setState(() => conversationError = null);
    }
    try {
      final result = await store.conversations();
      if (!mounted) return;
      final fetched = _maps(result['conversations']);
      final selectedId = _profileId(selectedConversation?['friend']);
      setState(() {
        conversations = fetched;
        if (selectedId.isNotEmpty) {
          selectedConversation = fetched
              .where((item) => _profileId(item['friend']) == selectedId)
              .cast<Map<String, dynamic>>()
              .firstOrNull;
        }
      });
      widget.onUnreadChanged?.call(store.socialUnreadCount);
    } catch (_) {
      // Keep a working thread visible if a background sidebar sync fails.
      if (mounted && conversations.isEmpty) {
        setState(() => conversationError = '聊天暂时无法加载');
      }
    } finally {
      if (mounted && showLoading) {
        setState(() => loadingConversations = false);
      }
    }
  }

  Future<void> _loadFriends() async {
    if (store.token.isEmpty) return;
    if (mounted) {
      setState(() {
        loadingFriends = true;
        friendError = null;
      });
    }
    try {
      final result = await store.friends();
      if (!mounted) return;
      setState(() {
        friends = _maps(result['friends']);
        incomingRequests = _maps(result['incoming']);
        outgoingRequests = _maps(result['outgoing']);
      });
    } catch (_) {
      if (mounted) setState(() => friendError = '好友列表暂时无法加载');
    } finally {
      if (mounted) setState(() => loadingFriends = false);
    }
  }

  Future<void> _loadNotifications({bool markRead = false}) async {
    if (store.token.isEmpty) return;
    if (mounted) {
      setState(() {
        loadingNotifications = true;
        notificationError = null;
      });
    }
    try {
      final result = await store.notifications();
      if (!mounted) return;
      // A direct-message notification is only a transport wake-up.  Showing
      // it again in this tab duplicates a chat row and makes its red dot look
      // like a general notification.  The chat tab/list owns those unread
      // indicators instead.
      final items = _maps(result['items'])
          .where((item) => item['type'] != 'direct_message')
          .toList();
      final visibleUnread =
          items.where((item) => item['readAt'] == null).length;
      // The server counts all notifications, not just the latest page.
      final legacy = _maps(result['items'])
          .any((item) => item['type'] == 'direct_message');
      var nextUnread = legacy
          ? visibleUnread
          : (result['unreadCount'] as num?)?.toInt() ?? visibleUnread;
      if (markRead && visibleUnread > 0) {
        final ids = items
            .where((item) => item['readAt'] == null)
            .map((item) => item['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        if (ids.isNotEmpty) {
          final acknowledgement = await store.markNotificationsRead(ids: ids);
          nextUnread = legacy
              ? 0
              : (acknowledgement['unreadCount'] as num?)?.toInt() ??
                  (nextUnread - visibleUnread).clamp(0, nextUnread);
        }
        for (final item in items) {
          item['readAt'] ??= DateTime.now().toIso8601String();
        }
      }
      if (!mounted) return;
      setState(() {
        notifications = items;
        unreadCount = nextUnread;
      });
      widget.onUnreadChanged?.call(store.socialUnreadCount);
    } catch (_) {
      if (mounted) setState(() => notificationError = '消息暂时无法加载');
    } finally {
      if (mounted) setState(() => loadingNotifications = false);
    }
  }

  Future<void> _markAllNotificationsRead() async {
    if (markingAllRead) return;
    setState(() => markingAllRead = true);
    try {
      // Explicit action: do not silently acknowledge older, unseen pages.
      final result = await store.markNotificationsRead();
      if (!mounted) return;
      setState(() {
        unreadCount = (result['unreadCount'] as num?)?.toInt() ?? 0;
        for (final item in notifications) {
          item['readAt'] ??= DateTime.now().toIso8601String();
        }
      });
      widget.onUnreadChanged?.call(store.socialUnreadCount);
    } catch (_) {
      if (mounted) message(context, '标记已读失败，请重试');
    } finally {
      if (mounted) setState(() => markingAllRead = false);
    }
  }

  Future<void> _respondToRequest(
      Map<String, dynamic> request, bool accept) async {
    if (respondingToRequest) return;
    final id = request['id'] as String? ?? '';
    if (id.isEmpty) return;
    setState(() => respondingToRequest = true);
    try {
      await store.respondToFriendRequest(id, accept);
      if (!mounted) return;
      message(context, accept ? '已添加好友' : '已忽略申请');
      await Future.wait(
          [_loadFriends(), _loadConversations(), _loadNotifications()]);
    } catch (error) {
      if (mounted) message(context, _readableError(error));
    } finally {
      if (mounted) setState(() => respondingToRequest = false);
    }
  }

  Future<void> _showAddFriend() async {
    if (store.token.isEmpty) {
      message(context, '登录后即可添加好友');
      return;
    }
    final field = TextEditingController();
    List<Map<String, dynamic>> results = [];
    String? error;
    bool searching = false;
    final pending = <String>{};
    Future<void> search(
        BuildContext dialogContext, StateSetter setDialogState) async {
      final query = field.text.trim();
      if (query.runes.length < 2 || query.runes.length > 40) {
        setDialogState(() => error = '昵称搜索需为 2–40 个字');
        return;
      }
      setDialogState(() {
        searching = true;
        error = null;
      });
      try {
        final result = await store.searchPeople(query);
        if (!dialogContext.mounted) return;
        setDialogState(() => results = _maps(result['users']));
      } catch (exception) {
        if (!dialogContext.mounted) return;
        setDialogState(() => error = _readableError(exception));
      } finally {
        if (dialogContext.mounted) {
          setDialogState(() => searching = false);
        }
      }
    }

    await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
                    title: Text(tr('添加好友')),
                    content: SizedBox(
                        width: 460,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: field,
                                  autofocus: true,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) =>
                                      search(dialogContext, setDialogState),
                                  decoration: const InputDecoration(
                                      labelText: '昵称',
                                      prefixIcon: Icon(Icons.search))),
                              const SizedBox(height: 8),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                      onPressed: searching
                                          ? null
                                          : () => search(
                                              dialogContext, setDialogState),
                                      icon: const Icon(Icons.search, size: 18),
                                      label: Text(tr('搜索')))),
                              const SizedBox(height: 12),
                              if (searching)
                                const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator())
                              else if (error != null)
                                Text(error!,
                                    style:
                                        const TextStyle(color: Colors.blueGrey))
                              else if (results.isEmpty)
                                Text(tr('输入昵称后按搜索键'),
                                    style: TextStyle(color: Colors.blueGrey))
                              else
                                ...results.map((profile) {
                                  final id = _profileId(profile);
                                  return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: _socialProfileAvatar(
                                          dialogContext, profile),
                                      title: Text(_profileName(profile)),
                                      subtitle: _university(profile).isEmpty
                                          ? null
                                          : Text(_university(profile)),
                                      trailing: FilledButton.tonal(
                                          onPressed: id.isEmpty ||
                                                  pending.contains(id)
                                              ? null
                                              : () async {
                                                  setDialogState(
                                                      () => pending.add(id));
                                                  try {
                                                    await store
                                                        .sendFriendRequest(id);
                                                    if (!dialogContext.mounted)
                                                      return;
                                                    setDialogState(() {
                                                      pending.remove(id);
                                                      results.removeWhere(
                                                          (item) =>
                                                              _profileId(
                                                                  item) ==
                                                              id);
                                                    });
                                                    message(context, '好友申请已发送');
                                                    await _loadFriends();
                                                  } catch (exception) {
                                                    if (!dialogContext.mounted)
                                                      return;
                                                    setDialogState(() {
                                                      pending.remove(id);
                                                      error = _readableError(
                                                          exception);
                                                    });
                                                  }
                                                },
                                          child: Text(pending.contains(id)
                                              ? '发送中…'
                                              : '添加')));
                                })
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(tr('关闭')))
                    ])));
    field.dispose();
  }

  Future<void> _openConversation(Map<String, dynamic> conversation) async {
    final friend = _profile(conversation['friend']);
    final friendId = _profileId(friend);
    if (friendId.isEmpty) return;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    if (wide) {
      setState(() => selectedConversation = conversation);
      return;
    }
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => ChatThreadPage(
                friend: friend,
                onMessageSent: _loadConversations,
                onThreadOpened: _refreshConversationReadState)));
    if (mounted) await _loadConversations();
  }

  Future<void> _refreshConversationReadState() async {
    await Future.wait([
      _loadConversations(showBlockingLoading: false),
      _loadNotifications(),
    ]);
  }

  Future<void> _refreshCurrent() async {
    switch (tabs.index) {
      case 0:
        await _loadConversations();
      case 1:
        await _loadFriends();
      case 2:
        await _loadNotifications(markRead: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(tr('消息')),
          actions: [
            if (tabs.index == 1)
              IconButton(
                  tooltip: tr('添加好友'),
                  onPressed: _showAddFriend,
                  icon: const Icon(Icons.person_add_alt_1_outlined)),
            if (tabs.index == 2 && unreadCount > 0)
              TextButton(
                  onPressed: markingAllRead ? null : _markAllNotificationsRead,
                  child: Text(tr('全部已读'))),
            IconButton(
                tooltip: tr('刷新'),
                onPressed: _refreshCurrent,
                icon: const Icon(Icons.refresh))
          ],
          bottom: TabBar(controller: tabs, tabs: [
            Tab(
                icon: _CountBadge(
                    count: chatUnreadCount,
                    child: const Icon(Icons.forum_outlined)),
                text: tr('聊天')),
            Tab(
                icon: _CountBadge(
                    count: incomingRequests.length,
                    child: const Icon(Icons.people_outline)),
                text: tr('好友')),
            Tab(
                icon: _CountBadge(
                    count: unreadCount,
                    child: const Icon(Icons.notifications_none)),
                text: tr('通知'))
          ])),
      body: SafeArea(
          top: false,
          child: TabBarView(controller: tabs, children: [
            _messagesTab(),
            _friendsTab(),
            _notificationsTab(),
          ])));

  Widget _messagesTab() {
    if (loadingConversations)
      return const Center(child: CircularProgressIndicator());
    if (conversationError != null)
      return _ErrorState(
          error: conversationError!, onRetry: _loadConversations);
    if (conversations.isEmpty) {
      return _EmptyState(
          icon: Icons.forum_outlined,
          title: tr('还没有聊天'),
          detail: tr('添加好友后，就可以在这里开始对话。'),
          action: _showAddFriend);
    }
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final list = _ConversationList(
        conversations: conversations,
        selectedId: _profileId(selectedConversation?['friend']),
        onOpen: _openConversation);
    if (!wide) return list;
    final friend = _profile(selectedConversation?['friend']);
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Row(children: [
              SizedBox(width: 330, child: list),
              const VerticalDivider(width: 1),
              Expanded(
                  child: friend.isEmpty
                      ? _EmptyState(
                          icon: Icons.chat_bubble_outline,
                          title: tr('选择一个对话'),
                          detail: tr('从左侧选择好友开始聊天。'))
                      : _ChatThread(
                          key: ValueKey(_profileId(friend)),
                          friend: friend,
                          onMessageSent: _loadConversations,
                          onThreadOpened: _refreshConversationReadState))
            ])));
  }

  Widget _friendsTab() => _ScrollPane(
      onRefresh: _loadFriends,
      child: loadingFriends
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()))
          : friendError != null
              ? _ErrorState(error: friendError!, onRetry: _loadFriends)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (incomingRequests.isNotEmpty) ...[
                    const _SectionTitle('好友申请'),
                    ...incomingRequests.map((request) => _FriendRequestTile(
                        request: request,
                        busy: respondingToRequest,
                        onRespond: _respondToRequest)),
                    const SizedBox(height: 20)
                  ],
                  if (_visibleOutgoingRequests.isNotEmpty) ...[
                    const _SectionTitle('已发送'),
                    ..._visibleOutgoingRequests.map((request) =>
                        _FriendRequestTile(
                            request: request,
                            outgoing: true,
                            busy: false,
                            onRespond: _respondToRequest)),
                    const SizedBox(height: 20)
                  ],
                  Row(children: [
                    const Expanded(child: _SectionTitle('我的好友')),
                    TextButton.icon(
                        onPressed: _showAddFriend,
                        icon: const Icon(Icons.person_add_alt_1_outlined,
                            size: 18),
                        label: Text('添加'))
                  ]),
                  if (friends.isEmpty)
                    _EmptyState(
                        icon: Icons.people_outline,
                        title: tr('还没有好友'),
                        detail: '搜索同学的昵称，发送好友申请。',
                        action: _showAddFriend)
                  else
                    ...friends.map((friend) => _FriendTile(
                        profile: _profile(friend),
                        onChat: () => _openFriendChat(_profile(friend))))
                ]));

  Future<void> _openFriendChat(Map<String, dynamic> friend) async {
    final id = _profileId(friend);
    if (id.isEmpty) return;
    final existing = conversations
        .where((item) => _profileId(item['friend']) == id)
        .cast<Map<String, dynamic>>()
        .firstOrNull;
    if (existing != null) {
      await _openConversation(existing);
      return;
    }
    await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => ChatThreadPage(
                friend: friend,
                onMessageSent: _loadConversations,
                onThreadOpened: _refreshConversationReadState)));
    if (mounted) await _loadConversations();
  }

  Widget _notificationsTab() => _ScrollPane(
      onRefresh: () => _loadNotifications(markRead: true),
      child: loadingNotifications
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()))
          : notificationError != null
              ? _ErrorState(
                  error: notificationError!, onRetry: _loadNotifications)
              : notifications.isEmpty
                  ? _EmptyState(
                      icon: Icons.notifications_none,
                      title: tr('还没有消息'),
                      detail: tr('收到点赞、评论或好友申请时会显示在这里。聊天未读会显示在“聊天”里。'))
                  : Column(
                      children: notifications
                          .map((item) => _NotificationTile(notification: item))
                          .toList()));

  /// Defensive handling for a briefly stale friends response: once a peer is
  /// accepted, its old outgoing request must disappear rather than showing a
  /// contradictory "已发送" card above the new friend row.
  List<Map<String, dynamic>> get _visibleOutgoingRequests {
    final acceptedIds =
        friends.map(_profileId).where((id) => id.isNotEmpty).toSet();
    return outgoingRequests.where((request) {
      final peerId = _profileId(request['profile']);
      return peerId.isEmpty || !acceptedIds.contains(peerId);
    }).toList();
  }
}

class ChatThreadPage extends StatelessWidget {
  final Map<String, dynamic> friend;
  final Future<void> Function()? onMessageSent;
  final Future<void> Function()? onThreadOpened;
  const ChatThreadPage(
      {super.key,
      required this.friend,
      this.onMessageSent,
      this.onThreadOpened});

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(_profileName(friend))),
      body: SafeArea(
          top: false,
          child: _ChatThread(
              friend: friend,
              onMessageSent: onMessageSent,
              onThreadOpened: onThreadOpened)));
}

class _ConversationList extends StatelessWidget {
  final List<Map<String, dynamic>> conversations;
  final String selectedId;
  final ValueChanged<Map<String, dynamic>> onOpen;
  const _ConversationList(
      {required this.conversations,
      required this.selectedId,
      required this.onOpen});

  @override
  Widget build(BuildContext context) => ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      itemCount: conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, index) {
        final conversation = conversations[index];
        final friend = _profile(conversation['friend']);
        final id = _profileId(friend);
        final preview = _messagePreview(conversation['lastMessage']);
        final unread = (conversation['unreadCount'] as num?)?.toInt() ?? 0;
        return Material(
            color: id == selectedId ? teal.withAlpha(16) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                onTap: () => onOpen(conversation),
                leading: _socialProfileAvatar(context, friend),
                title: Text(_profileName(friend),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(preview.isEmpty ? tr('开始聊天吧') : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.blueGrey)),
                trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (conversation['updatedAt'] is String)
                        Text(_shortTime(conversation['updatedAt'] as String),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.blueGrey)),
                      const SizedBox(height: 3),
                      if (unread > 0) _NumberPill(count: unread)
                    ])));
      });
}

class _ChatThread extends StatefulWidget {
  final Map<String, dynamic> friend;
  final Future<void> Function()? onMessageSent;
  final Future<void> Function()? onThreadOpened;
  const _ChatThread(
      {super.key,
      required this.friend,
      this.onMessageSent,
      this.onThreadOpened});

  @override
  State<_ChatThread> createState() => _ChatThreadState();
}

class _ChatThreadState extends State<_ChatThread> {
  final composer = TextEditingController();
  final scrollController = ScrollController();
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  bool sending = false;
  String? error;
  int loadGeneration = 0;

  String get friendId => _profileId(widget.friend);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ChatThread oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_profileId(oldWidget.friend) != friendId) {
      messages = [];
      error = null;
      _load();
    }
  }

  @override
  void dispose() {
    composer.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (friendId.isEmpty) return;
    final generation = ++loadGeneration;
    // A manual refresh should preserve messages already on screen. Besides
    // being calmer visually, this keeps the desktop thread mounted while its
    // parent refreshes the conversation sidebar.
    final showLoading = messages.isEmpty;
    if (mounted && showLoading) {
      setState(() {
        loading = true;
        error = null;
      });
    } else if (mounted && error != null) {
      setState(() => error = null);
    }
    try {
      final result = await store.conversationMessages(friendId);
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        messages = result['messages'] is List
            ? (result['messages'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
            : [];
      });
      if (showLoading) _scrollToEnd();
      await widget.onThreadOpened?.call();
    } catch (_) {
      if (mounted && generation == loadGeneration && messages.isEmpty) {
        setState(() => error = '对话暂时无法加载');
      }
    } finally {
      if (mounted && generation == loadGeneration && showLoading) {
        setState(() => loading = false);
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final draft = composer.text;
    final text = composer.text.trim();
    if (text.isEmpty || sending) return;
    if (text.runes.length > 1000) {
      message(context, '消息长度不能超过 1000 个字');
      return;
    }
    setState(() => sending = true);
    try {
      final result = await store.sendConversationMessage(friendId, text);
      final added = result['message'];
      if (!mounted) return;
      if (composer.text == draft) composer.clear();
      if (added is Map) {
        setState(() {
          // A stranger card opens an empty composer before its first intro
          // exists, so its initial GET may be denied. A successful first send
          // establishes the thread and must replace that provisional error.
          error = null;
          messages.add(Map<String, dynamic>.from(added));
        });
        _scrollToEnd();
      } else {
        await _load();
      }
      await widget.onMessageSent?.call();
    } catch (exception) {
      // Keep an unsuccessful send in the local thread instead of making the
      // learner wonder whether it vanished. This is especially useful after a
      // Friend deletion/block rejects delivery on the server. Keep an error
      // marker beside the failed bubble so the sender knows it never arrived.
      if (mounted) {
        if (composer.text == draft) composer.clear();
        setState(() {
          // The optimistic, visibly failed bubble is the useful state here;
          // do not leave an earlier initial-load error on top of it.
          error = null;
          messages.add({
            'id': 'failed-${DateTime.now().microsecondsSinceEpoch}',
            'body': text,
            'kind': 'chat',
            'createdAt': DateTime.now().toIso8601String(),
            'readAt': null,
            'mine': true,
            'failed': true,
          });
        });
        _scrollToEnd();
        message(context, _readableError(exception));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        _ChatHeader(friend: widget.friend, onRefresh: loading ? null : _load),
        const Divider(height: 1),
        Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? _ErrorState(error: error!, onRetry: _load)
                    : messages.isEmpty
                        ? _EmptyState(
                            icon: Icons.chat_bubble_outline,
                            title: tr('开始聊天吧'),
                            detail: tr('发送一条消息，和好友交流学习心得。'))
                        : ListView.builder(
                            controller: scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                            itemCount: messages.length,
                            itemBuilder: (_, index) => _MessageBubble(
                                message: messages[index],
                                friend: widget.friend))),
        const Divider(height: 1),
        SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child:
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      child: TextField(
                          controller: composer,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                              counterText: '', hintText: tr('输入消息…')))),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      tooltip: tr('发送'),
                      onPressed: sending ? null : _send,
                      icon: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_outlined))
                ]))),
      ]);
}

class _ChatHeader extends StatelessWidget {
  final Map<String, dynamic> friend;
  final VoidCallback? onRefresh;
  const _ChatHeader({required this.friend, this.onRefresh});

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
      child: Row(children: [
        _socialProfileAvatar(context, friend),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_profileName(friend),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (_university(friend).isNotEmpty)
            Text(_university(friend),
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey))
        ])),
        IconButton(
            tooltip: tr('刷新对话'),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh))
      ]));
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final Map<String, dynamic> friend;
  const _MessageBubble({required this.message, required this.friend});

  void _openSharedQuestion(BuildContext context) {
    final questionId = message['questionId'] as String? ?? '';
    final questions = store.resolveQuestions([questionId]);
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('本机暂未收录这道题，请先更新离线题库'))));
      return;
    }
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => QuestionPreviewPage(
                questions: questions, initialQuestionId: questionId)));
  }

  Widget _body(BuildContext context, bool mine) {
    final kind = message['kind'] as String? ?? 'chat';
    if (kind != 'question') {
      return SelectableText(message['body'] as String? ?? '',
          style: TextStyle(color: mine ? Colors.white : ink));
    }
    final question = _profile(message['question']);
    final subject = question['subject'] as String? ?? '';
    final chapter = question['chapter'] as String? ?? '';
    final stem = question['stem'] as String? ?? '题目暂不可用';
    final foreground = mine ? Colors.white : ink;
    return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 190),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.quiz_outlined, size: 18, color: foreground),
            const SizedBox(width: 6),
            Text(tr('分享了一道题'),
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: foreground))
          ]),
          if ([subject, chapter]
              .where((item) => item.trim().isNotEmpty)
              .isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
                [subject, chapter]
                    .where((item) => item.trim().isNotEmpty)
                    .join(' · '),
                style:
                    TextStyle(fontSize: 12, color: foreground.withAlpha(210)))
          ],
          const SizedBox(height: 5),
          Text(stem,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, height: 1.35)),
          const SizedBox(height: 3),
          TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: mine ? Colors.white : teal,
                  padding: const EdgeInsets.symmetric(horizontal: 2)),
              onPressed: () => _openSharedQuestion(context),
              icon: const Icon(Icons.open_in_new, size: 15),
              label: Text(tr('查看原题')))
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final mine = message['mine'] == true;
    final failed = message['failed'] == true;
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
            mainAxisAlignment:
                mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!mine) ...[
                _socialProfileAvatar(context, friend, radius: 17),
                const SizedBox(width: 8)
              ],
              Flexible(
                  child: Column(
                      crossAxisAlignment: mine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                    Container(
                        constraints: const BoxConstraints(maxWidth: 460),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 10),
                        decoration: BoxDecoration(
                            color: mine ? teal : const Color(0xFFF1F5F4),
                            borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(mine ? 16 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 16))),
                        child: _body(context, mine)),
                    const SizedBox(height: 3),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_shortTime(message['createdAt'] as String? ?? ''),
                          style: const TextStyle(
                              fontSize: 10.5, color: Colors.blueGrey)),
                      if (failed) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.error_outline,
                            size: 14, color: Colors.deepOrange),
                        const SizedBox(width: 2),
                        Text(tr('未送达'),
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.deepOrange))
                      ]
                    ])
                  ]))
            ]));
  }
}

class _FriendRequestTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool outgoing;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>, bool) onRespond;
  const _FriendRequestTile(
      {required this.request,
      required this.busy,
      required this.onRespond,
      this.outgoing = false});

  @override
  Widget build(BuildContext context) {
    final profile = _profile(request['profile']);
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: box(ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _socialProfileAvatar(context, profile),
            title: Text(_profileName(profile)),
            subtitle: Text(outgoing
                ? '等待对方通过'
                : (_university(profile).isEmpty
                    ? '想和你成为好友'
                    : _university(profile))),
            trailing: outgoing
                ? Text(tr('已发送'), style: TextStyle(color: Colors.blueGrey))
                : Wrap(spacing: 4, children: [
                    TextButton(
                        onPressed:
                            busy ? null : () => onRespond(request, false),
                        child: Text(tr('忽略'))),
                    FilledButton.tonal(
                        onPressed: busy ? null : () => onRespond(request, true),
                        child: Text(tr(busy ? '处理中…' : '通过')))
                  ]))));
  }
}

class _FriendTile extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onChat;
  const _FriendTile({required this.profile, required this.onChat});

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: box(ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _socialProfileAvatar(context, profile),
          title: Text(_profileName(profile)),
          subtitle:
              _university(profile).isEmpty ? null : Text(_university(profile)),
          trailing: OutlinedButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_outline, size: 17),
              label: Text(tr('聊天'))))));
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final actor = _profile(notification['actor']);
    final unread = notification['readAt'] == null;
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: box(ListTile(
            contentPadding: EdgeInsets.zero,
            leading: actor.isEmpty
                ? CircleAvatar(
                    backgroundColor: teal.withAlpha(18),
                    child: Icon(_notificationIcon(notification['type']),
                        color: teal))
                : _socialProfileAvatar(context, actor),
            title: Text(_notificationTitle(notification),
                style: TextStyle(
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w400)),
            subtitle:
                Text(_shortTime(notification['createdAt'] as String? ?? '')),
            trailing: unread
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Colors.redAccent, shape: BoxShape.circle))
                : null)));
  }
}

class _ScrollPane extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const _ScrollPane({required this.onRefresh, required this.child});

  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [child]))));
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)));
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? action;
  const _EmptyState(
      {required this.icon,
      required this.title,
      required this.detail,
      this.action});

  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 42, color: teal.withAlpha(180)),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.blueGrey, height: 1.5)),
            if (action != null) ...[
              const SizedBox(height: 15),
              FilledButton.icon(
                  onPressed: action,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(tr('添加好友')))
            ]
          ])));
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined,
                size: 38, color: Colors.blueGrey),
            const SizedBox(height: 10),
            Text(error, style: const TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(tr('重试')))
          ])));
}

class _CountBadge extends StatelessWidget {
  final int count;
  final Widget child;
  const _CountBadge({required this.count, required this.child});
  @override
  Widget build(BuildContext context) =>
      Stack(clipBehavior: Clip.none, children: [
        child,
        if (count > 0)
          Positioned(
              right: -7,
              top: -6,
              child: _NumberPill(count: count, compact: true))
      ]);
}

class _NumberPill extends StatelessWidget {
  final int count;
  final bool compact;
  const _NumberPill({required this.count, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    final diameter =
        count > 99 ? (compact ? 22.0 : 26.0) : (compact ? 15.0 : 18.0);
    return SizedBox(
        width: diameter,
        height: diameter,
        child: DecoratedBox(
            decoration: const BoxDecoration(
                color: Colors.redAccent, shape: BoxShape.circle),
            child: Center(
                child: Text(label,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 9 : 10,
                        height: 1,
                        fontWeight: FontWeight.w700)))));
  }
}

Map<String, dynamic> _profile(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String _profileId(Object? profile) => _profile(profile)['id'] as String? ?? '';

String _profileName(Map<String, dynamic> profile) =>
    (profile['nickname'] as String?)?.trim().isNotEmpty == true
        ? (profile['nickname'] as String).trim()
        : '齿间同学';

String _university(Map<String, dynamic> profile) =>
    (profile['university'] as String?)?.trim() ?? '';

/// All social surfaces use the same opaque-ID profile-card entry point.  The
/// card fetches its own server-filtered fields, rather than trusting whatever
/// lightweight map happened to render this avatar.
Widget _socialProfileAvatar(BuildContext context, Map<String, dynamic> profile,
    {double radius = 22}) {
  final avatar = UserAvatar(
      value: profile['avatar'] as String? ?? 'book',
      radius: radius,
      vip: profile['vipBadge'] == true);
  final userId = _profileId(profile);
  if (userId.isEmpty) return avatar;
  return Semantics(
      button: true,
      label: '查看 ${_profileName(profile)} 的资料',
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              showUserProfileSheet(context, userId, onOpenChat: (target) {
                if (!context.mounted) return;
                Navigator.of(context).push<void>(MaterialPageRoute(
                    builder: (_) => ChatThreadPage(friend: target)));
              }),
          child: avatar));
}

String _messagePreview(Object? value) {
  if (value is String) return value.trim();
  if (value is Map) return (value['body'] as String?)?.trim() ?? '';
  return '';
}

String _shortTime(String raw) {
  final time = DateTime.tryParse(raw)?.toLocal();
  if (time == null) return '';
  final now = DateTime.now();
  String two(int number) => number.toString().padLeft(2, '0');
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return '${two(time.hour)}:${two(time.minute)}';
  }
  return '${time.month}/${time.day}';
}

String _readableError(Object error) =>
    error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

IconData _notificationIcon(Object? type) {
  final kind = type?.toString().toLowerCase() ?? '';
  if (kind == 'vip_granted') return Icons.workspace_premium_outlined;
  if (kind.contains('like') || kind.contains('vote'))
    return Icons.thumb_up_alt_outlined;
  if (kind.contains('comment') || kind.contains('reply'))
    return Icons.forum_outlined;
  if (kind.contains('friend')) return Icons.person_add_alt_1_outlined;
  if (kind.contains('message') || kind.contains('chat'))
    return Icons.chat_bubble_outline;
  return Icons.notifications_none;
}

String _notificationTitle(Map<String, dynamic> notification) {
  final actor = _profile(notification['actor']);
  final name = actor.isEmpty ? '有人' : _profileName(actor);
  final kind = notification['type']?.toString().toLowerCase() ?? '';
  if (kind == 'vip_granted') {
    return notification['vipLifetime'] == true
        ? '系统消息：你已获得终身 VIP 会员'
        : '系统消息：VIP 会员服务已开通';
  }
  if (kind.contains('like') || kind.contains('vote')) return '$name 赞了你的评论';
  if (kind.contains('reply')) return '$name 回复了你的评论';
  if (kind.contains('comment')) return '$name 评论了题目';
  if (kind.contains('accepted')) return '$name 已通过你的好友申请';
  if (kind.contains('friend')) return '$name 向你发送了好友申请';
  if (kind.contains('message') || kind.contains('chat')) return '$name 发来一条消息';
  return '$name 有一条新动态';
}
