import 'dart:math' as math;
import 'package:flutter/material.dart';

const _comicInk = Color(0xFF34558A);
const _comicPaper = Color(0xFFF8FCFF);
const _gugaPaper = Color(0xFFF8F8F7);
const _gugaInk = Color(0xFF37363F);
const _gugaBorder = Color(0xFF45434D);

/// One bubble contains speech, four actions and a portrait. Empty space
/// outside this child passes taps through to the study page.
class DafeiyuComicPanels extends StatelessWidget {
  final Rect anchor;
  final EdgeInsets safeInsets;
  final String text;
  final bool sleeping, canChat, isAi, isThinking;
  final String companionName, portraitAsset;
  final bool showChat, isGuga;
  final VoidCallback onClose, onPet, onPraise, onSleep, onChat;
  final VoidCallback? onPlayVoice;
  const DafeiyuComicPanels(
      {super.key,
      required this.anchor,
      required this.safeInsets,
      required this.text,
      required this.sleeping,
      required this.canChat,
      required this.onClose,
      required this.onPet,
      required this.onPraise,
      required this.onSleep,
      required this.onChat,
      this.onPlayVoice,
      this.companionName = '大肥鱼',
      this.portraitAsset = 'assets/dafeiyu/runtime/03-wave.png',
      this.showChat = true,
      this.isGuga = false,
      this.isAi = false,
      this.isThinking = false});

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
        delegate: _ComicLayout(anchor, safeInsets),
        child: DafeiyuComicBubble(
          text: text,
          isAi: isAi,
          isThinking: isThinking,
          companionName: companionName,
          portraitAsset: portraitAsset,
          isGuga: isGuga,
          onClose: onClose,
          onPlayVoice: isThinking || isAi ? null : onPlayVoice,
          tailAbove: anchor.center.dy < MediaQuery.sizeOf(context).height * .43,
          footer: Wrap(
              key: const ValueKey('dafeiyu-interaction-menu'),
              spacing: 2,
              runSpacing: 2,
              children: [
                _action('摸摸头', onPet),
                _action('夸夸我', onPraise),
                _action(sleeping ? '醒醒啦' : '睡一会', onSleep),
                if (showChat) _action(canChat ? 'AI 聊天' : '聊天升级中', canChat ? onChat : null),
              ]),
        ),
      );

  Widget _action(String label, VoidCallback? callback) => TextButton(
      onPressed: callback,
      style: TextButton.styleFrom(
          foregroundColor: isGuga ? _gugaInk : _comicInk,
          backgroundColor: isGuga ? const Color(0xFFECECEF) : _comicInk.withAlpha(12),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          textStyle: const TextStyle(
              fontFamily: 'DentStudySans',
              fontFamilyFallback: ['DentStudySymbols', 'DentStudyMath'],
              fontSize: 12,
              fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      child: Text(label));
}

/// UI-only head crop of approved artwork, attached to the frame corner.
class _DafeiyuPortrait extends StatelessWidget {
  final String companionName, portraitAsset;
  final bool isGuga;
  const _DafeiyuPortrait({required this.companionName, required this.portraitAsset, required this.isGuga});
  @override
  Widget build(BuildContext context) => Semantics(
      image: true,
      label: '$companionName头像',
      child: Container(
          key: const ValueKey('dafeiyu-bubble-portrait'),
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
              color: isGuga ? const Color(0xFFECE8E1) : const Color(0xFFE8F1FF),
              shape: BoxShape.circle,
              border: Border.all(color: isGuga ? _gugaBorder : _comicInk, width: 1.5)),
          child: ClipOval(
              child: isGuga
                  ? OverflowBox(
                      alignment: Alignment.topCenter,
                      minWidth: 56,
                      maxWidth: 56,
                      minHeight: 67,
                      maxHeight: 67,
                      child: Image.asset(portraitAsset,
                          width: 56,
                          height: 67,
                          fit: BoxFit.contain,
                          cacheWidth: 128,
                          excludeFromSemantics: true,
                          errorBuilder: (_, error, stackTrace) =>
                              const Icon(Icons.face_rounded, color: _gugaBorder)))
                  : OverflowBox(
                  alignment: const Alignment(0, -.65),
                  maxWidth: 42,
                  maxHeight: 63,
                  child: Image.asset(portraitAsset,
                      width: 42,
                      height: 63,
                      fit: BoxFit.fill,
                      cacheWidth: 128,
                      excludeFromSemantics: true,
                      errorBuilder: (_, error, stackTrace) =>
                          const Icon(Icons.face_rounded, color: _comicInk))))));
}

class DafeiyuComicBubble extends StatelessWidget {
  final String text;
  final Widget footer;
  final VoidCallback onClose;
  final VoidCallback? onPlayVoice;
  final bool tailAbove, isAi, isThinking, isGuga;
  final String companionName, portraitAsset;
  const DafeiyuComicBubble(
      {super.key,
      required this.text,
      required this.footer,
      required this.onClose,
      this.onPlayVoice,
      this.companionName = '大肥鱼',
      this.portraitAsset = 'assets/dafeiyu/runtime/03-wave.png',
      this.tailAbove = false,
      this.isAi = false,
      this.isGuga = false,
      this.isThinking = false});

