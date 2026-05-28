/// Bookmark - 書籤與筆記模型
/// (原 Android data/entities/Bookmark.kt)
class Bookmark {
  int id;
  final int time;
  final String bookName;
  final String bookAuthor;
  int chapterIndex;
  int chapterPos;
  String chapterName;
  String bookUrl;
  String bookText; // 選取的原文內容 (筆記主體)
  String content; // 使用者的評論內容

  Bookmark({
    this.id = 0,
    required this.time,
    this.bookName = '',
    this.bookAuthor = '',
    this.chapterIndex = 0,
    this.chapterPos = 0,
    this.chapterName = '',
    this.bookUrl = '',
    this.bookText = '',
    this.content = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': time,
      'bookName': bookName,
      'bookAuthor': bookAuthor,
      'chapterIndex': chapterIndex,
      'chapterPos': chapterPos,
      'chapterName': chapterName,
      'bookUrl': bookUrl,
      'bookText': bookText,
      'content': content,
    };
  }

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      id: json['id'],
      time: json['time'] ?? DateTime.now().millisecondsSinceEpoch,
      bookName: json['bookName'] ?? '',
      bookAuthor: json['bookAuthor'] ?? '',
      chapterIndex: json['chapterIndex'] ?? 0,
      chapterPos: json['chapterPos'] ?? 0,
      chapterName: json['chapterName'] ?? '',
      bookUrl: json['bookUrl'] ?? '',
      bookText: json['bookText'] ?? '',
      content: json['content'] ?? '',
    );
  }

  Bookmark copyWith({
    int? id,
    int? time,
    String? bookName,
    String? bookAuthor,
    int? chapterIndex,
    int? chapterPos,
    String? chapterName,
    String? bookUrl,
    String? bookText,
    String? content,
  }) {
    return Bookmark(
      id: id ?? this.id,
      time: time ?? this.time,
      bookName: bookName ?? this.bookName,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterPos: chapterPos ?? this.chapterPos,
      chapterName: chapterName ?? this.chapterName,
      bookUrl: bookUrl ?? this.bookUrl,
      bookText: bookText ?? this.bookText,
      content: content ?? this.content,
    );
  }
}
