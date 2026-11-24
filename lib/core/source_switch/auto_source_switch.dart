import 'dart:async';

import 'package:dio/dio.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/app_log_service.dart';
import '../background_work/background_work.dart';
import '../storage/book_cover_storage_service.dart';
import '../storage/books_in_use.dart';
import '../download/download_service.dart';
import 'source_switch_service.dart';

/// 自動換源（ADR 0069）：書架上的網路書的書源被刪掉時，在背景替每本找一次
/// 同類別、書名與作者一樣、讀到的那一章章名對得上的書源換過去；找不到就
/// 維持原狀，之後不再自動找。
///
/// 刪除的那一刻（[AppEventBus.sourcesDeleted]）記下要換的書，一本一本換；
/// 跑的時候佔背景工作的位置、只有「結束」，碰到別的背景工作就排在它後面
/// （[BackgroundWork.beginAfterCurrent]）。正開著的書（[BooksInUse]）不換：
/// 閱讀器手上還是舊的書，存進度時會把它寫回來；等它關掉再換。
class AutoSourceSwitch implements BackgroundJob {
  AutoSourceSwitch({
    BackgroundWork? work,
    this._bookDao,
    this._sourceDao,
    this._chapterDao,
    this._switcher,
    Set<String> Function()? booksInUse,
    Stream<String>? releasedBooks,
    Future<void> Function(String bookUrl)? keepDownloaded,
  }) : _work = work ?? BackgroundWork.instance,
       _booksInUse = booksInUse ?? (() => BooksInUse.bookUrls),
       _releasedBooks = releasedBooks ?? BooksInUse.released,
       _keepDownloaded =
           keepDownloaded ??
           ((bookUrl) => DownloadService().keepShelfBookDownloaded(bookUrl));

  static final AutoSourceSwitch instance = AutoSourceSwitch();

  /// 通知的標題。
  static const String title = '自動換源';

  final BackgroundWork _work;
  final BookDao? _bookDao;
  final BookSourceDao? _sourceDao;
  final ChapterDao? _chapterDao;
  final SourceSwitchService? _switcher;
  final Set<String> Function() _booksInUse;
  final Stream<String> _releasedBooks;
  final Future<void> Function(String bookUrl) _keepDownloaded;

  BookDao get _books => _bookDao ?? getIt<BookDao>();
  BookSourceDao get _sources => _sourceDao ?? getIt<BookSourceDao>();
  ChapterDao get _chapters => _chapterDao ?? getIt<ChapterDao>();

  late final SourceSwitchService _switch =
      _switcher ??
      SourceSwitchService(
        operationQuiescer: (oldBook) =>
            DownloadService().quiesceForSourceSwitch(oldBook),
        assetRetirer: BookCoverStorageService().handoffSourceSwitchAssets,
      );

  StreamSubscription<AppEvent>? _deletions;
  StreamSubscription<String>? _releases;

  /// 進場播完了：之前記下的書這時才開始換（ADR 0018，背景工作不和進場搶）。
  bool _settled = false;

  /// 還沒輪到的書，照記下的順序。
  final List<String> _pending = [];

  /// 正開著、等關掉再換的書。
  final Set<String> _heldBack = {};

  /// 這一輪處理到第幾本、總共幾本（通知的進度條）。
  int _done = 0;
  int _total = 0;

  bool _running = false;
  CancelToken? _cancel;

  /// 開 App 時呼叫：開始接收刪書源的通知（同步在進場前就可能刪）。
  void listen() {
    _deletions ??= AppEventBus()
        .onName(AppEventBus.sourcesDeleted)
        .listen((event) => unawaited(_onDeleted(event.data as List<String>)));
    _releases ??= _releasedBooks.listen(_onReleased);
  }

  /// 不再接收刪書源與關書的通知（測試用完換一個新的）。
  Future<void> dispose() async {
    await _deletions?.cancel();
    await _releases?.cancel();
    _deletions = null;
    _releases = null;
  }

  /// 進場播完時呼叫：開始換記下的書；這一版之前就沒有書源的書架網路書，
  /// 這台第一次開時找一次（[PreferKey.orphanedBooksSwitched]，開始找就記，
  /// 中途被收掉也算找過）。
  Future<void> onLaunchSettled(SharedPreferences prefs) async {
    _settled = true;
    try {
      if (!(prefs.getBool(PreferKey.orphanedBooksSwitched) ?? false)) {
        await prefs.setBool(PreferKey.orphanedBooksSwitched, true);
        final known = {
          for (final source in await _sources.getAllPart())
            source.bookSourceUrl,
        };
        _add(await _shelfWebBooks((origin) => !known.contains(origin)));
      }
    } catch (error, stack) {
      AppLog.e('AutoSourceSwitch: 找沒有書源的書失敗', error: error, stackTrace: stack);
    }
    _kick();
  }

  Future<void> _onDeleted(List<String> urls) async {
    try {
      final deleted = urls.toSet();
      _add(await _shelfWebBooks(deleted.contains));
    } catch (error, stack) {
      AppLog.e('AutoSourceSwitch: 找要換源的書失敗', error: error, stackTrace: stack);
    }
    _kick();
  }

  void _onReleased(String bookUrl) {
    if (!_heldBack.remove(bookUrl)) return;
    _add([bookUrl]);
    _kick();
  }

  Future<List<String>> _shelfWebBooks(
    bool Function(String origin) gone,
  ) async => [
    for (final book in await _books.getInBookshelf())
      if (!book.isLocal && gone(book.origin)) book.bookUrl,
  ];

