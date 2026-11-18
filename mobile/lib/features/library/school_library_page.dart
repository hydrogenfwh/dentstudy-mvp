import 'package:flutter/material.dart';
import '../../app/shared.dart';
import 'school_library.dart';

class SchoolLibraryPage extends StatefulWidget {
  final Future<SchoolLibrary> Function()? loader;
  const SchoolLibraryPage({super.key, this.loader});
  @override
  State<SchoolLibraryPage> createState() => _SchoolLibraryPageState();
}

class _SchoolLibraryPageState extends State<SchoolLibraryPage> {
  late Future<SchoolLibrary> future;
  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<SchoolLibrary> _load() => (widget.loader ?? SchoolLibrary.load)()
      .timeout(const Duration(seconds: 15));

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(tr('按学校分类'))),
      body: FutureBuilder<SchoolLibrary>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return PageBody(children: [
                heading('学校资料暂未加载成功'),
                Text('不会影响原有题库，请重试。'),
                TextButton(
                    onPressed: () => setState(() {
                          future = _load();
                        }),
                    child: Text('重新加载')),
              ]);
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final schools = snapshot.data!.schools;
            return PageBody(children: [
              heading('考研 · 按学校分类', sub: tr('${schools.length} 所院校 · 按学校查找真题与资料')),
              if (schools.isEmpty) Text(tr('院校资料正在整理中。')),
              for (final school in schools)
                studyCard(
                    child: ListTile(
                        key: ValueKey('school-${school.id}'),
                        leading: Icon(Icons.school_outlined, color: teal),
                        title: Text(tr(school.name)),
                        subtitle: Text('${tr(school.recalledTitle)} · ${tr('资料包')}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    SchoolHomePage(school: school))))),
            ]);
          }));
}

class SchoolHomePage extends StatelessWidget {
  final SchoolCollection school;
  const SchoolHomePage({super.key, required this.school});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(tr(school.name))),
      body: PageBody(children: [
        heading(tr(school.name), sub: '考研资料'),
        for (final section in const ['recalled', 'materials'])
          studyCard(
              child: ListTile(
                  key: ValueKey('school-section-$section'),
                  contentPadding: const EdgeInsets.all(18),
                  leading: Icon(
                      section == 'recalled'
                          ? Icons.history_edu_outlined
                          : Icons.folder_open_outlined,
                      color: teal),
                  title: Text(tr(school.sectionTitle(section))),
                  subtitle: Text(tr(section == 'recalled'
                      ? '${school.forSection(section).length} 份资料 · ${school.recalledTitle}'
                      : '${school.materialBundles.length} 个合并资料包 · 按科目整理')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SchoolSectionPage(
                              school: school, section: section))))),
        const SizedBox(height: 16),
        Text(tr(school.note),
            style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
      ]));
}

String sectionTitle(String section) =>
    section == 'recalled' ? '历年真题（回忆版）' : '资料包';

class SchoolSectionPage extends StatefulWidget {
  final SchoolCollection school;
  final String section;
  const SchoolSectionPage(
      {super.key, required this.school, required this.section});
  @override
  State<SchoolSectionPage> createState() => _SchoolSectionPageState();
}

