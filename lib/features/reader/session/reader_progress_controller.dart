import 'dart:convert';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';

import 'progress_write_queue.dart';
import 'reader_location.dart';

class ReaderProgressController {
  ReaderProgressController({
    required this.book,
    required this.repository,
    required this.bookDao,
    this.debounce = const Duration(milliseconds: 400),
  });

  final Book book;
  final ReaderChapterRepository repository;
  final BookDao bookDao;
  final Duration debounce;

  late final _queue = ProgressWriteQueue<ReaderLocation>(
    write: _write,
    debounce: debounce,
  );
  bool _disposed = false;
  bool _retired = false;

  void retire() {
    _retired = true;
    _queue.discardPending();
  }

  void resume() {
    _retired = false;
  }

  void schedule(ReaderLocation location) {
    if (_disposed || _retired) return;
    _queue.schedule(location.normalized());
  }

  Future<void> saveImmediately(ReaderLocation location) async {
    if (_disposed || _retired) return;
    await _queue.saveImmediately(location.normalized());
  }

  Future<void> flush() => _retired ? Future<void>.value() : _queue.flush();

  Future<void> _write(ReaderLocation location) async {
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
    final chapterDao = repository.chapterDao;
    int? movedAt;
    await chapterDao.transaction(() async {
      final storedIndex = chapter == null
          ? null
          : await chapterDao.indexOfUrl(book.bookUrl, chapter.url);
      final persistedIndex = storedIndex ?? normalized.chapterIndex;
      movedAt = await bookDao.updateProgress(
        book.bookUrl,
        persistedIndex,
        title,
        persisted.charOffset,
        visualOffsetPx: persisted.visualOffsetPx,
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
    book.chapterIndex = normalized.chapterIndex;
    book.charOffset = persisted.charOffset;
    book.visualOffsetPx = persisted.visualOffsetPx;
    book.durChapterTitle = title;
    book.readerAnchorJson = anchorJson;
    book.durChapterTime = DateTime.now().millisecondsSinceEpoch;
    // 記憶體裡的書之後可能整筆寫回資料庫，位置移動的時間要跟著。
    if (movedAt case final time?) book.progressTime = time;
  }

  void dispose() {
    _disposed = true;
    // 閱讀器關閉時把最後一筆位置寫完。
    if (!_retired) _queue.flushInBackground();
  }
}
