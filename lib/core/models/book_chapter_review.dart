/// BookChapterReview - 章節段評模型
/// (原 Android data/entities/BookChapterReview.kt)
class BookChapterReview {
  int bookId;
  int chapterId;
  String summaryUrl;

  BookChapterReview({
    this.bookId = 0,
    this.chapterId = 0,
    this.summaryUrl = '',
  });

  Map<String, dynamic> toJson() {
    return {'bookId': bookId, 'chapterId': chapterId, 'summaryUrl': summaryUrl};
  }

  factory BookChapterReview.fromJson(Map<String, dynamic> json) {
    return BookChapterReview(
      bookId: json['bookId'] ?? 0,
      chapterId: json['chapterId'] ?? 0,
      summaryUrl: json['summaryUrl'] ?? '',
    );
  }
}
