import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../models.dart';
import '../practice/mode_picker.dart';
import '../practice/practice_request.dart';
import 'catalog.dart';
import 'question_preview.dart';

/// Source browsing and ordinary chapter practice share question IDs.
class MaterialCollectionPage extends StatefulWidget {
  final String mode, collection;
  final StartPractice onStart;
  const MaterialCollectionPage({
    super.key,
    required this.mode,
    required this.collection,
    required this.onStart,
  });
  @override
  State<MaterialCollectionPage> createState() => _MaterialCollectionPageState();
}

class _MaterialCollectionPageState extends State<MaterialCollectionPage> {
  String? subject, chapter;
  int shown = 30;

  Future<void> _practice(List<Question> questions) async {
    final mode =
        await chooseStudyMode(context, review: false, count: questions.length);
    if (mode == null || !mounted) return;
    final label = '${widget.collection} · ${chapter ?? subject ?? '全部科目'}';
    Navigator.pop(context);
    await widget.onStart(PracticeRequest(questions, mode: mode, label: label));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = QuestionCatalog(store.questions, widget.mode)
            .inMode
            .where((q) => q.data['collection'] == widget.collection)
            .toList();
        final subjects = <String, List<Question>>{};
        for (final q in all) {
          subjects.putIfAbsent(q.subject, () => []).add(q);
        }
        final material =
            subject == null ? all : (subjects[subject] ?? <Question>[]);
        final chapters = QuestionCatalog.sortedChapters(
            material.map((q) => q.chapter).toSet());
        final selected = chapter == null
            ? material
            : material.where((q) => q.chapter == chapter).toList();
        return Scaffold(
            appBar: AppBar(title: Text(widget.collection)),
            body: PageBody(children: [
              if (subject != null)
                Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        onPressed: () => setState(() {
                              if (chapter != null) {
                                chapter = null;
                              } else {
                                subject = null;
                              }
                              shown = 30;
                            }),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(chapter == null ? '全部科目' : '章节目录'))),
              heading(chapter ?? subject ?? widget.collection,
                  sub: subject == null
                      ? '${all.length} 题 · ${subjects.length} 个科目'
                      : '${selected.length} 题${chapter == null ? ' · ${chapters.length} 章' : ''}'),
              if (subject == null)
                for (final entry in subjects.entries)
                  studyCard(
                      child: ListTile(
                          title: Text(entry.key),
                          subtitle: Text('${entry.value.length} 题 · '
                              '${entry.value.map((q) => q.chapter).toSet().length} 章'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => subject = entry.key)))
              else if (chapter == null)
                for (final name in chapters)
                  studyCard(
                      child: ListTile(
                          title: Text(name),
                          subtitle: Text(
                              '${material.where((q) => q.chapter == name).length} 题'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => chapter = name)))
              else ...[
                Wrap(spacing: 12, children: [
                  FilledButton.icon(
                      onPressed:
                          selected.isEmpty ? null : () => _practice(selected),
                      icon: const Icon(Icons.play_arrow),
                      label: Text('开始练习')),
                  OutlinedButton.icon(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => QuestionPreviewPage(
                                      questions: selected,
                                      title: '$subject · $chapter'))),
                      icon: const Icon(Icons.menu_book_outlined),
                      label: Text('查看答案')),
                ]),
                const SizedBox(height: 16),
                for (final q in selected.take(shown))
                  studyCard(
                      child: ListTile(
                          title: Text(q.stem,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(q.type),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => QuestionPreviewPage(
                                      questions: selected,
                                      initialQuestionId: q.id,
                                      title: '$subject · $chapter'))))),
                if (selected.length > shown)
                  TextButton(
                      onPressed: () => setState(() => shown += 30),
                      child: Text('再显示 30 题')),
              ],
            ]));
      });
}

Widget renweiCollectionEntry(BuildContext context,
    {required String mode, required StartPractice onStart}) {
  final count = QuestionCatalog(store.questions, mode)
      .inMode
      .where((q) => q.data['collection'] == '人卫练习题')
      .length;
  if (count == 0) return const SizedBox.shrink();
  return studyCard(
      child: ListTile(
          key: ValueKey('renwei-entry-$mode'),
          leading: const Icon(Icons.library_books_outlined),
          title: Text('人卫练习题'),
          subtitle: Text('$count 题 · 按科目与章节练习'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => MaterialCollectionPage(
                      mode: mode, collection: '人卫练习题', onStart: onStart)))));
}