  void _add(Iterable<String> bookUrls) {
    for (final url in bookUrls) {
      if (_pending.contains(url) || _heldBack.contains(url)) continue;
      _pending.add(url);
      _total++;
    }
  }

  void _kick() {
    if (!_settled || _running || _pending.isEmpty) return;
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    final cancel = _cancel = CancelToken();
    try {
      await _work.beginAfterCurrent(this, _status(null));
      while (_pending.isNotEmpty && !cancel.isCancelled) {
        final bookUrl = _pending.removeAt(0);
        try {
          await _switchOne(bookUrl, cancel);
        } catch (error, stack) {
          AppLog.e(
            'AutoSourceSwitch: 自動換源失敗 $bookUrl',
            error: error,
            stackTrace: stack,
          );
        }
        _done++;
      }
    } finally {
      // 按了結束：還沒輪到的也算找過，不接著做（ADR 0069）。
      _pending.clear();
      _done = 0;
      _total = 0;
      _cancel = null;
      _running = false;
      _work.end(this);
    }
  }

  /// 替 [bookUrl] 找一次書源。做的時候書源可能又加回來了、使用者自己換過
  /// 源、或打開了這本：這些都不換。
  Future<void> _switchOne(String bookUrl, CancelToken cancel) async {
    final orphaned = await _stillOrphaned(bookUrl);
    if (orphaned == null) return;
    var book = orphaned;
    // 搜書源要一兩分鐘，這段時間進度可能被同步改了：讀到的那一章變了就照
    // 改過的再找一次。
    for (var attempt = 0; attempt < 2; attempt++) {
      if (_booksInUse().contains(bookUrl)) {
        _heldBack.add(bookUrl);
        return;
      }
      _work.update(this, _status(book));
      final chapterTitle = await _readingTitle(book);
      if (chapterTitle == null) return;
      final prepared = await _switch.prepareAutomaticSwitch(
        book,
        chapterTitle: chapterTitle,
        cancelToken: cancel,
      );
      if (prepared == null || cancel.isCancelled) return;
      final latest = await _stillOrphaned(bookUrl);
      if (latest == null) return;
      if (_booksInUse().contains(bookUrl)) {
        _heldBack.add(bookUrl);
        return;
      }
      // 寫回最新的這本：搜的時候分組、封面、閱讀設定這類可能改過。
      final rebased = latest.origin == book.origin
          ? _switch.rebase(
              prepared,
              latest,
              targetChapterTitle: await _readingTitle(latest),
            )
          : null;
      if (rebased == null) {
        book = latest;
        continue;
      }
      // 換過去的那本已經在書架上（從那個書源加過同一本）：換了會蓋掉它的
      // 進度、少一本，留給使用者自己決定。
      final target = rebased.migratedBook.bookUrl;
      if (target != bookUrl &&
          ((await _books.getByUrl(target))?.isInBookshelf ?? false)) {
        return;
      }
      // 換之前要等舊書源的下載收尾，可能等很久：等完照書現在的樣子再對一次
      // （讀者可能打開過、讀了幾頁）；現在開著就不換，等書關掉再來。
      final switched = await _switch.commitSwitch(
        latest,
        rebased,
        bookDao: _books,
        refresh: () async {
          if (_booksInUse().contains(bookUrl)) return null;
          final current = await _stillOrphaned(bookUrl);
          if (current == null || current.origin != latest.origin) return null;
          final again = _switch.rebase(
            prepared,
            current,
            targetChapterTitle: await _readingTitle(current),
          );
          if (again == null || _booksInUse().contains(bookUrl)) return null;
          return (book: current, prepared: again);
        },
      );
      if (!switched) {
        if (_booksInUse().contains(bookUrl)) {
          _heldBack.add(bookUrl);
          return;
        }
        // 讀到的那一章在新書源對不上了：照現在的進度再找一次。
        final current = await _stillOrphaned(bookUrl);
        if (current == null) return;
        book = current;
        continue;
      }
      AppEventBus().fire(AppEventBus.upBookshelf);
      // 書架上的書照新書源整本重抓（ADR 0008）。
      unawaited(_keepDownloaded(target));
      return;
    }
  }

  /// 書還在書架上、還是網路書、書源還是不在：要換源的那本。
  Future<Book?> _stillOrphaned(String bookUrl) async {
    final book = await _books.getByUrl(bookUrl);
    if (book == null || !book.isInBookshelf || book.isLocal) return null;
    if (await _sources.getByUrl(book.origin) != null) return null;
    return book;
  }

  /// 讀到的那一章的章名：書記的章名，沒記（從沒打開過）就照目錄。
  Future<String?> _readingTitle(Book book) async {
    final title = book.durChapterTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    for (final chapter in await _chapters.getByBook(book.bookUrl)) {
      if (chapter.index == book.chapterIndex) return chapter.title;
    }
    return null;
  }

  BackgroundWorkStatus _status(Book? book) => BackgroundWorkStatus(
    title: title,
    text: book == null ? '正在找替代的書源' : '正在替《${book.name}》找書源',
    progress: _total == 0 ? null : _done / _total,
  );

  /// 通知上按了暫停或被系統收掉：自動換源不接著做，和結束一樣（ADR 0069）。
  @override
  void pauseFromSystem() => endFromSystem();

  @override
  void endFromSystem() {
    _pending.clear();
    _heldBack.clear();
    _cancel?.cancel();
    if (_running) {
      _work.update(
        this,
        const BackgroundWorkStatus.settling(title, pausing: false),
      );
    }
  }

  /// 沒有頁面：做完就收掉，不留結果（ADR 0069）。
  @override
  void openFromNotification() {}
}