class _SchoolSectionPageState extends State<SchoolSectionPage> {
  String query = '';
  bool searching = false;
  String? searchError;
  int searchVersion = 0;
  void _search(String value) {
    final version = ++searchVersion;
    setState(() {
      query = value.trim();
      searchError = null;
      searching = widget.section == 'materials' && query.isNotEmpty;
    });
    if (!searching) return;
    widget.school.loadBodies().timeout(const Duration(seconds: 25)).then((_) {
      if (mounted && version == searchVersion) {
        setState(() => searching = false);
      }
    }, onError: (Object error) {
      if (mounted && version == searchVersion) {
        setState(() {
          searching = false;
          searchError = '正文搜索暂未完成，请重试；科目目录仍可使用。';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final documents = widget.school.forSection(widget.section);
    final matches = documents
        .where((d) => (query.isEmpty ||
            '${d.title} ${d.subject} ${d.sourceFiles.join(' ')}'
                .toLowerCase()
                .contains(query.toLowerCase())))
        .toList();
    final materials = widget.section == 'materials';
    final bundles =
        widget.school.materialBundles.where((b) => b.matches(query)).toList();
    return Scaffold(
        appBar: AppBar(title: Text(tr(widget.school.sectionTitle(widget.section)))),
        body: PageBody(
            key: PageStorageKey('school:${widget.school.id}:${widget.section}'),
            children: [
              heading(tr(widget.school.name),
                  sub: materials
                      ? '${bundles.length} 个合并资料包 · 同科同类集中阅读'
                      : '${matches.length} 份资料 · ${widget.school.sectionTitle(widget.section)}'),
              TextField(
                  key: const ValueKey('school-document-search'),
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: materials ? '搜索科目、题目或答案关键词' : '搜索资料名称或科目'),
                  onChanged: _search),
              const SizedBox(height: 14),
              if (searching) ...[
                const LinearProgressIndicator(),
                Text('正在搜索资料正文…'),
              ],
              if (searchError != null) ...[
                Text(searchError!),
                TextButton(
                    onPressed: () => _search(query), child: Text('重试搜索')),
              ],
              if (materials) ...[
                if (bundles.isEmpty) Text('暂时没有匹配的资料。'),
                for (final bundle in bundles)
                  studyCard(
                      child: ListTile(
                          key: ValueKey('school-bundle-${bundle.id}'),
                          title: Text(tr(bundle.subject)),
                          subtitle: Text(
                              '${bundle.sourceDocumentCount} 份原资料已合并 · ${bundle.groups.length} 个分区'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      SchoolBundlePage(bundle: bundle))))),
              ] else ...[
                if (matches.isEmpty) Text('暂时没有匹配的资料。'),
                for (final document in matches)
                  studyCard(
                      child: ListTile(
                          key: ValueKey('school-document-${document.id}'),
                          title: Text(document.title),
                          subtitle: Text([
                            if (widget.section == 'recalled' &&
                                document.claimedYears.isNotEmpty)
                              '${document.claimedYears.join('、')} 年${document.sourceLabel == '真题' ? '' : ' · 原资料标注'}',
                            if (document.courseSupplement) '本科课程补充',
                            document.statusLabel,
                            document.readable ? '可阅读原文' : '文字整理中',
                          ].join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => SchoolDocumentPage(
                                      document: document,
                                      school: widget.school))))),
              ],
            ]));
  }
}

class SchoolBundlePage extends StatelessWidget {
  final SchoolMaterialBundle bundle;
  const SchoolBundlePage({super.key, required this.bundle});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(tr(bundle.subject))),
      body: PageBody(children: [
        heading('${tr(bundle.subject)} · ${tr('合并资料包')}',
            sub:
                '${bundle.sourceDocumentCount} 份原资料，按内容合并为 ${bundle.groups.length} 个分区'),
        for (final group in bundle.groups)
          studyCard(
              child: ListTile(
                  key: ValueKey('school-material-group-${group.id}'),
                  leading: Icon(
                      group.id == 'pending'
                          ? Icons.hourglass_empty
                          : Icons.menu_book_outlined,
                      color: teal),
                  title: Text(group.title),
                  subtitle: Text(
                      '${group.documents.fold<int>(0, (n, d) => n + d.sourceDocumentCount)} 份原资料 · '
                      '${group.id == 'pending' ? '保留清单，等待整理' : '已合并为一份连续阅读合辑'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SchoolMergedReadingPage(
                              bundle: bundle, group: group))))),
        const SizedBox(height: 12),
        Text('完全相同的正文仅保留一份；不同版本和不同答案仍分别保留，并可查看原始来源。',
            style: TextStyle(color: Colors.blueGrey, fontSize: 13)),
      ]));
}

class SchoolReadingLoader extends StatefulWidget {
  final List<SchoolDocument> documents;
  final String title;
  final WidgetBuilder builder;
  const SchoolReadingLoader(
      {super.key,
      required this.documents,
      required this.title,
      required this.builder});
  @override
  State<SchoolReadingLoader> createState() => _SchoolReadingLoaderState();
}

class _SchoolReadingLoaderState extends State<SchoolReadingLoader> {
  late Future<void> future;
  @override
  void initState() {
    super.initState();
    future = loadSchoolBodies(widget.documents);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.documents.every((d) => d.bodyLoaded))
      return widget.builder(context);
    return FutureBuilder<void>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              !snapshot.hasError) {
            return widget.builder(context);
          }
          return Scaffold(
              appBar: AppBar(title: Text(widget.title)),
              body: PageBody(children: [
                if (snapshot.hasError) ...[
                  heading('资料暂未加载成功'),
                  Text('目录和学习记录均保留，可重试加载正文。'),
                  TextButton(
                      onPressed: () => setState(() {
                            future = loadSchoolBodies(widget.documents);
                          }),
                      child: Text('重新加载正文')),
                ] else ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  const Center(child: Text('正在加载这份资料…')),
                ],
              ]));
        });
  }
}

class SchoolMergedReadingPage extends StatelessWidget {
  final SchoolMaterialBundle bundle;
  final SchoolMaterialGroup group;
  const SchoolMergedReadingPage(
      {super.key, required this.bundle, required this.group});
  @override
  Widget build(BuildContext context) => SchoolReadingLoader(
      documents: group.documents,
      title: '${tr(bundle.subject)} · ${group.title}',
      builder: (_) => _SchoolMergedReadingBody(bundle: bundle, group: group));
}

class _SchoolMergedReadingBody extends StatelessWidget {
  final SchoolMaterialBundle bundle;
  final SchoolMaterialGroup group;
  const _SchoolMergedReadingBody({required this.bundle, required this.group});

