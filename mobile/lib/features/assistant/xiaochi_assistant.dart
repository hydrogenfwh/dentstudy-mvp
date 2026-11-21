import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../app/shared.dart';
import 'dafeiyu_avatar.dart';
import 'dafeiyu_dialogue.dart';
import 'dafeiyu_comic_bubble.dart';
import 'dafeiyu_voice.dart';
import 'guga_avatar.dart';
import 'guga_dialogue.dart';
import 'livliv_avatar_stub.dart'
    if (dart.library.js_interop) 'livliv_avatar.dart';
import 'livliv_window_stub.dart'
    if (dart.library.js_interop) 'livliv_window_web.dart';

/// A request-only chat companion. The conversation exists in this widget for
/// the current visit and is intentionally never written to StudyStore.
class XiaochiAssistant extends StatefulWidget {
  const XiaochiAssistant({super.key});

  @override
  State<XiaochiAssistant> createState() => _XiaochiAssistantState();
}

enum _AvatarMood { idle, interact, thinking, speaking, thanks }

class _ChatLine {
  final String role;
  final String text;
  final String thinkingSummary;
  const _ChatLine(this.role, this.text, {this.thinkingSummary = ''});
}

class _XiaochiAssistantState extends State<XiaochiAssistant>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Keep the client affordance aligned with the server-side author check.
  // The server remains the authority, so editing a Web build cannot unlock
  // the chat endpoint for another account.
  static const _avatarWidth = 86.0;
  static const _avatarHeight = 129.0;
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatLine> _lines = [
    const _ChatLine(
        'assistant', '嗨，我是小齿～除了口腔备考，也可以问我“今日计划怎么开始”“题库怎么按章节练”或“题本在哪里”。')
  ];
  late final AnimationController _motion;
  Timer? _moodTimer;
  Timer? _careTimer;
  Timer? _holdTimer;
  Timer? _idleTimer;
  Timer? _interactionTimer;
  Timer? _thinkingTimer;
  bool _localThinking = false;
  final _interactionRandom = math.Random();
  late String _observedPreference;
  late String _observedVoiceMode;
  String _observedAccount = '';
  bool _showDafeiyuSpeech = false;
  bool _speechIsAi = false;
  final _dialogue = DafeiyuDialogueDeck();
  final _gugaDialogue = GugaDialogueDeck();
  final _voice = DafeiyuVoicePlayer();
  String? _voiceAsset;
  String _dafeiyuMessage = '大肥鱼来啦～今天也陪你一起学！';
  DafeiyuPose _dafeiyuPose = DafeiyuPose.wave;
  DafeiyuPose? _readyPose;
  int _livlivInteractionSerial = 0;
  String? _livlivExpression;
  Offset? _position;
  bool _open = false;
  bool _holding = false;
  bool _sending = false;
  bool _showCare = false;
  bool _deepThinking = false;
  _AvatarMood _mood = _AvatarMood.idle;

  bool get _isAuthor => !store.usesGuga && !store.usesLivlivPreview && store.canChatWithCompanion;
  String get _name => store.companionName;
  String get _preferenceKey =>
      '${store.userId}:${store.token}:${store.canChatWithCompanion}:${store.companionAppearance}:${store.xiaochiEnabled}';
  DafeiyuPose get _activePose {
    if (_holding) return DafeiyuPose.pout;
    switch (_mood) {
      case _AvatarMood.thinking:
        return DafeiyuPose.thinking;
      case _AvatarMood.speaking:
        return DafeiyuPose.happy;
      case _AvatarMood.thanks:
        return DafeiyuPose.praise;
      case _AvatarMood.interact:
        return DafeiyuPose.wave;
      case _AvatarMood.idle:
        return _dafeiyuPose;
    }
  }
  GugaPose get _gugaPose {
    if (_holding) return GugaPose.drag;
    if (_mood == _AvatarMood.speaking) return GugaPose.answer;
    return switch (_dafeiyuPose) {
      DafeiyuPose.happy => GugaPose.pet,
      DafeiyuPose.praise => GugaPose.praise,
      DafeiyuPose.sleep => GugaPose.sleep,
      DafeiyuPose.thinking => GugaPose.thinking,
      _ => GugaPose.idle,
    };
  }
  String _nextDialogue(DafeiyuInteraction action) {
    if (store.usesLivlivPreview) {
      return switch (action) {
        DafeiyuInteraction.pet => '摸摸头～今天也一起加油！ (｡•ᴗ•｡)',
        DafeiyuInteraction.praise => '你已经很努力啦，给自己一个赞！✨',
        DafeiyuInteraction.sleep => '休息一下，慢慢呼吸～🌙',
        _ => '醒啦，继续陪你一起学习～',
      };
    }
    return store.usesGuga ? _gugaDialogue.next(action) : _dialogue.next(action);
  }

  bool get _isWidgetTest => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  @override
  void initState() {
    super.initState();
    _observedPreference = _preferenceKey;
    _observedVoiceMode = store.dafeiyuVoiceMode;
    _observedAccount = store.userId;
    store.addListener(_preferencesChanged);
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    // A perpetually ticking avatar is desirable in the app, but it prevents
    // existing widget tests from ever reaching an idle frame. Avoid starting
    // it only under Flutter's test binding; production and local previews
    // retain the continuous breathing/sway motion.
    if (!_isWidgetTest) {
      _motion.repeat();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCare());
    }
    _scheduleSleep();
  }

  void _preferencesChanged() {
    if (!mounted) return;
    if (_observedVoiceMode != store.dafeiyuVoiceMode) {
      _observedVoiceMode = store.dafeiyuVoiceMode;
      _voice.stop();
      setState(() {});
    }
    if (_observedPreference == _preferenceKey) return;
    _voice.stop();
    _voiceAsset = null;
    _observedPreference = _preferenceKey;
    _idleTimer?.cancel();
    _thinkingTimer?.cancel();
    _interactionTimer?.cancel();
    _careTimer?.cancel();
    _moodTimer?.cancel();
    setState(() {
      _showDafeiyuSpeech = false;
      _localThinking = false;
      _speechIsAi = false;
      _showCare = false;
      _dafeiyuPose = DafeiyuPose.wave;
      _livlivExpression = null;
      _readyPose = null;
      _mood = _AvatarMood.idle;
      if (_observedAccount != store.userId || !store.canChatWithCompanion || store.usesGuga || store.usesLivlivPreview) {
        _observedAccount = store.userId;
        _open = false;
        _lines.removeRange(1, _lines.length);
      }
    });
    if (!_isWidgetTest) {
      if (store.xiaochiEnabled) {
        _motion.repeat();
      } else {
        _motion.stop();
      }
    }
    _scheduleSleep();
  }

  void _scheduleSleep() {
    _idleTimer?.cancel();
    if (!store.usesInteractiveCompanion || !store.xiaochiEnabled || _open || _sending)
      return;
    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted ||
          !store.usesInteractiveCompanion ||
          !store.xiaochiEnabled ||
          _open ||
          _holding ||
          _sending) return;
      setState(() {
        _dafeiyuPose = DafeiyuPose.sleep;
        _mood = _AvatarMood.idle;
        _showDafeiyuSpeech = false;
      });
    });
  }

  void _interact(DafeiyuPose pose, String text,
      {DafeiyuInteraction? interaction, String? livlivExpression}) {
    _thinkingTimer?.cancel();
    _idleTimer?.cancel();
    _moodTimer?.cancel();
    _interactionTimer?.cancel();
    _voice.stop();
    _voiceAsset =
        interaction == null || store.usesGuga || store.usesLivlivPreview ? null : dafeiyuVoiceAsset(interaction, text);
    setState(() {
      if (store.usesLivlivPreview) _livlivInteractionSerial++;
      _livlivExpression = livlivExpression;
      _localThinking = false;
      _mood = _AvatarMood.idle;
      _dafeiyuPose = pose;
      _dafeiyuMessage = text;
      _showDafeiyuSpeech = true;
      _speechIsAi = false;
    });
    if (_readyPose == pose) _startInteractionTimeout();
    if (_voiceAsset != null && store.dafeiyuVoiceMode == 'auto') {
      unawaited(_playVoice(manual: false));
    }
  }

  Future<void> _playVoice({required bool manual}) async {
    final asset = _voiceAsset;
    if (asset == null || store.dafeiyuVoiceMode == 'off') return;
    final played = await _voice.play(asset);
    if (!played && mounted && manual) {
      message(context, '语音暂时无法播放，请检查设备静音或浏览器设置。');
    }
  }

  void _poseReady(DafeiyuPose pose) {
    _readyPose = pose;
    if (!_open &&
        !_localThinking &&
        !_speechIsAi &&
        _showDafeiyuSpeech &&
        pose == _dafeiyuPose) {
      _startInteractionTimeout();
    }
  }

  void _startInteractionTimeout() {
    if (_dafeiyuPose != DafeiyuPose.sleep) _scheduleSleep();
    _interactionTimer?.cancel();
    _interactionTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() {
        _showDafeiyuSpeech = false;
        if (_dafeiyuPose != DafeiyuPose.sleep) {
          _dafeiyuPose = DafeiyuPose.wave;
          _livlivExpression = null;
        }
      });
    });
  }

  void _expressLivliv(String expression) {
    if (!store.usesLivlivPreview) return;
    final text = switch (expression) {
      'angry' => '我有点生闷气啦，需要你陪我 (^_^)',
      'sad' => '今天有一点不开心，可以陪陪我吗？ (T_T)',
      'shy' => '这样夸我，我会害羞的啦！ (*^_^*)',
      _ => null,
    };
    if (text == null) return;
    _thinkThen(() => _interact(DafeiyuPose.wave, text,
        livlivExpression: expression));
  }

  void _thinkThen(VoidCallback response) {
    if (!store.usesInteractiveCompanion || !store.xiaochiEnabled || _open || _holding)
      return;
    _voice.stop();
    _voiceAsset = null;
    _thinkingTimer?.cancel();
    _interactionTimer?.cancel();
    _idleTimer?.cancel();
    final scope = _preferenceKey;
    setState(() {
      _localThinking = true;
      _showDafeiyuSpeech = true;
      _speechIsAi = false;
    });
    _thinkingTimer = Timer(
        Duration(milliseconds: 200 + _interactionRandom.nextInt(301)), () {
      if (!mounted) return;
      if (scope != _preferenceKey || _holding || _open) {
        setState(() {
          _localThinking = false;
          _showDafeiyuSpeech = false;
        });
        return;
      }
      setState(() => _localThinking = false);
      response();
    });
  }

  void _closeDafeiyuBubble() {
    _voice.stop();
    _voiceAsset = null;
    _thinkingTimer?.cancel();
    _interactionTimer?.cancel();
    setState(() {
      _localThinking = false;
      _showDafeiyuSpeech = false;
    });
    _scheduleSleep();
  }

  void _greetDafeiyu() {
    final waking = _dafeiyuPose == DafeiyuPose.sleep;
    if (waking) {
      _interact(DafeiyuPose.wave, _nextDialogue(DafeiyuInteraction.wake),
          interaction: DafeiyuInteraction.wake);
    } else {
      _interact(DafeiyuPose.wave, store.usesLivlivPreview
          ? '来互动空间换个搭子，听听今天的问候吧。'
          : store.usesGuga
          ? '咕嘎来啦～摸摸头，或者让我夸夸你？(｡•ᴗ•｡) 🐧'
          : '大肥鱼来啦～摸摸头，或者让我夸夸你？(｡•ᴗ•｡)');
    }
  }

  void _avatarTapped() {
    _holdTimer?.cancel();
    if (_holding) return;
    if (!store.usesInteractiveCompanion) {
      _openChat();
      return;
    }
    _thinkThen(_greetDafeiyu);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isWidgetTest && store.xiaochiEnabled) _motion.repeat();
      _scheduleSleep();
    } else {
      _voice.stop();
      _motion.stop();
      _idleTimer?.cancel();
      _thinkingTimer?.cancel();
      if (_localThinking) {
        setState(() {
          _localThinking = false;
          _showDafeiyuSpeech = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _voice.dispose();
    _thinkingTimer?.cancel();
    _moodTimer?.cancel();
    _careTimer?.cancel();
    _holdTimer?.cancel();
    _idleTimer?.cancel();
    _interactionTimer?.cancel();
    store.removeListener(_preferencesChanged);
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _scheduleCare() async {
    // One quiet, local greeting at most once every three days: useful enough
    // to feel companionable without constantly interrupting study.
    await Future<void>.delayed(const Duration(seconds: 16));
    if (!mounted ||
        store.usesInteractiveCompanion ||
        !store.xiaochiEnabled ||
        !_isAuthor ||
        store.token.isEmpty ||
        _open) return;
    if (!await store.claimXiaochiGreeting() || !mounted) return;
    setState(() {
      _showCare = true;
      _mood = _AvatarMood.interact;
    });
    _careTimer = Timer(const Duration(seconds: 9), () {
      if (mounted) setState(() => _showCare = false);
      _setMood(_AvatarMood.idle);
    });
  }

  void _setMood(_AvatarMood mood, {Duration? resetAfter}) {
    _moodTimer?.cancel();
    if (mounted) setState(() => _mood = mood);
    if (resetAfter != null) {
      _moodTimer = Timer(resetAfter, () {
        if (mounted) setState(() => _mood = _AvatarMood.idle);
      });
    }
  }

  void _openChat() {
    _voice.stop();
    _voiceAsset = null;
    _thinkingTimer?.cancel();
    _holdTimer?.cancel();
    if (_holding) return;
    if (!_isAuthor) {
      message(context, '${_name}正在升级中···');
      return;
    }
    if (store.token.isEmpty) {
      message(context, '登录后才能和${_name}聊天，请前往「我的」登录或注册。');
      return;
    }
    _careTimer?.cancel();
    _idleTimer?.cancel();
    _interactionTimer?.cancel();
    setState(() {
      _open = true;
      _localThinking = false;
      _showCare = false;
      _showDafeiyuSpeech = false;
    });
    _setMood(_AvatarMood.interact,
        resetAfter: const Duration(milliseconds: 1300));
    _scrollToBottom();
  }

  void _closeChat() {
    FocusScope.of(context).unfocus();
    _interactionTimer?.cancel();
    setState(() {
      _open = false;
      if (store.usesDafeiyu &&
          _lines.length > 1 &&
          _lines.last.role == 'assistant') {
        _dafeiyuMessage = _lines.last.text;
        _speechIsAi = true;
        _showDafeiyuSpeech = true;
      }
    });
    _setMood(_AvatarMood.idle);
    _scheduleSleep();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    final requestAccount = store.userId;
    final requestCompanion = store.companionAppearance;
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    if (text.length > 1000) {
      message(context, '消息请控制在 1000 个字以内');
      return;
    }
    final history = _lines.length <= 6
        ? List<_ChatLine>.from(_lines)
        : _lines.sublist(_lines.length - 6);
    setState(() {
      _lines.add(_ChatLine('user', text));
      _composer.clear();
      _sending = true;
      _mood = _AvatarMood.thinking;
    });
    _scrollToBottom();
    try {
      final reply = await store.chatWithXiaochi(
          message: text,
          history: history
              .map((line) => {'role': line.role, 'content': line.text})
              .toList(),
          deep: _deepThinking);
      if (!mounted ||
          !store.canChatWithCompanion ||
          store.userId != requestAccount ||
          store.companionAppearance != requestCompanion) return;
      setState(() {
        _lines.add(_ChatLine('assistant', reply.text,
            thinkingSummary: reply.thinkingSummary));
        if (store.usesDafeiyu) {
          _dafeiyuMessage = reply.text;
          _showDafeiyuSpeech = true;
          _speechIsAi = true;
        }
        _mood = _AvatarMood.speaking;
      });
      _moodTimer?.cancel();
      _moodTimer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _mood = _AvatarMood.thanks);
        _moodTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted) setState(() => _mood = _AvatarMood.idle);
        });
      });
    } catch (error) {
      if (!mounted ||
          !store.canChatWithCompanion ||
          store.userId != requestAccount ||
          store.companionAppearance != requestCompanion) return;
      final detail =
          error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _lines.add(_ChatLine(
            'assistant', detail.isEmpty ? '${_name}暂时没能回复，请稍后再试。' : detail));
        _mood = _AvatarMood.idle;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Offset _clampPosition(Offset proposed, Size size, EdgeInsets padding) {
    final bottomReserved = (store.glassEnabled ? 104.0 : 94.0) + padding.bottom;
    final maxX = math.max(8.0, size.width - _avatarWidth - 8);
    final maxY = math.max(72.0, size.height - _avatarHeight - bottomReserved);
    return Offset(proposed.dx.clamp(8.0, maxX).toDouble(),
        proposed.dy.clamp(72.0, maxY).toDouble());
  }

  void _armDrag() {
    _holdTimer?.cancel();
    // Flutter's default long-press delay is intentionally conservative.
    // 小齿 is a floating control, so a short hold makes its drag affordance
    // feel immediate without turning an ordinary tap into a drag.
    _holdTimer = Timer(const Duration(milliseconds: 120), _startHolding);
  }

  void _startHolding() {
    if (_holding) return;
    _voice.stop();
    _voiceAsset = null;
    _holdTimer?.cancel();
    _careTimer?.cancel();
    _thinkingTimer?.cancel();
    setState(() {
      _localThinking = false;
      _holding = true;
      _showCare = false;
      _showDafeiyuSpeech = false;
    });
    _idleTimer?.cancel();
  }

  void _moveHolding(DragUpdateDetails details, Size size, EdgeInsets padding) {
    _startHolding();
    final proposed = Offset(details.globalPosition.dx - _avatarWidth / 2,
        details.globalPosition.dy - _avatarHeight / 2);
    setState(() => _position = _clampPosition(proposed, size, padding));
  }

  Future<void> _endHolding(Size size, EdgeInsets padding) async {
    _holdTimer?.cancel();
    if (!_holding) return;
    final position = _position;
    if (position != null) {
      final maxX = math.max(8.0, size.width - _avatarWidth - 8);
      final maxY = math.max(
          72.0,
          size.height -
              _avatarHeight -
              (store.glassEnabled ? 104.0 : 94.0) -
              padding.bottom);
      await store.setXiaochiPosition(position.dx / maxX, position.dy / maxY);
    }
    // Keep the drag state through this event turn so the tap recognizer cannot
    // also open the chat when someone simply holds the avatar in place.
    await Future<void>.delayed(Duration.zero);
    if (mounted) {
      setState(() => _holding = false);
      _scheduleSleep();
    }
  }

  void _cancelHolding() {
    _holdTimer?.cancel();
    if (mounted && _holding) {
      setState(() => _holding = false);
      _scheduleSleep();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store, builder: (context, _) => _buildOverlay(context));

  Widget _buildOverlay(BuildContext context) {
    if (!store.xiaochiEnabled) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final size = media.size;
    final padding = media.padding;
    final maxX = math.max(8.0, size.width - _avatarWidth - 8);
    final maxY = math.max(
        72.0,
        size.height -
            _avatarHeight -
            (store.glassEnabled ? 104.0 : 94.0) -
            padding.bottom);
    final initial = Offset(maxX - 2, maxY - 4);
    final persisted = store.xiaochiPositionX != null &&
            store.xiaochiPositionY != null
        ? Offset(store.xiaochiPositionX! * maxX, store.xiaochiPositionY! * maxY)
        : initial;
    final position = _clampPosition(_position ?? persisted, size, padding);
    final chatWidth = math.min(366.0, size.width - 24);

    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
          right: 12,
          bottom: (store.glassEnabled ? 92.0 : 78.0) + padding.bottom,
          child: _ChatPanel(
              open: _open,
              width: chatWidth,
              sending: _sending,
              composer: _composer,
              scroll: _scroll,
              lines: _lines,
              deepThinking: _deepThinking,
              onDeepThinkingChanged: (value) =>
                  setState(() => _deepThinking = value),
              onClose: _closeChat,
              onSend: _send)),
      if (!_open || !store.usesInteractiveCompanion)
        Positioned(
            left: position.dx,
            top: position.dy,
            child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                key: const ValueKey('floating-companion'),
                onTap: _avatarTapped,
                onTapDown: (_) => _armDrag(),
                onTapUp: (_) {
                  if (_holding) {
                    unawaited(_endHolding(size, padding));
                  } else {
                    _holdTimer?.cancel();
                  }
                },
                onTapCancel: _cancelHolding,
                onPanStart: (_) => _startHolding(),
                onPanUpdate: (details) => _moveHolding(details, size, padding),
                onPanEnd: (_) => unawaited(_endHolding(size, padding)),
                onPanCancel: _cancelHolding,
                child: SizedBox(
                    width: _avatarWidth,
                    height: _avatarHeight,
                    child: Stack(clipBehavior: Clip.none, children: [
                      if (_showCare)
                        Positioned(
                            right: 20,
                            bottom: 103,
                            child: _CareBubble(onTap: _openChat)),
                      Positioned.fill(
                          child: store.usesLivlivPreview
                              ? LivLivAvatar(
                                  key: const ValueKey('livliv-preview-avatar'),
                                  pose: _holding ? DafeiyuPose.pout : _dafeiyuPose,
                                  expression: _holding ? null : _livlivExpression,
                                  interactionSerial: _livlivInteractionSerial,
                                  onPoseReady: _poseReady)
                              : store.usesGuga
                              ? GugaAvatar(
                                  key: const ValueKey('guga-avatar'),
                                  pose: _gugaPose,
                                  onPoseReady: () => _poseReady(_dafeiyuPose),
                                  motion: _motion,
                                  sleepNudge: math.max(0.0, (_avatarHeight - _avatarWidth) / 2 - position.dx) -
                                      math.max(0.0, (_avatarHeight - _avatarWidth) / 2 - (size.width - position.dx - _avatarWidth)),
                                  reducedMotion: MediaQuery.disableAnimationsOf(context))
                              : store.usesDafeiyu
                              ? DafeiyuAvatar(
                                  key: const ValueKey('dafeiyu-avatar'),
                                  pose: _activePose,
                                  onPoseReady: _poseReady,
                                  motion: _motion,
                                  reducedMotion:
                                      MediaQuery.disableAnimationsOf(context))
                              : _AvatarArt(
                                  mood: _mood,
                                  motion: _motion,
                                  holding: _holding)),
                    ])))),
      if (store.usesInteractiveCompanion && !_open && _showDafeiyuSpeech)
        Positioned.fill(
            child: DafeiyuComicPanels(
                anchor: Rect.fromLTWH(
                    position.dx, position.dy, _avatarWidth, _avatarHeight),
                safeInsets: EdgeInsets.fromLTRB(
                    padding.left,
                    padding.top,
                    padding.right,
                    math.max(
                        (store.glassEnabled ? 104.0 : 94.0) + padding.bottom,
                        media.viewInsets.bottom)),
                text: _dafeiyuMessage,
                companionName: store.companionName,
                isGuga: store.usesGuga,
                portraitAsset: store.usesLivlivPreview ? 'assets/livliv/kujira.webp' : (store.usesGuga ? 'assets/guga/guga-idle-body.png' : DafeiyuPose.wave.asset),
                isLivliv: store.usesLivlivPreview,
                showChat: !store.usesGuga && !store.usesLivlivPreview,
                isThinking: _localThinking,
                isAi: _speechIsAi,
                sleeping: _dafeiyuPose == DafeiyuPose.sleep,
                canChat: store.usesLivlivPreview ? store.canChatWithCompanion : _isAuthor,
                onPlayVoice: _voice.available &&
                        _voiceAsset != null &&
                        store.dafeiyuVoiceMode != 'off'
                    ? () => unawaited(_playVoice(manual: true))
                    : null,
                onClose: _closeDafeiyuBubble,
                onExpand: kIsWeb || store.usesLivlivPreview ? openLivLivConversation : null,
                onEmotion: store.usesLivlivPreview ? _expressLivliv : null,
                onPet: () => _thinkThen(() => _interact(
                    DafeiyuPose.happy, _nextDialogue(DafeiyuInteraction.pet),
                    interaction: DafeiyuInteraction.pet)),
                onPraise: () => _thinkThen(
                    () => _interact(DafeiyuPose.praise, _nextDialogue(DafeiyuInteraction.praise), interaction: DafeiyuInteraction.praise)),
                onSleep: () => _thinkThen(() => _dafeiyuPose == DafeiyuPose.sleep ? _greetDafeiyu() : _interact(DafeiyuPose.sleep, _nextDialogue(DafeiyuInteraction.sleep), interaction: DafeiyuInteraction.sleep)),
                onChat: () => _thinkThen(_openChat)))
    ]);
  }
}

