import 'package:flutter/material.dart';
import 'features/assistant/guga_avatar.dart';

void main() => runApp(const MaterialApp(
    debugShowCheckedModeBanner: false, home: _MotionPreview()));

class _MotionPreview extends StatefulWidget {
  const _MotionPreview();
  @override
  State<_MotionPreview> createState() => _MotionPreviewState();
}

class _MotionPreviewState extends State<_MotionPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion;
  GugaPose selected = GugaPose.idle;
  bool dragging = false;
  Offset offset = Offset.zero;
  static const labels = <GugaPose, String>{
    GugaPose.idle: '待机挥手',
    GugaPose.pet: '摸摸头',
    GugaPose.sleep: '睡一会',
    GugaPose.praise: '夸夸我',
    GugaPose.thinking: '思考',
    GugaPose.answer: '回答动作',
    GugaPose.drag: '拖动表情',
  };
  @override
  void initState() {
    super.initState();
    motion = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xfff6f4ef),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('咕嘎 · 动作预览',
                            style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                                color: Color(0xff303b47))),
                        const SizedBox(height: 8),
                        const Text('点选动作，或直接拖动咕嘎试试',
                            style: TextStyle(color: Color(0xff687582))),
                        const SizedBox(height: 18),
                        Container(
                            width: 440,
                            height: 430,
                            decoration: BoxDecoration(
                                color: const Color(0xffefede5),
                                borderRadius: BorderRadius.circular(32)),
                            clipBehavior: Clip.hardEdge,
                            child: Center(
                                child: AnimatedContainer(
                                    duration: Duration(
                                        milliseconds: dragging ? 0 : 350),
                                    curve: Curves.easeOutCubic,
                                    transform: Matrix4.translationValues(
                                        offset.dx, offset.dy, 0),
                                    child: GestureDetector(
                                      onPanStart: (_) =>
                                          setState(() => dragging = true),
                                      onPanUpdate: (d) =>
                                          setState(() => offset += d.delta),
                                      onPanEnd: (_) => setState(() {
                                        dragging = false;
                                        offset = Offset.zero;
                                      }),
                                      onPanCancel: () => setState(() {
                                        dragging = false;
                                        offset = Offset.zero;
                                      }),
                                      child: SizedBox(
                                          width: 260,
                                          height: 390,
                                          child: GugaAvatar(
                                              pose: dragging
                                                  ? GugaPose.drag
                                                  : selected,
                                              motion: motion)),
                                    )))),
                        const SizedBox(height: 20),
                        ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final item in labels.entries)
                                    ChoiceChip(
                                        label: Text(item.value),
                                        selected: selected == item.key,
                                        onSelected: (_) =>
                                            setState(() => selected = item.key))
                                ])),
                        const SizedBox(height: 12),
                        const Text('回答仅展示动作，不接入 AI 聊天或语音。',
                            style: TextStyle(
                                color: Color(0xff78848d), fontSize: 12)),
                      ]))))));
}
