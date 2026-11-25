import '../json_read.dart';

/// 標註的顏色。存名字（[name]），同步與備份看得懂；讀不懂的當成 [amber]。
enum HighlightColor {
  amber('黃'),
  green('綠'),
  blue('藍'),
  pink('粉'),
  purple('紫');

  const HighlightColor(this.label);

  final String label;

  static HighlightColor parse(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return amber;
  }
}

/// 標註畫在字上的樣子：鋪底色或畫底線。
enum HighlightStyle {
  fill('底色'),
  underline('底線');

  const HighlightStyle(this.label);

  final String label;

  static HighlightStyle parse(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fill;
  }
}

/// 標註：正文裡畫上底色或底線的一段字，可以附一段自己的話（[note]），之後
/// 在清單裡看、匯出。
///
/// 書籤記位置，標註記內容：[quote] 是畫到的那段字本身，清單與匯出照它；
/// 位置和書籤、閱讀進度同一套（第幾章的第幾個字加錨點，ADR 0042），正文
/// 變了照錨點找回開頭，再往後畫 [quote] 那麼長。
///
/// 跟著書名加作者，不跟書源（同書籤，ADR 0044）。
class Highlight {
  Highlight({
    required this.id,
    required this.bookName,
    this.bookAuthor = '',
    this.chapterIndex = 0,
    this.chapterTitle = '',
    this.charOffset = 0,
    this.anchor,
    this.quote = '',
    this.color = HighlightColor.amber,
    this.style = HighlightStyle.fill,
    this.note = '',
  });

  /// 編號的配法同書籤（`BookmarkDao.newId`）：兩台各自新增的不撞號。
  final int id;
  final String bookName;
  final String bookAuthor;

  /// 這台目錄裡的章節序號；目錄變了以 [chapterTitle] 為準。
  final int chapterIndex;
  final String chapterTitle;

  /// 標註開頭是章內第幾個字（正文顯示文字的位置）。
  final int charOffset;

  /// 開頭那個字的 `ReaderLocation` JSON，含綁定的正文與前後原文。
  final String? anchor;

  /// 畫到的那段字。
  final String quote;
  final HighlightColor color;
  final HighlightStyle style;

  /// 備忘：標註旁附的一段自己的話；沒寫是空字串。
  final String note;

  /// 標註結尾（不含）是章內第幾個字。
  int get endOffset => charOffset + quote.length;

  Highlight copyWith({
    int? id,
    String? bookName,
    String? bookAuthor,
    int? chapterIndex,
    String? chapterTitle,
    HighlightColor? color,
    HighlightStyle? style,
    String? note,
  }) => Highlight(
    id: id ?? this.id,
    bookName: bookName ?? this.bookName,
    bookAuthor: bookAuthor ?? this.bookAuthor,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    charOffset: charOffset,
    anchor: anchor,
    quote: quote,
    color: color ?? this.color,
    style: style ?? this.style,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookName': bookName,
    'bookAuthor': bookAuthor,
    'chapterIndex': chapterIndex,
    'chapterTitle': chapterTitle,
    'charOffset': charOffset,
    'anchor': ?anchor,
    'quote': quote,
    'color': color.name,
    'style': style.name,
    'note': note,
  };

  /// Legado 備份裡寫了附註的書籤（`bookmark.json` 一筆，有 `content`）換成的
  /// 標註：畫在書籤記的原文（`bookText`，選字加的是選到的字、從選單加的是
  /// 那一頁的字）上，附註是備忘。沒有錨點：位置照 Legado 的算法記，閱讀器
  /// 畫之前照原文核對。編號是建立時間（`time`）的毫秒乘 1000，和這台畫的
  /// 標註（`BookmarkDao.newId`）一起照建立時間排。夜讀 2026-09 以前的備份
  /// 書籤欄位同 Legado，附註一樣是讀者寫的話，也走這裡。不是這種書籤（現在
  /// 的夜讀書籤有 `excerpt`）、沒有附註或沒有原文時是 null，照書籤讀。
  static Highlight? fromLegadoBookmark(Map<String, dynamic> json) {
    if (json.containsKey('excerpt')) return null;
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    final note = readString('content').trim();
    final quote = readString('bookText');
    final time = readJsonInt(json['time'], fallback: 0);
    final bookName = readString('bookName');
    if (note.isEmpty || quote.trim().isEmpty || time <= 0 || bookName.isEmpty) {
      return null;
    }
    return Highlight(
      id: time * 1000,
      bookName: bookName,
      bookAuthor: readString('bookAuthor'),
      chapterIndex: readJsonInt(json['chapterIndex'], fallback: 0),
      chapterTitle: readString('chapterName'),
      charOffset: readJsonInt(json['chapterPos'], fallback: 0),
      quote: quote,
      note: note,
    );
  }

  factory Highlight.fromJson(Map<String, dynamic> json) {
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    final anchor = json['anchor'];
    return Highlight(
      id: readJsonInt(json['id'], fallback: 0),
      bookName: readString('bookName'),
      bookAuthor: readString('bookAuthor'),
      chapterIndex: readJsonInt(json['chapterIndex'], fallback: 0),
      chapterTitle: readString('chapterTitle'),
      charOffset: readJsonInt(json['charOffset'], fallback: 0),
      anchor: anchor is String && anchor.isNotEmpty ? anchor : null,
      quote: readString('quote'),
      color: HighlightColor.parse(json['color']),
      style: HighlightStyle.parse(json['style']),
      note: readString('note'),
    );
  }
}
