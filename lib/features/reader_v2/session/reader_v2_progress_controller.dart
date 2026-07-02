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
    final title = repository.titleFor(normalized.chapterIndex);
    book.chapterIndex = normalized.chapterIndex;
    book.charOffset = normalized.charOffset;
    book.visualOffsetPx = normalized.visualOffsetPx;
    book.durChapterTitle = title;
    book.readerAnchorJson = jsonEncode(normalized.toJson());
    await bookDao.updateProgress(
      book.bookUrl,
      normalized.chapterIndex,
      title,
      normalized.charOffset,
      visualOffsetPx: normalized.visualOffsetPx,
      readerAnchorJson: jsonEncode(normalized.toJson()),
    );
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
