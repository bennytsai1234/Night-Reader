import 'dart:convert';

import 'book.dart';

import 'package:night_reader/core/models/rule_data_interface.dart';
import 'package:night_reader/core/engine/book/book_help.dart';
import 'package:night_reader/core/utils/string_utils.dart';

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

  /// 搜尋合併卡的身分（正規化書名＋作者），建立合併卡時由搜尋分組填入；
  /// 原始結果為 null。不存檔。
  String? groupIdentity;

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

  /// 從同一群組（同名 + 同作者 / 安置後的缺作者）建立一張「合併卡」。
  ///
  /// 僅用於呈現層：書架儲存模型仍是「每源獨立」，此方法不會改動傳入的原始
  /// [SearchBook]（[origins] 為 `late final`，於原物件上呼叫 [addOrigin] 會
  /// 永久污染，故這裡複製出全新的 representative 物件再累計 origins）。
  ///
  /// representative 決定點進去、加入書架預設的來源（[origin]）與卡片上的
  /// 最新章節，見 [_pickRepresentative]。它缺的封面、簡介、分類與字數從
  /// 群組裡其他來源補上。
  static SearchBook aggregate(List<SearchBook> group) {
    if (group.isEmpty) {
      throw ArgumentError.value(group, 'group', 'aggregate 需要非空群組');
    }
    final representative = _pickRepresentative(group);
    final card = representative._cloneForCard();
    for (final book in group) {
      card.addOrigin(book.origin, name: book.originName);
      // 缺作者的來源被選成代表時，作者也從其他來源補：卡片的身分（書名＋
      // 作者，見 searchResultIdentity）跟著分組，不會因為換代表就變成另一本。
      card.author = _filled(card.author) ?? book.author;
      card.coverUrl = _filled(card.coverUrl) ?? book.coverUrl;
      card.intro = _filled(card.intro) ?? book.intro;
      card.kind = _filled(card.kind) ?? book.kind;
      card.wordCount = _filled(card.wordCount) ?? book.wordCount;
    }
    return card;
  }

  static String? _filled(String? value) =>
      (value ?? '').trim().isEmpty ? null : value;

  /// 最新章節最新的來源（章節編號較大；讀不出編號的排在後面）；一樣新時
  /// 取這次搜尋回得最快的，再一樣就照書源順序。
  static SearchBook _pickRepresentative(List<SearchBook> group) {
    int compare(SearchBook a, SearchBook b) {
      final byChapter = (b._latestChapterNumber ?? -1).compareTo(
        a._latestChapterNumber ?? -1,
      );
      if (byChapter != 0) return byChapter;
      final bySpeed = a._searchSpeed.compareTo(b._searchSpeed);
      if (bySpeed != 0) return bySpeed;
      return a.originOrder.compareTo(b.originOrder);
    }

    return group.reduce((best, book) => compare(book, best) < 0 ? book : best);
  }

  /// 這次搜尋這個來源花的毫秒數；沒量到（0）排在最後。
  int get _searchSpeed => respondTime > 0 ? respondTime : 1 << 31;

  static final _chapterNumberPattern = RegExp(
    r'第\s*([0-9０-９〇零一二三四五六七八九十百千万萬两兩壹贰貳叁參肆伍陆陸柒捌玖拾佰仟亿億]+)\s*[章節节回話话集篇]',
  );

  /// 最新章節標題裡「第 N 章」的 N；讀不出來時為 null。
  /// 搜尋每回來一個書源就重新挑一次代表，每次比較都要讀章節編號；依章名
  /// 記下結果，章名換掉才重算。
  int? get _latestChapterNumber {
    final title = latestChapterTitle;
    if (!identical(title, _chapterNumberTitle) || !_chapterNumberRead) {
      _chapterNumberTitle = title;
      _chapterNumberRead = true;
      final match = _chapterNumberPattern.firstMatch(title ?? '');
      final number = match == null
          ? 0
          : StringUtils.stringToInt(match.group(1));
      _chapterNumber = number > 0 ? number : null;
    }
    return _chapterNumber;
  }

  String? _chapterNumberTitle;
  bool _chapterNumberRead = false;
  int? _chapterNumber;

  /// 複製出一張全新的呈現卡，origins 重置為只含自身來源。
  SearchBook _cloneForCard() {
    return SearchBook(
      bookUrl: bookUrl,
      name: name,
      author: author,
      kind: kind,
      coverUrl: coverUrl,
      intro: intro,
      wordCount: wordCount,
      latestChapterTitle: latestChapterTitle,
      origin: origin,
      originName: originName,
      originOrder: originOrder,
      type: type,
      addTime: addTime,
      variable: variable,
      tocUrl: tocUrl,
      respondTime: respondTime,
    );
  }

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
