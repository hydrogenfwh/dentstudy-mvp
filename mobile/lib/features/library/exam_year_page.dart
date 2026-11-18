import 'package:flutter/material.dart';
import '../../app/shared.dart';
import '../../models.dart';
import '../practice/practice_request.dart';
import 'catalog.dart';
import 'exam_year_catalog.dart';
import 'question_preview.dart';
import 'material_collection_page.dart';

class ExamYearPage extends StatefulWidget {
  final String mode;
  final StartPractice onStart;
  const ExamYearPage({super.key, required this.mode, required this.onStart});
  @override
  State<ExamYearPage> createState() => _ExamYearPageState();
}

class _ExamYearPageState extends State<ExamYearPage> {
  int? year;
  String? paperId;
  int shown = 20;
  bool showPending = false;
  String? pendingCollection;

  static String _collectionOf(Question q) {
    final explicit = (q.data['collection'] as String?)?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final paper = q.data['paperName'] as String? ?? '未命名资料';
    final i = paper.indexOf(' · ');
    return i > 0 ? paper.substring(0, i) : paper;
  }

  Future<void> _practice(List<Question> questions, String label) async {
    final mode = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.all(20), child: Text('选择练习模式')),
              for (final entry
                  in {'deep': '逐题深度', 'batch': '批量练习', 'speed': '速刷'}.entries)
                ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(c, entry.key))
            ])));
    if (mode != null && mounted) {
      // Keep the existing session's return-to-today action in the tab shell.
      Navigator.pop(context);
      await widget
          .onStart(PracticeRequest(questions, mode: mode, label: label));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final archive = ExamYearCatalog(store.questions, widget.mode);
        final learnable = QuestionCatalog(store.questions, widget.mode)
            .learnable
            .map((q) => q.id)
            .toSet();
        final questions = year == null ? <Question>[] : archive.forYear(year!);
        final papers = <String, List<Question>>{};
        for (final q in questions) {
          papers.putIfAbsent(q.data['paperId'] as String, () => []).add(q);
        }
        final selected = papers[paperId] ?? [];
        final practice =
            selected.where((q) => learnable.contains(q.id)).toList();
        final pending = archive.questions
            .where((q) => ExamYearCatalog.verifiedYear(q) == null)
            .toList();
        final pendingCollections = <String, List<Question>>{};
        for (final q in pending) {
          pendingCollections.putIfAbsent(_collectionOf(q), () => []).add(q);
        }
        final collectionQuestions = pendingCollection == null
            ? <Question>[]
            : pending
                .where((q) => _collectionOf(q) == pendingCollection)
                .toList();
        final collectionPapers = <String, List<Question>>{};
        for (final q in collectionQuestions) {
          collectionPapers
              .putIfAbsent(q.data['paperName'] as String? ?? '未命名资料', () => [])
              .add(q);
        }
        final pendingCollectionEntries = pendingCollections.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final collectionPaperEntries = collectionPapers.entries.toList()
          ..sort((a, b) {
            final aName = a.key.replaceFirst('$pendingCollection · ', '');
            final bName = b.key.replaceFirst('$pendingCollection · ', '');
            final order = QuestionCatalog.chapterOrder(aName)
                .compareTo(QuestionCatalog.chapterOrder(bName));
            return order != 0 ? order : aName.compareTo(bName);
          });
        return Scaffold(
            appBar: AppBar(
                title: Text(pendingCollection ??
                    (year == null ? '${widget.mode} · 真题/模拟题' : '$year 年试题')),
                actions: [
                  if (paperId != null)
                    TextButton.icon(
                        onPressed: practice.isEmpty
                            ? null
                            : () => _practice(practice,
                                '$year 年 · ${selected.first.data['paperName']}'),
                        icon: const Icon(Icons.play_arrow),
                        label: Text('开始练习'))
                ]),
            body: PageBody(children: [
              if (year != null || showPending)
                Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        onPressed: () => setState(() {
                              if (pendingCollection != null) {
                                pendingCollection = null;
                              } else if (showPending) {
                                showPending = false;
                              } else if (paperId != null) {
                                paperId = null;
                              } else {
                                year = null;
                              }
                              shown = 20;
                            }),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(pendingCollection != null
                            ? '全部资料'
                            : showPending
                                ? '全部年份'
                                : (paperId == null ? '全部年份' : '本年试卷')))),
              if (showPending && pendingCollection == null) ...[
                heading('未标年份资料',
                    sub:
                        '${pending.length} 题 · ${pendingCollections.length} 份资料'),
                for (final entry in pendingCollectionEntries)
                  studyCard(
                      child: ListTile(
                          title: Text(entry.key),
                          subtitle: Text('${entry.value.length} 题'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            final papers = entry.value
                                .map((q) => q.data['paperName'])
                                .toSet();
                            if (papers.length == 1) {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => QuestionPreviewPage(
                                          questions: entry.value,
                                          title: entry.key)));
                            } else {
                              setState(() {
                                pendingCollection = entry.key;
                                shown = 20;
                              });
                            }
                          }))
              ] else if (showPending) ...[
                heading(pendingCollection!,
                    sub: '${collectionQuestions.length} 题 · 年份与来源待核验'),
                for (final entry in collectionPaperEntries)
                  studyCard(
                      child: ListTile(
                          title: Text(entry.key
                              .replaceFirst('$pendingCollection · ', '')),
                          subtitle: Text('${entry.value.length} 题'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => QuestionPreviewPage(
                                      questions: entry.value,
                                      title: entry.key)))))
              ] else if (year == null) ...[
                heading('按年份浏览', sub: '真题与回忆题分别标注来源'),
                if (archive.years.isEmpty && pending.isEmpty)
                  box(const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('真题/模拟题整理中',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Text('暂未收录年份与来源可核验的真题。可返回题库，继续按学科练习。')
                      ])),
                for (final value in archive.years)
                  studyCard(
                      child: ListTile(
                          title: Text('$value 年'),
                          subtitle: Text('${archive.forYear(value).length} 题 · '
                              '${archive.forYear(value).map((q) => q.data['paperId']).toSet().length} 份资料'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => year = value))),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  studyCard(
                      child: ListTile(
                          leading: const Icon(Icons.history_edu_outlined),
                          title: Text('未标年份资料'),
                          subtitle: Text('${pending.length} 题 · 年份与来源待核验'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() {
                                showPending = true;
                                pendingCollection = null;
                                shown = 20;
                              })))
                ],
                renweiCollectionEntry(context,
                    mode: widget.mode, onStart: widget.onStart),
              ] else if (paperId == null) ...[
                heading('$year 年', sub: '已收录 ${questions.length} 题；题量不代表完整试卷'),
                for (final entry in papers.entries)
                  studyCard(
                      child: ListTile(
                          title: Text(
                              entry.value.first.data['paperName'] as String),
                          subtitle: Text('${entry.value.length} 题 · '
                              '${QuestionCatalog.statusSummary(entry.value)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() => paperId = entry.key)))
              ] else ...[
                heading(
                    selected.isEmpty
                        ? '当前试卷暂无题目'
                        : selected.first.data['paperName'] as String,
                    sub: '已收录 ${selected.length} 题 · 可练 ${practice.length} 题'),
                if (practice.length < selected.length)
                  Text('部分学科题量不足，暂可查看解析；达到开放门槛后可练习。'),
                for (final q in selected.take(shown))
                  studyCard(
                      child: ListTile(
                          title: Text(q.stem,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${ExamYearCatalog.yearLabel(q)} · ${tr(q.subject)} · ${q.type}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => QuestionPreviewPage(
                                      questions: selected,
                                      initialQuestionId: q.id,
                                      title: '$year 年 · 题目解析'))))),
                if (selected.length > shown)
                  TextButton(
                      onPressed: () => setState(() => shown += 20),
                      child: Text('再显示 20 题'))
              ]
            ]));
      });
}
