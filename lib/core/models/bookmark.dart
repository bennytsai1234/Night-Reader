import 'json_read.dart';

/// 書籤：在某一句留的記號，之後從清單一點就跳回去。
///
/// 位置和閱讀進度同一套：第幾章（章名）的第幾個字，跳回時照目前的排版
/// 算出在畫面哪裡；[anchor] 另記那個字前後的原文，換了書源、正文有出入時
/// 照它找回同一句（`ReaderV2Location`）。
///
/// 書籤跟著書名加作者，不跟書源：換源、另一台用別的書源讀同一本書，都還
/// 是這本書的書籤（同步認書的方式，ADR 0039）。
class Bookmark {
  Bookmark({
    required this.id,
    required this.bookName,
    this.bookAuthor = '',
    this.chapterIndex = 0,
    this.chapterTitle = '',
    this.charOffset = 0,
    this.anchor,
    this.excerpt = '',
  });

  /// 這筆書籤的編號：建立時間的毫秒乘 1000 加隨機三位數
  /// （`BookmarkDao.newId`），兩台各自新增的不會撞號；2026-09 以前備份裡
  /// 的書籤是建立時間的毫秒。
  final int id;
  final String bookName;
  final String bookAuthor;

  /// 這台目錄裡的章節序號。目錄變了（書源插章、換源、另一台的書源）時以
  /// [chapterTitle] 為準，序號只在找不到同名章時用。
  final int chapterIndex;
  final String chapterTitle;

  /// 章內第幾個字（正文顯示文字的位置）。
  final int charOffset;

  /// `ReaderV2Location` 的 JSON，含這個位置綁定的正文與前後原文。
  final String? anchor;

  /// 書籤那一句（選得比一句長時是選到的全部），清單上顯示它。
  final String excerpt;

  Bookmark copyWith({
    int? id,
    String? bookName,
    String? bookAuthor,
    int? chapterIndex,
    String? chapterTitle,
    int? charOffset,
    String? anchor,
  }) => Bookmark(
    id: id ?? this.id,
    bookName: bookName ?? this.bookName,
    bookAuthor: bookAuthor ?? this.bookAuthor,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    charOffset: charOffset ?? this.charOffset,
    anchor: anchor ?? this.anchor,
    excerpt: excerpt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookName': bookName,
    'bookAuthor': bookAuthor,
    'chapterIndex': chapterIndex,
    'chapterTitle': chapterTitle,
    'charOffset': charOffset,
    'anchor': ?anchor,
    'excerpt': excerpt,
  };

  /// 也讀得懂 2026-09 以前的備份（`bookmark.json`）：那時的編號是流水號、
  /// 建立時間在 `time`，位置與內容是 `chapterPos`、`chapterName`、`bookText`。
  factory Bookmark.fromJson(Map<String, dynamic> json) {
    String readString(String key, [String? legacy]) {
      final value = json[key] ?? (legacy == null ? null : json[legacy]);
      return value is String ? value : '';
    }

    final legacyTime = json['time'];
    final anchor = json['anchor'];
    return Bookmark(
      id: legacyTime != null
          ? readJsonInt(legacyTime, fallback: 0)
          : readJsonInt(json['id'], fallback: 0),
      bookName: readString('bookName'),
      bookAuthor: readString('bookAuthor'),
      chapterIndex: readJsonInt(json['chapterIndex'], fallback: 0),
      chapterTitle: readString('chapterTitle', 'chapterName'),
      charOffset: readJsonInt(
        json['charOffset'] ?? json['chapterPos'],
        fallback: 0,
      ),
      anchor: anchor is String && anchor.isNotEmpty ? anchor : null,
      excerpt: readString('excerpt', 'bookText'),
    );
  }
}