  Future<void> _sources(BuildContext context, SchoolDocument document) =>
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => SafeArea(
              child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .6,
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    heading(document.sourceLabel.isNotEmpty ? '来源' : '原始来源',
                        sub: document.title),
                    for (final file in document.sourceFiles)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SelectableText(file)),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('关闭')),
                  ]))));

  @override
  Widget build(BuildContext context) {
    final rows = <({SchoolDocument? document, String? text})>[];
    for (final document in group.documents) {
      rows.add((document: document, text: null));
      if (document.readable) {
        rows.addAll(
            document.readingBlocks.map((text) => (document: null, text: text)));
      } else {
        rows.add((document: null, text: '这份原资料仍需文字识别或版面核对，暂未加入合辑正文。'));
      }
    }
    return Scaffold(
        appBar: AppBar(title: Text('${tr(bundle.subject)} · ${group.title}')),
        body: SafeArea(
            top: false,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: ListView.builder(
                        key: PageStorageKey(
                            'school-merged:${bundle.id}:${group.id}'),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        itemCount: rows.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0)
                            return Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      heading(group.title,
                                          sub: '${tr(bundle.subject)} · ${tr('合并阅读')}'),
                                      box(Text(group.documents.every(
                                              (d) => d.sourceLabel.isNotEmpty)
                                          ? '来源：${group.documents.map((d) => d.sourceLabel).toSet().join('、')}。主观题不自动判分。'
                                          : group.documents.every((d) =>
                                                  d.sourceAnswersReviewed)
                                              ? '同类资料与原资料答案已合并阅读，来源页码仍保留。主观题不自动判分。'
                                              : '同类原资料已合并阅读，原始出处仍保留。笔记及答案尚未逐题核验，不代表已审核的标准答案。')),
                                    ]));
                          final row = rows[index - 1];
                          final document = row.document;
                          if (document != null)
                            return Padding(
                                padding:
                                    const EdgeInsets.only(top: 16, bottom: 12),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Divider(),
                                      Text(document.title,
                                          style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold)),
                                      Text(document.statusLabel,
                                          style: const TextStyle(
                                              color: Colors.blueGrey,
                                              fontSize: 12)),
                                      TextButton.icon(
                                          key: ValueKey(
                                              'merged-source-${document.id}'),
                                          onPressed: () =>
                                              _sources(context, document),
                                          icon: const Icon(
                                              Icons.source_outlined,
                                              size: 16),
                                          label: Text(
                                              document.sourceLabel.isNotEmpty
                                                  ? '来源：${document.sourceLabel}'
                                                  : '原始来源')),
                                    ]));
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: SelectableText(row.text!,
                                  style: const TextStyle(
                                      fontSize: 16, height: 1.65)));
                        })))));
  }
}

class SchoolDocumentPage extends StatelessWidget {
  final SchoolDocument document;
  final SchoolCollection? school;
  const SchoolDocumentPage({super.key, required this.document, this.school});
  @override
  Widget build(BuildContext context) => SchoolReadingLoader(
      documents: [document],
      title: document.title,
      builder: (_) => _SchoolDocumentBody(document: document, school: school));
}

class _SchoolDocumentBody extends StatelessWidget {
  final SchoolDocument document;
  final SchoolCollection? school;
  const _SchoolDocumentBody({required this.document, this.school});
  @override
  Widget build(BuildContext context) {
    final blocks = document.readingBlocks;
    return Scaffold(
        appBar: AppBar(title: Text(document.title)),
        body: SafeArea(
            top: false,
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: ListView.builder(
                        key: PageStorageKey('school-reading:${document.id}'),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                        itemCount: blocks.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  heading(document.title,
                                      sub:
                                          '${tr(document.subject)} · ${document.statusLabel}'),
                                  box(Text(document.sourceLabel.isNotEmpty
                                      ? '来源：${document.sourceLabel}。主观题不自动判分。'
                                      : document.sourceAnswersReviewed
                                          ? '已收录原资料答案；明确配对的答案直接附在题目下方。主观题不自动判分。'
                                          : '资料原文预览；回忆题、笔记及答案尚未逐题核验，不作为已审核的标准答案。')),
                                  if (document.sourceAnswersReviewed &&
                                      school != null)
                                    TextButton.icon(
                                        key: const ValueKey(
                                            'school-answer-packs'),
                                        onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    SchoolSectionPage(
                                                        school: school!,
                                                        section: 'materials'))),
                                        icon: const Icon(
                                            Icons.menu_book_outlined),
                                        label: Text('查看各科答案资料包')),
                                  const SizedBox(height: 12),
                                  ExpansionTile(
                                      key: PageStorageKey(
                                          'school-source:${document.id}'),
                                      tilePadding: EdgeInsets.zero,
                                      title: Text(
                                          document.sourceLabel.isNotEmpty
                                              ? '来源'
                                              : '查看原始来源'),
                                      children: [
                                        for (final source
                                            in document.sourceFiles)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: SelectableText(source,
                                                  key: PageStorageKey(
                                                      'school-source-text:${document.id}:$source'),
                                                  style: const TextStyle(
                                                      fontSize: 12))),
                                      ]),
                                  if (!document.readable)
                                    const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 24),
                                        child: Text(
                                            '这份资料需要文字识别或版面核对，暂未开放原文阅读。不会用空白题或猜测答案代替原资料。')),
                                  const SizedBox(height: 14),
                                ]);
                          }
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: SelectableText(blocks[index - 1],
                                  style: const TextStyle(
                                      fontSize: 16, height: 1.65)));
                        })))));
  }
}
