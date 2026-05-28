import 'dart:convert';
import 'book.dart';
import 'package:reader/core/models/rule_data_interface.dart';
import 'package:reader/core/engine/book/book_help.dart';

/// SearchBook - 搜尋結果模型
/// (原 Android data/entities/SearchBook.kt)
class SearchBook implements RuleDataInterface {
  String bookUrl; // 書籍 URL
  String name; // 書名
  String? author; // 作者
  String? kind; // 分類
  String? coverUrl; // 封面 URL
  String? intro; // 簡介
  String? wordCount; // 字數
  String? latestChapterTitle; // 最新章節
  String origin; // 書源 URL
  String? originName; // 書源名稱
  int originOrder; // 書源排序
  int type; // 書源類型
  int addTime; // 添加時間
  String? variable; // 暫存變數
  String? tocUrl; // 目錄 URL
  int respondTime; // 回應時間

  // --- Transient Properties (Not persisted, Android parity) ---
  String? infoHtml;
  String? tocHtml;

  late final Set<String> origins = {origin};
  late final Map<String, String> _originNames = {
    if (originName != null && originName!.isNotEmpty) origin: originName!,
  };

  void addOrigin(String o, {String? name}) {
    origins.add(o);
    if (name != null && name.isNotEmpty) {
      _originNames[o] = name;
    }
  }

  List<String> get sourceLabels =>
      origins.map((originUrl) => _originNames[originUrl] ?? originUrl).toList();

  // 核心業務方法
  String getRealAuthor() => BookHelp.formatBookAuthor(author ?? '');
  String get latestChapter => latestChapterTitle ?? '無最新章節';

  @override
  Map<String, String> get variableMap {
    if (variable == null || variable!.isEmpty) return {};
    try {
      final decoded = jsonDecode(variable!);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  @override
  void putVariable(String key, String? value) {
    final map = variableMap;
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    variable = map.isEmpty ? null : jsonEncode(map);
  }

  @override
  String getVariable(String key) => variableMap[key] ?? '';

  SearchBook({
    required this.bookUrl,
    required this.name,
    this.author,
    this.kind,
    this.coverUrl,
    this.intro,
    this.wordCount,
    this.latestChapterTitle,
    required this.origin,
    this.originName,
    this.originOrder = 0,
    this.type = 0,
    this.addTime = 0,
    this.variable,
    this.tocUrl,
    this.respondTime = 0,
  });

  factory SearchBook.fromJson(Map<String, dynamic> json) {
    return SearchBook(
      bookUrl: json['bookUrl'] ?? '',
      name: json['name'] ?? '',
      author: json['author'],
      kind: json['kind'],
      coverUrl: json['coverUrl'],
      intro: json['intro'],
      wordCount: json['wordCount'],
      latestChapterTitle: json['latestChapterTitle'],
      origin: json['origin'] ?? '',
      originName: json['originName'],
      originOrder: json['originOrder'] ?? 0,
      type: json['type'] ?? 0,
      addTime: json['addTime'] ?? 0,
      variable: json['variable'],
      tocUrl: json['tocUrl'],
      respondTime: json['respondTime'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bookUrl': bookUrl,
      'name': name,
      'author': author,
      'kind': kind,
      'coverUrl': coverUrl,
      'intro': intro,
      'wordCount': wordCount,
      'latestChapterTitle': latestChapterTitle,
      'origin': origin,
      'originName': originName,
      'originOrder': originOrder,
      'type': type,
      'addTime': addTime,
      'variable': variable,
      'tocUrl': tocUrl,
      'respondTime': respondTime,
    };
  }

  Book toBook() {
    return Book(
      bookUrl: bookUrl,
      tocUrl: tocUrl ?? '',
      origin: origin,
      originName: originName ?? '',
      name: name,
      author: author ?? '',
      kind: kind,
      coverUrl: coverUrl,
      intro: intro,
      latestChapterTitle: latestChapterTitle,
      wordCount: wordCount,
      type: type,
      originOrder: originOrder,
      variable: variable,
    );
  }
}

class AggregatedSearchBook {
  final dynamic book; // Can be Book or SearchBook
  final List<String> sources;

  AggregatedSearchBook({required this.book, required this.sources});
}
