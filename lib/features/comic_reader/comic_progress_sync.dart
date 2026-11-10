import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';

import 'comic_strip_view.dart';

/// 漫畫閱讀器這一頭的進度同步，規則同文字閱讀器（ADR 0039、0052）：
/// - 接著上次讀的地方開書時，開 App 的那次同步還沒做完就等它（最多
///   [openGrace]），再照這台資料庫裡的位置開。
/// - 回到前景時抓這本書的雲端進度，比這台新、而且從那之後沒捲過，就跳過去；
///   同一話差 [nearPages] 張以內不跳。
/// - 退到背景、離開閱讀器時存好進度再上傳。
class ComicProgressSync {
  ComicProgressSync({
    required this.book,
    required this.bookDao,
    required this.current,
    required this.flush,
    required this.titles,
    required this.ids,
    required this.jumpTo,
    this.resumes = true,
    SyncService? sync,
  }) : _sync = sync ?? SyncService.instance;

  static const Duration openGrace = Duration(milliseconds: 500);

  /// 同一話差這麼多張以內不跳（使用者 2026-11-09 選，對應文字書的 100 字）。
  static const int nearPages = 1;

  final Book book;
  final BookDao bookDao;

  /// 畫面上讀到哪；還沒開好是 null。
  final ComicLocation? Function() current;

  /// 把還沒存的進度存好。
  final Future<void> Function() flush;

  /// 這台目錄的章名。
  final List<String> Function() titles;

  /// 這台每一話的章指紋（目錄的網址）：本地漫畫照它對另一台的那一話。
  final List<String> Function() ids;

  /// 跳到另一台的位置。
  final void Function(int chapterIndex, int pageIndex) jumpTo;

  /// 接著上次讀的地方開書（不是從目錄或詳情點了某一話）。
  final bool resumes;
  final SyncService _sync;

  AppLifecycleListener? _lifecycle;
  bool _marked = false;
  bool _opened = false;
  bool _disposed = false;

  void start() {
    if (!resumes) _markOpen();
    _lifecycle = AppLifecycleListener(onShow: _onShow, onHide: _onHide);
  }

  void _markOpen() {
    if (_marked || _disposed) return;
    _marked = true;
    _sync.openBook(book);
  }

  /// 開書前呼叫：要開在哪裡（這台資料庫裡、等過同步的位置）；從目錄點的
  /// 或讀不到時是 null。
  Future<({int chapterIndex, int pageIndex, double fraction})?>
  openLocation() async {
    if (!resumes) return null;
    final ready = _sync.progressReady;
    if (ready != null) {
      await Future.any([ready, Future<void>.delayed(openGrace)]);
    }
    if (_disposed) return null;
    _markOpen();
    try {
      final stored = await bookDao.getByUrl(book.bookUrl);
      if (stored == null) return null;
      return (
        chapterIndex: stored.chapterIndex,
        pageIndex: stored.charOffset,
        fraction: stored.visualOffsetPx,
      );
    } catch (error, stackTrace) {
      AppLog.e('讀閱讀紀錄失敗', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  /// 開書定位完成時呼叫。
  void bookOpened() {
    _opened = true;
    _markOpen();
  }

  void _onShow() => unawaited(_pullAfterResume());

  Future<void> _pullAfterResume() async {
    if (!_opened || _disposed) return;
    await flush();
    final since = current();
    if (since == null) return;
    final pulled = await _sync.pullProgress(book.bookUrl);
    if (pulled == null || !pulled.isCurrent || _disposed) return;
    final now = current();
    if (now == null ||
        now.chapterIndex != since.chapterIndex ||
        now.pageIndex != since.pageIndex) {
      return;
    }
    final index = pulled.progress.chapterIndexIn(titles(), ids: ids());
    final page = pulled.progress.charOffset;
    if (shouldJump(now, index, page)) jumpTo(index, page);
    await flush();
    if (_disposed) return;
    await pulled.commit(
      ProgressSync.recordOf(
        book,
        chapterId: ProgressSync.chapterIdOf(book, ids()),
      ),
    );
  }

  /// 另一台在第 [chapterIndex] 話第 [pageIndex] 張，這台要不要跳過去。
  static bool shouldJump(ComicLocation here, int chapterIndex, int pageIndex) =>
      chapterIndex != here.chapterIndex ||
      (pageIndex - here.pageIndex).abs() > nearPages;

  void _onHide() => _upload();

  void _upload() {
    unawaited(
      flush()
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              AppLog.e('存進度失敗', error: error, stackTrace: stackTrace);
            },
          )
          .whenComplete(_sync.requestSyncProgressFirst),
    );
  }

  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    if (_marked) _sync.closeBook(book);
    _upload();
  }
}
