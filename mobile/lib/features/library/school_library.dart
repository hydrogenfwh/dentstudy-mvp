import 'dart:convert';
import 'package:flutter/services.dart';

/// Document reading is deliberately separate from scored question practice.
class SchoolDocument {
  final String id, title, section, subject, state, bodyAsset, sourceLabel;
  String text;
  final bool hasText, continuousQuestions;
  bool _bodyLoaded;
  Future<void>? _bodyLoading;
  final List<String> sourceFiles, schoolEvidence;
  final List<int> claimedYears;
  final bool courseSupplement, sourceAnswersReviewed;
  final int sourceDocumentCount;
  SchoolDocument.fromJson(Map<String, dynamic> data)
      : id = data['id'] as String,
        title = data['title'] as String,
        section = data['section'] as String,
        subject = data['subject'] as String,
        state = data['state'] as String,
        text = data['text'] as String? ?? '',
        bodyAsset = data['bodyAsset'] as String? ?? '',
        sourceLabel = data['sourceLabel'] as String? ?? '',
        continuousQuestions = data['continuousQuestions'] == true,
        hasText = data['hasText'] == true ||
            (data['text'] as String? ?? '').trim().isNotEmpty,
        _bodyLoaded = data.containsKey('text') ||
            (data['bodyAsset'] as String? ?? '').isEmpty,
        sourceFiles = List<String>.from(data['sourceFiles'] as List),
        schoolEvidence =
            List<String>.from(data['schoolEvidence'] as List? ?? []),
        claimedYears = List<int>.from(data['claimedYears'] as List? ?? []),
        courseSupplement = data['courseSupplement'] == true,
        sourceAnswersReviewed = data['sourceAnswersReviewed'] == true,
        sourceDocumentCount = (data['mergedRecordIds'] as List?)?.length ?? 1;

  bool get readable => hasText || text.trim().isNotEmpty;
  bool get bodyLoaded => _bodyLoaded;
  Future<void> loadBody({Future<String> Function(String)? reader}) {
    if (_bodyLoaded) return Future<void>.value();
    return _bodyLoading ??= _readBody(reader);
  }

  Future<void> _readBody(Future<String> Function(String)? reader) async {
    try {
      if (!RegExp(r'^assets/school_documents/[a-f0-9]{64}\.json$')
          .hasMatch(bodyAsset)) {
        throw const FormatException('Invalid reading asset');
      }
      final raw = await (reader ??
              (path) => rootBundle.loadString(path, cache: false))(bodyAsset)
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['id'] != id || data['text'] is! String) {
        throw const FormatException('Reading asset mismatch');
      }
      text = data['text'] as String;
      _bodyLoaded = true;
    } catch (_) {
      _bodyLoading = null;
      rethrow;
    }
  }

  String get statusLabel => switch (state) {
        'needs_ocr' => '待文字识别',
        'needs_extraction' || 'needs_cleanup' => '待版面整理',
        'needs_pairing' => '答案待配对',
        'needs_answer' => '答案待核对',
        'candidate' => '待逐题校验',
        'recalled' => '回忆版',
        'ocr_draft' => '扫描识别稿 · 待核对',
        'source_answers' => '含原资料答案',
        'verified_paper' => '真题',
        _ => '参考资料',
      };

  List<String> get readingBlocks {
    if (continuousQuestions) {
      return text
          .split(RegExp(r'\n\s*\n'))
          .map((block) => block.trim())
          .where((block) => block.isNotEmpty)
          .toList();
    }
    final result = <String>[];
    var current = '';
    for (final line in text.split('\n')) {
      if (current.length + line.length > 1600 && current.isNotEmpty) {
        result.add(current.trim());
        current = '';
      }
      // Bound even an exceptionally long single paragraph.
      var remaining = line;
      while (remaining.length > 1600) {
        if (current.trim().isNotEmpty) result.add(current.trim());
        final last = remaining.codeUnitAt(1599);
        final end = last >= 0xd800 && last <= 0xdbff ? 1599 : 1600;
        result.add(remaining.substring(0, end));
        current = '';
        remaining = remaining.substring(end);
      }
      current += '$remaining\n';
    }
    if (current.trim().isNotEmpty) result.add(current.trim());
    return result;
  }
}