class _AvatarArt extends StatelessWidget {
  final _AvatarMood mood;
  final Animation<double> motion;
  final bool holding;
  const _AvatarArt(
      {required this.mood, required this.motion, required this.holding});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: motion,
      builder: (context, _) {
        final wave = math.sin(motion.value * math.pi * 2);
        var lift = 0.0;
        var turn = 0.0;
        var scaleX = 1.0;
        var scaleY = 1.0;
        switch (mood) {
          case _AvatarMood.idle:
            lift = wave * 1.6;
            turn = wave * .018;
            scaleX = 1 + wave * .007;
            scaleY = 1 - wave * .006;
            break;
          case _AvatarMood.interact:
            lift = -math.max(0, wave) * 7;
            turn = wave * .04;
            break;
          case _AvatarMood.thinking:
            lift = wave * 1.8;
            turn = wave * .035;
            break;
          case _AvatarMood.speaking:
            lift = wave * 1.2;
            turn = wave * .012;
            break;
          case _AvatarMood.thanks:
            lift = -math.max(0, wave) * 5;
            scaleX = 1 + math.max(0, wave) * .025;
            scaleY = 1 - math.max(0, wave) * .018;
            break;
        }
        return AnimatedScale(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutBack,
            scale: holding ? 1.12 : 1,
            child: Stack(clipBehavior: Clip.none, children: [
              if (holding)
                Positioned.fill(
                    child: Transform.scale(
                        scale: 1.06 + (wave + 1) * .025,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: teal.withAlpha(150), width: 1.5),
                                boxShadow: [
                              BoxShadow(
                                  color: teal.withAlpha(65),
                                  blurRadius: 18,
                                  spreadRadius: 4)
                            ])))),
              Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..translateByDouble(0.0, lift, 0.0, 1.0)
                    ..rotateZ(turn)
                    ..scaleByDouble(scaleX, scaleY, 1.0, 1.0),
                  child: ClipPath(
                      // The supplied illustration has a faint opaque studio
                      // vignette despite its PNG alpha channel. A soft
                      // character-shaped mask removes that rectangular field
                      // without changing the face or the illustrated pixels.
                      clipper: const _AvatarSilhouetteClipper(),
                      child: const _AvatarImage())),
              if (mood == _AvatarMood.speaking)
                Positioned(
                    left: 39,
                    top: 53,
                    child: Transform.scale(
                        scaleY: .65 + math.max(0, wave) * .65,
                        alignment: Alignment.topCenter,
                        child: Container(
                            width: 5.5,
                            height: 2.6,
                            decoration: const BoxDecoration(
                                color: Color(0xFFE88486),
                                borderRadius: BorderRadius.vertical(
                                    bottom: Radius.circular(5)))))),
              if (mood == _AvatarMood.thinking)
                _OrbitDots(progress: motion.value),
              if (mood == _AvatarMood.thanks) _Sparkles(progress: motion.value),
            ]));
      });
}

