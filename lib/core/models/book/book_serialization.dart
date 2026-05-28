import 'dart:convert';
import 'book_base.dart';

/// Book 序列化與複制擴展
extension BookSerialization on BookBase {
  static int toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double toVisualOffsetPx(dynamic value) {
    final parsed = toDouble(value);
    if (!parsed.isFinite || parsed.isNaN) return 0.0;
    return parsed.clamp(-80.0, 120.0).toDouble();
  }

  // 由於 factory 不能在 extension 中，這裡將其定義為普通靜態方法或讓子類調用
  static Map<String, dynamic> bookToJson(BookBase book) {
    return {
      'bookUrl': book.bookUrl,
      'tocUrl': book.tocUrl,
      'origin': book.origin,
      'originName': book.originName,
      'name': book.name,
      'author': book.author,
      'kind': book.kind,
      'customTag': book.customTag,
      'coverUrl': book.coverUrl,
      'coverLocalPath': book.coverLocalPath,
      'customCoverUrl': book.customCoverUrl,
      'customCoverLocalPath': book.customCoverLocalPath,
      'intro': book.intro,
      'customIntro': book.customIntro,
      'charset': book.charset,
      'type': book.type,
      'group': book.group,
      'latestChapterTitle': book.latestChapterTitle,
      'latestChapterTime': book.latestChapterTime,
      'lastCheckTime': book.lastCheckTime,
      'lastCheckCount': book.lastCheckCount,
      'totalChapterNum': book.totalChapterNum,
      'durChapterTitle': book.durChapterTitle,
      'chapterIndex': book.chapterIndex,
      'charOffset': book.charOffset,
      'visualOffsetPx': toVisualOffsetPx(book.visualOffsetPx),
      'readerAnchorJson': book.readerAnchorJson,
      'durChapterTime': book.durChapterTime,
      'wordCount': book.wordCount,
      'canUpdate': book.canUpdate ? 1 : 0,
      'order': book.order,
      'originOrder': book.originOrder,
      'variable': book.variable,
      'readConfig':
          book.readConfig != null
              ? jsonEncode(book.readConfig!.toJson())
              : null,
      'syncTime': book.syncTime,
      'isInBookshelf': book.isInBookshelf ? 1 : 0,
    };
  }
}
