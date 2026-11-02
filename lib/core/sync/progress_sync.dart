import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 閱讀進度的同步：書架上一本書一筆，用書名加作者對上另一台的同一本書，
/// 兩台用不同書源也對得上。記第幾章第幾個字，螢幕大小不同也落在同一個字
/// （ADR 0039）。書不在書架上就留在雲端；閱讀器開著的書由閱讀器自己跳。
class ProgressSync extends SyncKind {
  ProgressSync({
    required this.bookDao,
    required this.chapterDao,
    bool Function(String key)? isOpen,
  }) : _isOpen = isOpen ?? _never;

  static const String kind = 'progress';

  final BookDao bookDao;
  final ChapterDao chapterDao;
  final bool Function(String key) _isOpen;

  static bool _never(String key) => false;

  @override
  String get name => kind;

  @override
  bool get hasOwnTime => true;

  /// 書從書架移除由書架的同步負責，進度留在雲端。
  @override
  bool get syncsDeletion => false;

  static String keyOf(Book book) => '${book.name}\t${book.author}';

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final entry in (await shelfBooks()).entries)
      entry.key: recordOf(entry.value),
  };

  @override
  String fingerprint(SyncRecord record) => fingerprintOf(record);

  @override
  bool canApply(String key, SyncRecord? local) =>
      local != null && !_isOpen(key);

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final books = await shelfBooks();
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      // 查書架的這段時間剛被打開的，留給閱讀器。
      if (record.deleted || _isOpen(key)) continue;
      if (books[key] case final book?) {
        applied[key] = await applyTo(book, record);
      }
    }
    // 書卡的進度線與書架的順序跟著換。
    if (applied.isNotEmpty) AppEventBus().fire(AppEventBus.upBookshelf);
    return applied;
  }

  /// 時間用「位置最後移動的時間」，不用最近閱讀時間：開書沒翻頁也會更新
  /// 後者，拿它比新舊，沒動過的這台會蓋掉別台真的讀過的進度。
  static SyncRecord recordOf(Book book) => SyncRecord(
    time: book.progressTime,
    data: {
      'chapterIndex': book.chapterIndex,
      'charOffset': book.charOffset,
      'chapterTitle': book.durChapterTitle ?? '',
    },
  );

  /// 進度的內容是「哪一章（章名）的第幾個字」。章節序號只是這台目錄裡的
  /// 座標：書源在前面插一章、序號跟著變，讀到的地方沒變，不算改過；沒有
  /// 章名時才看序號。
  static String fingerprintOf(SyncRecord record) {
    if (record.deleted) return record.fingerprint;
    final title = record.data['chapterTitle'];
    final hasTitle = title is String && title.trim().isNotEmpty;
    return SyncRecord.fingerprintOf({
      if (hasTitle) 'chapterTitle': title.trim(),
      if (!hasTitle) 'chapterIndex': record.data['chapterIndex'],
      'charOffset': record.data['charOffset'],
    });
  }

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
  Future<SyncRecord> applyTo(Book book, SyncRecord remote) async {
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