class _AvatarSilhouetteClipper extends CustomClipper<Path> {
  const _AvatarSilhouetteClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    // This deliberately follows the broad outline instead of making a card
    // or a circle. At the on-screen avatar size it leaves room for hair tips,
    // sleeves and shoes while excluding the source artwork's backdrop.
    return Path()
      ..moveTo(w * .49, 0)
      ..cubicTo(w * .35, h * .02, w * .24, h * .08, w * .17, h * .16)
      ..cubicTo(w * .10, h * .10, w * .03, h * .16, w * .07, h * .24)
      ..cubicTo(0, h * .29, w * .07, h * .36, w * .14, h * .39)
      ..cubicTo(w * .08, h * .44, w * .13, h * .50, w * .21, h * .52)
      ..cubicTo(w * .16, h * .59, w * .10, h * .66, w * .12, h * .73)
      ..cubicTo(w * .16, h * .78, w * .21, h * .75, w * .24, h * .70)
      ..cubicTo(w * .23, h * .80, w * .30, h * .85, w * .38, h * .87)
      ..cubicTo(w * .34, h * .94, w * .29, h * .98, w * .29, h)
      ..lineTo(w * .71, h)
      ..cubicTo(w * .71, h * .98, w * .66, h * .94, w * .62, h * .87)
      ..cubicTo(w * .70, h * .85, w * .77, h * .80, w * .76, h * .70)
      ..cubicTo(w * .79, h * .75, w * .84, h * .78, w * .88, h * .73)
      ..cubicTo(w * .90, h * .66, w * .84, h * .59, w * .79, h * .52)
      ..cubicTo(w * .87, h * .50, w * .92, h * .44, w * .86, h * .39)
      ..cubicTo(w * .93, h * .36, w, h * .29, w * .93, h * .24)
      ..cubicTo(w * .97, h * .16, w * .90, h * .10, w * .83, h * .16)
      ..cubicTo(w * .76, h * .08, w * .65, h * .02, w * .49, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _AvatarSilhouetteClipper oldClipper) => false;
}

