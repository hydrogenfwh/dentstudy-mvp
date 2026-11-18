import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dentstudy/features/assistant/dafeiyu_dialogue.dart';
import 'package:dentstudy/features/assistant/dafeiyu_comic_bubble.dart';

void main() {
  test('four pools contain twenty unique lines and an occasional catchphrase',
      () {
    expect(dafeiyuDialogue.length, 4);
    for (final pool in dafeiyuDialogue.values) {
      expect(pool.length, 20);
      expect(pool.toSet().length, 20);
      expect(pool.where((line) => line.contains('哦鲸鲸')).length, 3);
      expect(pool.every((line) => line.trim().isNotEmpty), isTrue);
    }
  });

  test('every dialogue maps to its numbered voice asset', () {
    for (final interaction in DafeiyuInteraction.values) {
      final lines = dafeiyuDialogue[interaction]!;
      for (var i = 0; i < lines.length; i++) {
        expect(dafeiyuVoiceAsset(interaction, lines[i]),
            'assets/dafeiyu/voice/${interaction.name}-${(i + 1).toString().padLeft(2, '0')}.m4a');
      }
      expect(dafeiyuVoiceAsset(interaction, 'not a dialogue'), isNull);
    }
  });

  test('each shuffle cycle is complete with no immediate boundary repeat', () {
    for (var seed = 0; seed < 20; seed++) {
      final deck = DafeiyuDialogueDeck(random: Random(seed));
      for (final interaction in DafeiyuInteraction.values) {
        String? last;
        for (var cycle = 0; cycle < 5; cycle++) {
          final seen = <String>{};
          for (var i = 0; i < 20; i++) {
            final line = deck.next(interaction);
            expect(line, isNot(last));
            expect(seen.add(line), isTrue);
            last = line;
          }
          expect(seen, dafeiyuDialogue[interaction]!.toSet());
        }
      }
    }
  });

  for (final viewport in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
    const Size(320, 320),
    const Size(1440, 900)
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('comic panels fit $viewport at text scale $scale',
          (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final point in [
          const Offset(0, 0),
          const Offset(1, 0),
          const Offset(0, 1),
          const Offset(1, 1),
          const Offset(.5, .5)
        ]) {
          var pressed = 0;
          final x = 10 + (viewport.width - 106) * point.dx;
          final y = 60 + max(0, viewport.height - 300) * point.dy;
          await tester.pumpWidget(MaterialApp(
              home: MediaQuery(
                  data: MediaQueryData(
                      size: viewport, textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                      body: Stack(children: [
                    Positioned(
                        left: 0,
                        bottom: 0,
                        child: TextButton(
                            key: const ValueKey('underlying-page-action'),
                            onPressed: () => pressed++,
                            child: const Text('页面按钮'))),
                    Positioned.fill(
                        child: DafeiyuComicPanels(
                            anchor: Rect.fromLTWH(x, y, 86, 129),
                            safeInsets: const EdgeInsets.only(bottom: 94),
                            text: List.filled(
                                    20, '哦鲸鲸～你不需要先交出成绩单，才值得被温柔对待 (≧▽≦) 🐳')
                                .join('\n'),
                            sleeping: false,
                            canChat: true,
                            onClose: () {},
                            onPet: () {},
                            onPraise: () {},
                            onSleep: () {},
                            onChat: () {})),
                  ])))));
          await tester.pump();
          final speech = tester
              .getRect(find.byKey(const ValueKey('dafeiyu-speech-bubble')));
          for (final rect in [speech]) {
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(viewport.width));
            expect(rect.bottom, lessThanOrEqualTo(viewport.height - 94));
          }
          final portrait =
              find.byKey(const ValueKey('dafeiyu-bubble-portrait'));
          await tester.ensureVisible(portrait);
          await tester.pumpAndSettle();
          final portraitRect = tester.getRect(portrait);
          final textRect =
              tester.getRect(find.byKey(const ValueKey('dafeiyu-speech-text')));
          final controls = tester
              .getRect(find.byKey(const ValueKey('dafeiyu-interaction-menu')));
          final viewportRect = tester
              .getRect(find.byKey(const ValueKey('dafeiyu-speech-scroll')));
          expect(portraitRect.size, const Size(36, 36));
          expect(
              textRect.intersect(viewportRect).overlaps(portraitRect), isFalse);
          expect(
              controls.intersect(viewportRect).overlaps(portraitRect), isFalse);
          expect(portraitRect.right, closeTo(speech.right + 4, .01));
          expect(portraitRect.bottom,
              inInclusiveRange(speech.bottom, speech.bottom + 12));
          expect(portraitRect.bottom, lessThanOrEqualTo(viewport.height - 94));
          for (final label in ['摸摸头', '夸夸我', '睡一会', 'AI 聊天']) {
            final action = find.widgetWithText(TextButton, label);
            expect(
                find.descendant(
                    of: find.byKey(const ValueKey('dafeiyu-speech-bubble')),
                    matching: action),
                findsOneWidget);
            await tester.ensureVisible(action);
            await tester.pumpAndSettle();
            await tester.tap(action);
          }
          await tester
              .tap(find.byKey(const ValueKey('underlying-page-action')));
          expect(pressed, 1);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
