/// BookProgress - 書籍進度同步模型
/// (原 Android data/entities/BookProgress.kt)
class BookProgress {
  final String name;
  final String author;
  final int chapterIndex;
  final int charOffset;
  final double visualOffsetPx;
  final String durChapterTitle;
  final int durChapterTime;

  BookProgress({
    required this.name,
    required this.author,
    required this.chapterIndex,
    required this.charOffset,
    this.visualOffsetPx = 0.0,
    required this.durChapterTitle,
    required this.durChapterTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'author': author,
      'chapterIndex': chapterIndex,
      'charOffset': charOffset,
      'visualOffsetPx': _normalizeVisualOffsetPx(visualOffsetPx),
      'durChapterTitle': durChapterTitle,
      'durChapterTime': durChapterTime,
    };
  }

  factory BookProgress.fromJson(Map<String, dynamic> json) {
    return BookProgress(
      name: json['name'] ?? '',
      author: json['author'] ?? '',
      chapterIndex: json['chapterIndex'] ?? 0,
      charOffset: json['charOffset'] ?? 0,
      visualOffsetPx: _normalizeVisualOffsetPx(
        _toDouble(json['visualOffsetPx']),
      ),
      durChapterTitle: json['durChapterTitle'] ?? '',
      durChapterTime: json['durChapterTime'] ?? 0,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double _normalizeVisualOffsetPx(double value) {
    if (!value.isFinite || value.isNaN) return 0.0;
    return value.clamp(-80.0, 120.0).toDouble();
  }
}