/// Uses the original supplied illustration without any colour overlays.
/// This avoids introducing visible clip edges around hair or clothing when a
/// theme changes.
class _AvatarImage extends StatelessWidget {
  const _AvatarImage();

  @override
  Widget build(BuildContext context) => Image.asset('assets/xiaochi/avatar.png',
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: '小齿，口腔备考搭子');
}

class _OrbitDots extends StatelessWidget {
  final double progress;
  const _OrbitDots({required this.progress});
  @override
  Widget build(BuildContext context) => Positioned(
      left: 24,
      top: -1,
      width: 40,
      height: 40,
      child: Stack(
          children: List.generate(3, (index) {
        final radians = progress * math.pi * 2 + index * math.pi * 2 / 3;
        return Positioned(
            left: 17 + math.cos(radians) * 16,
            top: 17 + math.sin(radians) * 12,
            child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                    color: Color(0xFFDFFFFE),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0xAA72FFF6), blurRadius: 7)
                    ])));
      })));
}

class _Sparkles extends StatelessWidget {
  final double progress;
  const _Sparkles({required this.progress});
  @override
  Widget build(BuildContext context) {
    final grow = 1 + math.max(0, math.sin(progress * math.pi * 2)) * .35;
    return Positioned.fill(
        child: Transform.scale(
            scale: grow,
            child: Stack(children: const [
              Positioned(left: 7, top: 37, child: _Sparkle()),
              Positioned(right: 5, top: 48, child: _Sparkle()),
              Positioned(left: 16, bottom: 32, child: _Sparkle()),
              Positioned(right: 14, bottom: 20, child: _Sparkle()),
            ])));
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle();
  @override
  Widget build(BuildContext context) => Container(
      width: 4.5,
      height: 4.5,
      decoration: const BoxDecoration(
          color: Color(0xFFDFFFFE),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0xAA65FFF2), blurRadius: 7)]));
}

