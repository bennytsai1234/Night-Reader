enum ReaderChapterContentStatus {
  notReady(0),
  ready(1),
  failed(2);

  const ReaderChapterContentStatus(this.code);

  final int code;

  static ReaderChapterContentStatus fromCode(int code) {
    return switch (code) {
      1 => ReaderChapterContentStatus.ready,
      2 => ReaderChapterContentStatus.failed,
      _ => ReaderChapterContentStatus.notReady,
    };
  }
}

class ReaderChapterContentEntry {
  const ReaderChapterContentEntry({
    required this.contentKey,
    required this.origin,
    required this.bookUrl,
    required this.chapterUrl,
    required this.chapterIndex,
    required this.status,
    this.content,
    this.failureMessage,
    required this.updatedAt,
  });

  final String contentKey;
  final String origin;
  final String bookUrl;
  final String chapterUrl;
  final int chapterIndex;
  final ReaderChapterContentStatus status;
  final String? content;
  final String? failureMessage;
  final int updatedAt;

  bool get isReady => status == ReaderChapterContentStatus.ready;
  bool get isFailed => status == ReaderChapterContentStatus.failed;
  bool get hasDisplayContent => (content ?? '').trim().isNotEmpty;

  factory ReaderChapterContentEntry.fromJson(Map<String, dynamic> json) {
    return ReaderChapterContentEntry(
      contentKey: json['contentKey'] ?? '',
      origin: json['origin'] ?? '',
      bookUrl: json['bookUrl'] ?? '',
      chapterUrl: json['chapterUrl'] ?? '',
      chapterIndex: json['chapterIndex'] ?? 0,
      status: ReaderChapterContentStatus.fromCode(json['status'] ?? 0),
      content: json['content'],
      failureMessage: json['failureMessage'],
      updatedAt: json['updatedAt'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contentKey': contentKey,
      'origin': origin,
      'bookUrl': bookUrl,
      'chapterUrl': chapterUrl,
      'chapterIndex': chapterIndex,
      'status': status.code,
      'content': content,
      'failureMessage': failureMessage,
      'updatedAt': updatedAt,
    };
  }
}
