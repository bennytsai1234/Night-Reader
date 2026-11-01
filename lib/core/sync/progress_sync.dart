import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';

import 'sync_records.dart';

/// 閱讀進度的同步：書架上一本書一筆，用書名加作者對上另一台的同一本書，
/// 兩台用不同書源也對得上。記第幾章第幾個字，螢幕大小不同也落在同一個字
/// （ADR 0039）。
class ProgressSync {
  ProgressSync({required this.bookDao, required this.chapterDao});

  static const String kind = 'progress';
  static const String fileName = 'progress.json';

  final BookDao bookDao;
  final ChapterDao chapterDao;

  static String keyOf(Book book) => '${book.name}\t${book.author}';

  static SyncRecord recordOf(Book book) => SyncRecord(
    time: book.durChapterTime,
    data: {
      'chapterIndex': book.chapterIndex,
      'charOffset': book.charOffset,
      'chapterTitle': book.durChapterTitle ?? '',
    },
  );

  /// 書架上每個書名加作者最近讀的那一本。同一本書從兩個書源都加進書架時，
  /// 同步只跟著最近讀的那本。
  Future<Map<String, Book>> shelfBooks() async {
    final books = <String, Book>{};
    for (final book in await bookDao.getInBookshelf()) {
      final key = keyOf(book);
      final existing = books[key];
      if (existing == null || book.durChapterTime > existing.durChapterTime) {
        books[key] = book;
      }
    }
    return books;
  }

  /// 把 [remote] 套用到 [book]，傳回套用後這台的紀錄（章節序號照這台的
  /// 目錄對過）。
  Future<SyncRecord> apply(Book book, SyncRecord remote) async {
    final position = SyncedProgress.fromRecord(remote);
    final titles = await chapterDao.titlesByBook(book.bookUrl);
    final index = position.chapterIndexIn(titles);
    final title = titles.isEmpty ? position.chapterTitle : titles[index];
    await bookDao.applySyncedProgress(
      book.bookUrl,
      chapterIndex: index,
      chapterTitle: title,
      charOffset: position.charOffset,
      time: remote.time,
    );
    return SyncRecord(
      time: remote.time,
      data: {
        'chapterIndex': index,
        'charOffset': position.charOffset,
        'chapterTitle': title,
      },
    );
  }
}

/// 另一台同步來的一本書的進度。
class SyncedProgress {
  const SyncedProgress({
    required this.chapterIndex,
    required this.charOffset,
    required this.chapterTitle,
    required this.time,
  });

  factory SyncedProgress.fromRecord(SyncRecord record) {
    int asInt(Object? value) => value is int && value >= 0 ? value : 0;
    final title = record.data['chapterTitle'];
    return SyncedProgress(
      chapterIndex: asInt(record.data['chapterIndex']),
      charOffset: asInt(record.data['charOffset']),
      chapterTitle: title is String ? title : '',
      time: record.time,
    );
  }

  final int chapterIndex;
  final int charOffset;
  final String chapterTitle;
  final int time;

  /// 這台目錄（[titles]）裡對應的章節序號。兩台的書源或目錄版本不同時，
  /// 同一個序號可能是不同章：先找同名的章（離原序號最近的那個），找不到才
  /// 照序號，超出目錄就停在最後一章。
  int chapterIndexIn(List<String> titles) {
    if (titles.isEmpty) return chapterIndex;
    final wanted = chapterTitle.trim();
    if (wanted.isNotEmpty) {
      if (chapterIndex < titles.length &&
          titles[chapterIndex].trim() == wanted) {
        return chapterIndex;
      }
      int? best;
      for (var i = 0; i < titles.length; i++) {
        if (titles[i].trim() != wanted) continue;
        if (best == null ||
            (i - chapterIndex).abs() < (best - chapterIndex).abs()) {
          best = i;
        }
      }
      if (best != null) return best;
    }
    return chapterIndex.clamp(0, titles.length - 1);
  }
}