class _CareBubble extends StatelessWidget {
  final VoidCallback onTap;
  const _CareBubble({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
              width: 196,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                  color: store.glassEnabled
                      ? Colors.white.withAlpha(208)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: teal.withAlpha(32)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha(18),
                        blurRadius: 16,
                        offset: const Offset(0, 5))
                  ]),
              child:
                  Text('今天也辛苦啦，刷几道就很好～', style: TextStyle(fontSize: 12.5)))));
}

class _ChatPanel extends StatelessWidget {
  final bool open;
  final double width;
  final bool sending;
  final TextEditingController composer;
  final ScrollController scroll;
  final List<_ChatLine> lines;
  final bool deepThinking;
  final ValueChanged<bool> onDeepThinkingChanged;
  final VoidCallback onClose;
  final Future<void> Function() onSend;
  const _ChatPanel({
    required this.open,
    required this.width,
    required this.sending,
    required this.composer,
    required this.scroll,
    required this.lines,
    required this.deepThinking,
    required this.onDeepThinkingChanged,
    required this.onClose,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) => IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          opacity: open ? 1 : 0,
          child: AnimatedScale(
              duration: const Duration(milliseconds: 230),
              curve: Curves.easeOutBack,
              alignment: Alignment.bottomRight,
              scale: open ? 1 : .9,
              child: SizedBox(
                  width: width,
                  height: 444,
                  child: Material(
                      color: Colors.transparent,
                      child: Container(
                          decoration: BoxDecoration(
                              color: store.glassEnabled
                                  ? Colors.white.withAlpha(210)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: store.glassEnabled
                                      ? Colors.white.withAlpha(230)
                                      : teal.withAlpha(36)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withAlpha(34),
                                    blurRadius: 26,
                                    offset: const Offset(0, 12))
                              ]),
                          child: Column(children: [
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 11, 8, 8),
                                child: Row(children: [
                                  CircleAvatar(
                                      radius: 17,
                                      backgroundColor: teal.withAlpha(30),
                                      child: Image.asset(
                                          store.usesDafeiyu
                                              ? DafeiyuPose.wave.asset
                                              : 'assets/xiaochi/avatar.png',
                                          fit: BoxFit.contain)),
                                  const SizedBox(width: 9),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(store.companionName,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16)),
                                        Text('口腔医学/备考不限 · 闲聊每日 10 句',
                                            style: TextStyle(
                                                color: Colors.blueGrey,
                                                fontSize: 11))
                                      ])),
                                  IconButton(
                                      tooltip: '关闭${store.companionName}聊天',
                                      onPressed: onClose,
                                      icon: const Icon(Icons.close_rounded))
                                ])),
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(15, 0, 12, 7),
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilterChip(
                                        avatar: Icon(
                                            Icons.psychology_alt_outlined,
                                            size: 16,
                                            color: deepThinking
                                                ? Colors.white
                                                : teal),
                                        label: Text('深度思考',
                                            style: TextStyle(fontSize: 11.5)),
                                        selected: deepThinking,
                                        selectedColor: teal,
                                        labelStyle: TextStyle(
                                            color: deepThinking
                                                ? Colors.white
                                                : ink),
                                        side: BorderSide(
                                            color: teal.withAlpha(50)),
                                        visualDensity: VisualDensity.compact,
                                        tooltip: '生成可展开的学习思路摘要，不展示模型内部推理',
                                        onSelected: sending
                                            ? null
                                            : onDeepThinkingChanged))),
                            Divider(height: 1, color: teal.withAlpha(20)),
                            Expanded(
                                child: ListView.builder(
                                    controller: scroll,
                                    padding: const EdgeInsets.fromLTRB(
                                        13, 14, 13, 6),
                                    itemCount: lines.length + (sending ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == lines.length) {
                                        return const _TypingLine();
                                      }
                                      if (index == 0 && store.usesDafeiyu) {
                                        return _ChatBubble(
                                            line: _ChatLine(
                                                'assistant',
                                                lines[index].text.replaceFirst(
                                                    '我是小齿', '我是大肥鱼')));
                                      }
                                      return _ChatBubble(line: lines[index]);
                                    })),
                            const Padding(
                                padding: EdgeInsets.fromLTRB(15, 2, 15, 7),
                                child: Text(
                                    '消息仅为当前回复发送给 AI 服务，DentStudy 不保存聊天内容。请勿发送隐私或未授权资料。',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: Colors.blueGrey))),
                            Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 8, 10),
                                child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                          child: TextField(
                                              controller: composer,
                                              enabled: !sending,
                                              minLines: 1,
                                              maxLines: 3,
                                              maxLength: 1000,
                                              textInputAction:
                                                  TextInputAction.send,
                                              onSubmitted: (_) => onSend(),
                                              decoration: const InputDecoration(
                                                  hintText: '问问学习方法或知识点…',
                                                  counterText: '',
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          horizontal: 13,
                                                          vertical: 11)))),
                                      const SizedBox(width: 5),
                                      IconButton.filled(
                                          tooltip: '发送给${store.companionName}',
                                          onPressed: sending ? null : onSend,
                                          icon: sending
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white))
                                              : const Icon(
                                                  Icons.arrow_upward_rounded))
                                    ]))
                          ])))))));
}

