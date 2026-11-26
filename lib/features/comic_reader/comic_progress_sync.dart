import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/reading_upload_pacer.dart';
import 'package:night_reader/core/sync/sync_service.dart';

import 'comic_strip_view.dart';

/// 漫畫閱讀器這一頭的進度同步，規則同文字閱讀器（ADR 0039、0052）：雲端
/// 那筆比較新、而且讀到的地方在這台後面，才接。
/// - 接著上次讀的地方開書時，點書當下就先抓這本書的雲端進度；換頁動畫播完
///   最多等 [openGrace]：等到了而且比這台新就照它開；等不及先照這台的位置
///   開，正文已經在畫面上之後才到的話先問要不要跳過去，不自己跳。從目錄或
///   詳情點了某一話開書不抓。
/// - 回到前景時再抓一次，比這台新、而且抓的途中沒捲過，就問要不要跳到那一
///   話那一張；沒按就不跳、不記成同步過。位置完全一樣才不動。
/// - 讀書途中畫面停住時上傳（[ReadingUploadPacer]）；退到背景、離開閱讀器
///   時存好進度再上傳。
class ComicProgressSync {
  ComicProgressSync({
    required this.book,
    required this.bookDao,
    required this.current,
    required this.flush,
    required this.titles,
    required this.ids,
    required this.jumpTo,
    required this.onProgressSuggestion,
    this.resumes = true,
    this._busy,
    SyncService? sync,
  }) : _sync = sync ?? SyncService.instance;

  static const Duration openGrace = Duration(milliseconds: 500);

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

  /// 跳到另一台的位置；傳回有沒有落在那一話那一張（那一話載不下來、換到
  /// 別話就是 false）。
  final Future<bool> Function(int chapterIndex, int pageIndex) jumpTo;

  /// 正文已經在畫面上之後才抓到比這台新的進度：交給頁面問要不要跳過去，
  /// 按了才執行傳進去的動作（會再確認讀者沒動過、還是同一筆）。
  final void Function(Future<void> Function() jump) onProgressSuggestion;

  /// 接著上次讀的地方開書（不是從目錄或詳情點了某一話）。
  final bool resumes;
  final SyncService _sync;

  /// 畫面還在動（自動捲動中）。
  final bool Function()? _busy;

  late final ReadingUploadPacer _pacer = ReadingUploadPacer(
    upload: _upload,
    busy: _busy,
  );

  AppLifecycleListener? _lifecycle;

  /// 點書當下就開始抓的那一次；換頁動畫播完的 [openLocation] 改用它。
  Future<PulledProgress?>? _openingPull;

  /// 開書時等不及的那次抓取：進度晚到時，書已經開在這台的位置了。
  Future<PulledProgress?>? _lateProgress;

  /// 問過幾次要不要跳：換下一則之後，前一個按鈕按了也不動。
  int _suggestions = 0;
  bool _marked = false;
  bool _opened = false;
  bool _disposed = false;
  bool _foreground = true;

  /// 開書失敗後重試會再呼叫一次，只註冊一次。
  void start() {
    if (!resumes) {
      _markOpen();
    } else {
      // 點書當下就開始抓，換頁動畫播完時直接用這一次，多賺動畫的時間。
      _openingPull ??= _sync.pullProgress(book.bookUrl);
    }
    _lifecycle ??= AppLifecycleListener(onShow: _onShow, onHide: _onHide);
    _sync.uploadsOnHide(this, true);
  }

  /// 頁面一打開就先抓雲端進度；還沒到換頁動畫播完時不用等。
  void prefetch() {
    if (!resumes || _openingPull != null) return;
    _openingPull = _sync.pullProgress(book.bookUrl);
  }

  void _markOpen() {
    if (_marked || _disposed) return;
    _marked = true;
    _sync.openBook(book);
  }