class SchoolMaterialGroup {
  final String id, title;
  final List<SchoolDocument> documents;
  SchoolMaterialGroup(this.id, this.title, this.documents);
}

class SchoolMaterialBundle {
  final String id, subject;
  final List<SchoolMaterialGroup> groups;
  SchoolMaterialBundle(this.id, this.subject, this.groups);
  List<SchoolDocument> get documents =>
      groups.expand((g) => g.documents).toList();
  int get sourceDocumentCount =>
      documents.fold(0, (n, d) => n + d.sourceDocumentCount);
  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    return subject.toLowerCase().contains(needle) ||
        documents.any((d) =>
            '${d.title} ${d.sourceFiles.join(' ')}'
                .toLowerCase()
                .contains(needle) ||
            d.text.toLowerCase().contains(needle));
  }
}

class SchoolCollection {
  final String id, name, note, recalledTitle;
  Future<void>? _bodyLoading;
  final List<SchoolDocument> documents;
  late final List<SchoolMaterialBundle> materialBundles;
  SchoolCollection.fromJson(Map<String, dynamic> data)
      : id = data['id'] as String,
        name = data['name'] as String,
        note = data['note'] as String? ?? '',
        recalledTitle = data['recalledTitle'] as String? ?? '历年真题（回忆版）',
        documents = (data['documents'] as List)
            .map((d) =>
                SchoolDocument.fromJson(Map<String, dynamic>.from(d as Map)))
            .toList() {
    final byId = {for (final d in documents) d.id: d};
    final rawBundles = data['materialBundles'] as List?;
    if (rawBundles != null) {
      materialBundles = rawBundles.map((raw) {
        final bundle = raw as Map;
        final groups = (bundle['groups'] as List).map((rawGroup) {
          final group = rawGroup as Map;
          return SchoolMaterialGroup(
              group['id'] as String,
              group['title'] as String,
              (group['documentIds'] as List).map((id) => byId[id]!).toList());
        }).toList();
        return SchoolMaterialBundle(
            bundle['id'] as String, bundle['subject'] as String, groups);
      }).toList();
    } else {
      final subjects = <String, List<SchoolDocument>>{};
      for (final d in forSection('materials')) {
        subjects.putIfAbsent(d.subject, () => []).add(d);
      }
      materialBundles = subjects.entries
          .map((entry) => SchoolMaterialBundle(entry.key, entry.key,
              [SchoolMaterialGroup('combined', '资料合辑', entry.value)]))
          .toList();
    }
  }

  List<SchoolDocument> forSection(String section) =>
      documents.where((d) => d.section == section).toList();
  String sectionTitle(String section) =>
      section == 'recalled' ? recalledTitle : '资料包';
  Future<void> loadBodies() => _bodyLoading ??= _readBodies();
  Future<void> _readBodies() async {
    try {
      await loadSchoolBodies(documents);
    } catch (_) {
      _bodyLoading = null;
      rethrow;
    }
  }
}

/// Only an opened reading group (or an explicit body search) requests text.
/// Two workers bound simultaneous requests on slower mobile connections.
Future<void> loadSchoolBodies(List<SchoolDocument> documents) async {
  var next = 0;
  Future<void> worker() async {
    while (next < documents.length) {
      final document = documents[next++];
      await document.loadBody();
    }
  }

  await Future.wait([worker(), worker()], eagerError: true);
}

class SchoolLibrary {
  final List<SchoolCollection> schools;
  SchoolLibrary.fromJson(Map<String, dynamic> data)
      : schools = (data['schools'] as List)
            .map((s) =>
                SchoolCollection.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList();

  static Future<SchoolLibrary>? _loading;
  static Future<SchoolLibrary> load() => _loading ??= _read();
  static Future<SchoolLibrary> _read() async {
    try {
      final text = await rootBundle
          .loadString('assets/school_library_index.json', cache: false)
          .timeout(const Duration(seconds: 12));
      return SchoolLibrary.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }
}