class _ChatBubble extends StatelessWidget {
  final _ChatLine line;
  const _ChatBubble({required this.line});
  @override
  Widget build(BuildContext context) {
    final mine = line.role == 'user';
    final comic = !mine && store.usesDafeiyu;
    return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
            constraints: const BoxConstraints(maxWidth: 286),
            margin: const EdgeInsets.only(bottom: 9),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
                color: mine
                    ? teal
                    : comic
                        ? const Color(0xFFF8FCFF)
                        : teal.withAlpha(17),
                border: comic
                    ? Border.all(color: const Color(0xFF34558A), width: 1.4)
                    : null,
                boxShadow: comic
                    ? const [
                        BoxShadow(
                            color: Color(0x2234558A), offset: Offset(2, 3))
                      ]
                    : null,
                borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(15),
                    topRight: const Radius.circular(15),
                    bottomLeft: Radius.circular(mine ? 15 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 15))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.text,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: mine ? Colors.white : ink)),
              if (!mine && line.thinkingSummary.isNotEmpty) ...[
                const SizedBox(height: 7),
                _ThinkingSummary(text: line.thinkingSummary),
              ]
            ])));
  }
}

/// A compact, user-facing study outline. It deliberately does not expose
/// provider chain-of-thought or other hidden model reasoning.
class _ThinkingSummary extends StatefulWidget {
  final String text;
  const _ThinkingSummary({required this.text});

  @override
  State<_ThinkingSummary> createState() => _ThinkingSummaryState();
}

class _ThinkingSummaryState extends State<_ThinkingSummary> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) => InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => expanded = !expanded),
      child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
              color: Colors.blueGrey.withAlpha(10),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.blueGrey.withAlpha(24))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.account_tree_outlined,
                  size: 13, color: Colors.blueGrey),
              const SizedBox(width: 4),
              Text(expanded ? '收起思路摘要' : '展开思路摘要',
                  style:
                      const TextStyle(fontSize: 10.5, color: Colors.blueGrey)),
              const Spacer(),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16, color: Colors.blueGrey)
            ]),
            if (expanded) ...[
              const SizedBox(height: 4),
              Text(widget.text,
                  style: const TextStyle(
                      fontSize: 11.2, height: 1.42, color: Colors.blueGrey)),
            ]
          ])));
}

class _TypingLine extends StatelessWidget {
  const _TypingLine();
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: teal.withAlpha(17),
              borderRadius: BorderRadius.circular(15)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: teal)),
            const SizedBox(width: 8),
            Text('${store.companionName}正在想…',
                style: const TextStyle(fontSize: 12.5))
          ])));
}