  /// 開書前呼叫：要開在哪裡（這台資料庫裡的位置，抓得到比這台新的雲端
  /// 進度時先寫進去）；從目錄點的或讀不到時是 null。
  Future<({int chapterIndex, int pageIndex, double fraction})?>
  openLocation() async {
    if (!resumes) return null;
    // 先記成開著：背景的同步不再改這本，由這裡抓的那一筆決定。
    _markOpen();
    final pulling = _openingPull ?? _sync.pullProgress(book.bookUrl);
    _openingPull = null;
    if (await settlesWithin(pulling, openGrace)) {
      if (_disposed) return null;
      try {
        await (await pulling)?.applyBeforeOpen();
      } catch (error, stackTrace) {
        AppLog.e('接上雲端進度失敗', error: error, stackTrace: stackTrace);
      }
    } else {
      _lateProgress = pulling;
    }
    if (_disposed) return null;
    try {
      final stored = await bookDao.getByUrl(book.bookUrl);
      if (stored == null) return null;
      // 記憶體裡的書之後可能整筆寫回資料庫，位置移動的時間要跟著。
      book.progressTime = stored.progressTime;
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
    if (_foreground) _pacer.start();
    final late = _lateProgress;
    _lateProgress = null;
    if (late != null) unawaited(_catchUp(late));
  }

  /// 畫面上的位置變了（捲動中也會一直呼叫）。
  void located() => _pacer.activity();

  /// 存進度時位置真的移動了。
  void moved() => _pacer.moved();

  /// 開書時雲端進度還沒抓到、先照這台的位置開了：抓到時讀者還沒捲就問
  /// 要不要跳過去。
  Future<void> _catchUp(Future<PulledProgress?> pulling) async {
    final since = current();
    if (since == null) return;
    await _offerCatchUp(await pulling, since);
  }

  void _onShow() {
    _foreground = true;
    if (_opened && !_disposed) _pacer.start();
    unawaited(_pullAfterResume());
  }

  Future<void> _pullAfterResume() async {
    if (!_opened || _disposed) return;
    try {
      await flush();
    } catch (error, stackTrace) {
      AppLog.e('存進度失敗', error: error, stackTrace: stackTrace);
    }
    final since = current();
    if (since == null) return;
    await _offerCatchUp(await _sync.pullProgress(book.bookUrl), since);
  }

  /// 正文已經在畫面上才抓到比這台新的進度：位置一樣就照舊記成同步過；
  /// 不一樣就先問要不要跳過去，不自己跳。
  Future<void> _offerCatchUp(
    PulledProgress? pulled,
    ComicLocation since,
  ) async {
    if (pulled == null || !pulled.isCurrent || _disposed) return;
    final now = current();
    if (now == null || !sameSpot(now, since)) return;
    final index = pulled.progress.chapterIndexIn(
      titles(),
      ids: ids(),
      reversed: book.getReverseToc(),
    );
    final page = pulled.progress.charOffset;
    if (shouldJump(now, index, page)) {
      final suggestion = ++_suggestions;
      onProgressSuggestion(() async {
        // 換過一則提示（讀者又動了、回到前景又抓到）：前一個按鈕不再有用。
        if (suggestion != _suggestions) return;
        await _jumpIfStill(pulled, since);
      });
      return;
    }
    await _jumpIfStill(pulled, since);
  }

  /// 按了「跳過去」：讀者從 [since] 之後沒捲過、還是同一筆、同一個同步
  /// 空間，就跳到那一話那一張，存好、記成同步過。
  Future<void> _jumpIfStill(PulledProgress? pulled, ComicLocation since) async {
    if (pulled == null || !pulled.isCurrent || _disposed) return;
    final now = current();
    if (now == null || !sameSpot(now, since)) return;
    final index = pulled.progress.chapterIndexIn(
      titles(),
      ids: ids(),
      reversed: book.getReverseToc(),
    );
    final page = pulled.progress.charOffset;
    if (shouldJump(now, index, page)) {
      // 那一話載不下來、不能讀而換到別話、張數不夠：沒接上，不記成同步過，
      // 下次回到前景再抓。
      if (!await jumpTo(index, page) || _disposed) return;
    }
    try {
      await flush();
      if (_disposed) return;
      // 跳轉存檔記的是這台的時間；記成不比雲端那一筆早，之後往前讀的才比
      // 另一台記的新（`BookDao.markProgressSynced`）。
      final time = await bookDao.markProgressSynced(
        book.bookUrl,
        syncedTime: pulled.progress.time,
      );
      if (time == null || _disposed) return;
      book.progressTime = time;
    } catch (error, stackTrace) {
      AppLog.e('存進度失敗', error: error, stackTrace: stackTrace);
      return;
    }
    await pulled.commit(
      ProgressSync.recordOf(
        book,
        chapterId: ProgressSync.chapterIdOf(book, ids()),
      ),
    );
  }

  /// 另一台在第 [chapterIndex] 話第 [pageIndex] 張，這台要不要跳過去：
  /// 不在同一張就跳。
  static bool shouldJump(ComicLocation here, int chapterIndex, int pageIndex) =>
      chapterIndex != here.chapterIndex || pageIndex != here.pageIndex;

  /// 讀者沒捲過：同一話同一張，那張圖讀到的幾成也一樣。開書還原到那張圖
  /// 的幾成時，換算回來會差一點點，不算捲過。
  static bool sameSpot(ComicLocation a, ComicLocation b) =>
      a.chapterIndex == b.chapterIndex &&
      a.pageIndex == b.pageIndex &&
      (a.fraction - b.fraction).abs() < 0.01;

  void _onHide() {
    _foreground = false;
    _pacer.stop();
    _upload();
  }

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
    if (_disposed) return;
    _disposed = true;
    _pacer.dispose();
    _lifecycle?.dispose();
    _sync.uploadsOnHide(this, false);
    if (_marked) _sync.closeBook(book);
    _upload();
  }
}
