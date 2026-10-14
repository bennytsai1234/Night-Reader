import 'dart:async';
import 'dart:convert';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';

import 'reader_v2_location.dart';

class ReaderV2ProgressController {
  ReaderV2ProgressController({
    required this.book,
    required this.repository,
    required this.bookDao,
    this.debounce = const Duration(milliseconds: 400),
  });

  final Book book;
  final ReaderV2ChapterRepository repository;
  final BookDao bookDao;
  final Duration debounce;

  Timer? _timer;
  ReaderV2Location? _pendingLocation;
  Future<void>? _activeFlush;
  bool _disposed = false;

  void schedule(ReaderV2Location location) {
    if (_disposed) return;
    _pendingLocation = location.normalized();
    _timer?.cancel();
    _timer = Timer(debounce, () {
      unawaited(flush());
    });
  }

  Future<void> saveImmediately(ReaderV2Location location) async {
    if (_disposed) return;
    _pendingLocation = location.normalized();
    await flush();
  }

  Future<void> flush() {
    _timer?.cancel();
    final active = _activeFlush;
    if (active != null) {
      return active.then((_) => flush());
    }
    if (_pendingLocation == null) return Future<void>.value();
    _activeFlush = _flushPendingLocations().whenComplete(() {
      _activeFlush = null;
    });
    return _activeFlush!;
  }

  Future<void> _flushPendingLocations() async {
    while (true) {
      final location = _pendingLocation;
      if (location == null) return;
      _pendingLocation = null;
      await _write(location);
    }
  }

  Future<void> _write(ReaderV2Location location) async {
    final normalized = location.normalized(
      chapterCount: repository.chapterCount,
    );
    final content = repository.cachedContent(normalized.chapterIndex);
    // A progress write describes content that is already on screen. Do not
    // turn persistence into a network/content load; enrich it only from the
    // exact materialized chapter already present in the repository cache.
    final persisted = normalized.hasContentIdentity || content == null
        ? normalized
        : normalized.withContentIdentity(
            contentHash: content.contentHash,
            displayText: content.displayText,
          );
    final title = repository.titleFor(normalized.chapterIndex);
    final anchorJson = jsonEncode(persisted.toJson());
    // 閱讀器開著時，檢查更新可能已換上新目錄、章節重新編號（書源在中間
    // 插入或刪除章節）；閱讀器手上仍是開書時的目錄。寫進資料庫的序號依
    // 章節網址換成目前目錄的，下次開書才落在同一章。目錄裡已經沒有這一章
    // 時照閱讀器的序號寫。查序號與寫進度在同一個交易裡，中間不會被換目錄。
    final chapter = repository.chapterAt(normalized.chapterIndex);
    book.chapterIndex = normalized.chapterIndex;
    book.charOffset = normalized.charOffset;
    book.visualOffsetPx = normalized.visualOffsetPx;
    book.durChapterTitle = title;
    book.readerAnchorJson = anchorJson;
    final chapterDao = repository.chapterDao;
    await chapterDao.transaction(() async {
      final storedIndex = chapter == null
          ? null
          : await chapterDao.indexOfUrl(book.bookUrl, chapter.url);
      final persistedIndex = storedIndex ?? normalized.chapterIndex;
      await bookDao.updateProgress(
        book.bookUrl,
        persistedIndex,
        title,
        normalized.charOffset,
        visualOffsetPx: normalized.visualOffsetPx,
        readerAnchorJson: persistedIndex == normalized.chapterIndex
            ? anchorJson
            : jsonEncode(
                persisted.copyWith(chapterIndex: persistedIndex).toJson(),
              ),
      );
    });
    // The DAO write is the commit point for "started reading". Keep the
    // in-memory model behind that boundary so a failed persistence cannot
    // create a second, contradictory truth.
    book.durChapterTime = DateTime.now().millisecondsSinceEpoch;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    // debounce 中的進度不能跟著 dispose 一起丟——閱讀器關閉時把最後一筆
    // 位置寫完（DAO 是 App 級單例，寫入不依賴本控制器存活）。
    if (_pendingLocation != null) {
      unawaited(flush());
    }
  }
}