  @override
  Widget build(BuildContext context) => Stack(
          key: const ValueKey('dafeiyu-speech-bubble'),
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              painter: _ComicPainter(tailAbove, isGuga),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    15, tailAbove ? 19 : 7, 12, tailAbove ? 24 : 36),
                child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 15, color: isGuga ? _gugaInk : _comicInk),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(isAi ? '$companionName · AI 回复' : companionName,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: isGuga ? _gugaInk : _comicInk))),
                          if (onPlayVoice != null)
                            IconButton(
                                key: const ValueKey('dafeiyu-play-voice'),
                                tooltip: '播放大肥鱼语音',
                                onPressed: onPlayVoice,
                                constraints: const BoxConstraints.tightFor(
                                    width: 36, height: 36),
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.volume_up_outlined,
                                    size: 19, color: isGuga ? _gugaInk : _comicInk)),
                          IconButton(
                              tooltip: '收起$companionName气泡',
                              onPressed: onClose,
                              constraints: const BoxConstraints.tightFor(
                                  width: 36, height: 36),
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.close_rounded,
                                  size: 17, color: isGuga ? _gugaInk : _comicInk)),
                        ]),
                        Flexible(
                            fit: FlexFit.loose,
                            child: SingleChildScrollView(
                                key: const ValueKey('dafeiyu-speech-scroll'),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isThinking)
                                        _ThinkingDots(
                                            color: isGuga ? _gugaInk : _comicInk,
                                            label: isGuga ? '咕嘎正在回应' : '大肥鱼思考中')
                                      else
                                        Semantics(
                                            liveRegion: true,
                                            child: Text(text,
                                                key: const ValueKey(
                                                    'dafeiyu-speech-text'),
                                                style: TextStyle(
                                                    fontSize: 13.5,
                                                    height: 1.5,
                                                    color: isGuga ? _gugaInk : const Color(0xFF253D60)))),
                                      const SizedBox(height: 10),
                                      Divider(
                                          height: 1,
                                          color: (isGuga ? _gugaInk : _comicInk).withAlpha(28)),
                                      const SizedBox(height: 8),
                                      footer,
                                    ]))),
                      ],
                    )),
              ),
            ),
            Positioned(
                right: -4,
                bottom: tailAbove ? -12 : 0,
                child: IgnorePointer(child: _DafeiyuPortrait(companionName: companionName, portraitAsset: portraitAsset, isGuga: isGuga))),
          ]);
}

class _ThinkingDots extends StatefulWidget {
  final Color color;
  final String label;
  const _ThinkingDots({required this.color, required this.label});
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
      label: widget.label,
      liveRegion: true,
      child: ExcludeSemantics(
          child: AnimatedBuilder(
              animation: _float,
              builder: (_, child) => Transform.translate(
                  offset:
                      Offset(0, -3 * Curves.easeInOut.transform(_float.value)),
                  child: child),
              child: Text('···',
                  key: ValueKey('dafeiyu-thinking-dots'),
                  style: TextStyle(
                      fontSize: 22,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w800,
                      color: widget.color)))));
}

class _ComicPainter extends CustomPainter {
  final bool tailAbove, isGuga;
  _ComicPainter(this.tailAbove, this.isGuga);
  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTRB(1.5, tailAbove ? 14 : 1.5, size.width - 5,
        size.height - (tailAbove ? 5 : 17));
    final tailX = size.width * .80;
    final triangle = Path();
    if (tailAbove) {
      triangle
        ..moveTo(tailX - 12, body.top + 1)
        ..lineTo(tailX + 8, 1.5)
        ..lineTo(tailX + 4, body.top + 1)
        ..close();
    } else {
      triangle
        ..moveTo(tailX - 12, body.bottom - 1)
        ..lineTo(tailX + 8, size.height - 4)
        ..lineTo(tailX + 4, body.bottom - 1)
        ..close();
    }
    final path = Path.combine(
        PathOperation.union,
        Path()
          ..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(18))),
        triangle);
    canvas.drawPath(path.shift(const Offset(3, 3)),
        Paint()..color = (isGuga ? Colors.black : _comicInk).withAlpha(42));
    canvas.drawPath(path, Paint()..color = isGuga ? _gugaPaper : _comicPaper);
    canvas.drawPath(
        path,
        Paint()
          ..color = isGuga ? _gugaBorder : _comicInk
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _ComicPainter old) => old.tailAbove != tailAbove || old.isGuga != isGuga;
}

class _ComicLayout extends SingleChildLayoutDelegate {
  final Rect anchor;
  final EdgeInsets insets;
  _ComicLayout(this.anchor, this.insets);

  Rect _safe(Size size) => Rect.fromLTRB(
      insets.left + 10,
      insets.top + 10,
      math.max(insets.left + 11, size.width - insets.right - 10),
      math.max(insets.top + 11, size.height - insets.bottom - 24));

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final safe = _safe(constraints.biggest);
    return BoxConstraints(
        minWidth: math.min(210, safe.width),
        maxWidth: math.min(320, safe.width),
        maxHeight: math.min(340, safe.height));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final safe = _safe(size);
    final below = anchor.center.dy < size.height * .43;
    final top = below ? anchor.bottom + 12 : anchor.top - childSize.height - 12;
    return Offset(
        (anchor.right - childSize.width).clamp(
            safe.left, math.max(safe.left, safe.right - childSize.width)),
        top.clamp(
            safe.top, math.max(safe.top, safe.bottom - childSize.height)));
  }

  @override
  bool shouldRelayout(covariant _ComicLayout old) =>
      old.anchor != anchor || old.insets != insets;
}
