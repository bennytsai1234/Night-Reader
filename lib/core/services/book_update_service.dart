import 'dart:async';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';

/// 把書架上一本書還沒下載的章節排進背景下載（ADR 0008）。
typedef ShelfBookDownloader = Future<void> Function(
  String bookUrl, {
  bool hasNewChapters,
});

class BookUpdateCheckResult {
  const BookUpdateCheckResult({
    required this.bookUrl,
    required this.newChapterCount,
    this.error,
  });

  final String bookUrl;
  final int newChapterCount;
  final Object? error;

  bool get hasUpdate => newChapterCount > 0;
  bool get failed => error != null;
}

/// 從書源抓一本書的詳情與目錄寫回資料庫，寫好後交給書架自動下載。
///
/// 書架的下拉與開 App 檢查、書架上單本與多選的「檢查更新」、書籍詳情的
/// 「檢查更新」都走這裡。同一本書（網址＋書源）已在檢查時接上同一次：
/// 不重複發請求，後到的也不會因為先到的那次已寫入新目錄，就把新章節數算
/// 成 0。各入口只決定怎麼呈現結果。
class BookUpdateService {
  BookUpdateService({
    required this._keepDownloaded,
    BookDao? bookDao,
    ChapterDao? chapterDao,
    BookSourceDao? sourceDao,
    BookSourceService? sourceService,
  }) : _bookDao = bookDao ?? getIt<BookDao>(),
       _chapterDao = chapterDao ?? getIt<ChapterDao>(),
       _sourceDao = sourceDao ?? getIt<BookSourceDao>(),
       _sourceService = sourceService ?? BookSourceService();

  final ShelfBookDownloader _keepDownloaded;
  final BookDao _bookDao;
  final ChapterDao _chapterDao;
  final BookSourceDao _sourceDao;
  final BookSourceService _sourceService;

  /// 進行中的檢查。書架與書籍詳情各自建立實例，所以放在 static 上共用。
  static final Map<(String, String), Future<BookUpdateCheckResult>> _checking =
      {};

  Future<BookUpdateCheckResult> check(Book book) {
    if (book.isLocal) {
      return Future.value(
        BookUpdateCheckResult(bookUrl: book.bookUrl, newChapterCount: 0),
      );
    }
    final key = (book.bookUrl, book.origin);
    // 不能寫成 `=> _checking.remove(...)`：remove 回傳的就是這個 Future，
    // whenComplete 會等它，變成自己等自己。
    return _checking[key] ??= _check(book).whenComplete(() {
      _checking.remove(key);
    });
  }

  /// 網路請求期間使用者可能在讀這本書、改了設定或把它移出書架，所以寫回時
  /// 以資料庫裡最新的一筆為準，只換掉書源給的欄位。
  Future<BookUpdateCheckResult> _check(Book book) async {
    final checkedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final source = await _sourceDao.getByUrl(book.origin);
      if (source == null || !source.isReadingEnabledByRuntime) {
        throw StateError('找不到可閱讀書源');
      }
      final info = await _sourceService.getBookInfo(source, book);
      final chapters = await _sourceService.getChapterList(source, info);
      info.bookUrl = book.bookUrl;
      info.origin = book.origin;
      info.originName = book.originName;
      if (info.tocUrl.isEmpty) {
        info.tocUrl = book.tocUrl;
      }
      for (var i = 0; i < chapters.length; i++) {
        chapters[i].index = i;
        chapters[i].bookUrl = book.bookUrl;
      }

      final newCount = await _bookDao.transaction<int?>(() async {
        final stored = await _bookDao.getByUrl(book.bookUrl);
        // 檢查期間移出書架或換了書源：不寫回，免得書又回到書架上。不在
        // 書架上的書（從搜尋或發現打開的詳情）照樣寫回。
        if (book.isInBookshelf && (stored == null || !stored.isInBookshelf) ||
            stored != null && stored.origin != book.origin) {
          return null;
        }
        final current = stored ?? book;
        final oldTotal = current.totalChapterNum > 0
            ? current.totalChapterNum
            : chapters.length;
        final newCount = chapters.length > oldTotal
            ? chapters.length - oldTotal
            : 0;
        info.isInBookshelf = current.isInBookshelf;
        info.group = current.group;
        info.order = current.order;
        info.syncTime = current.syncTime;
        info.chapterIndex = current.chapterIndex;
        info.charOffset = current.charOffset;
        info.visualOffsetPx = current.visualOffsetPx;
        info.durChapterTitle = current.durChapterTitle;
        info.durChapterTime = current.durChapterTime;
        info.readerAnchorJson = current.readerAnchorJson;
        info.canUpdate = current.canUpdate;
        info.customCoverUrl = current.customCoverUrl;
        info.customCoverLocalPath = current.customCoverLocalPath;
        info.customIntro = current.customIntro;
        info.customTag = current.customTag;
        info.readConfig = current.readConfig;
        info.lastCheckTime = checkedAt;
        info.lastCheckCount = newCount;
        info.totalChapterNum = chapters.length;
        if (chapters.isNotEmpty) {
          info.latestChapterTitle = chapters.last.title;
          if (newCount > 0) {
            info.latestChapterTime = checkedAt;
          }
        }
        await _bookDao.upsert(info);
        if (chapters.isNotEmpty) {
          // 整份換成書源目前的目錄：書源拿掉的章節不留下來佔著序號。
          await _chapterDao.deleteByBook(book.bookUrl);
          await _chapterDao.insertChapters(chapters);
        }
        return newCount;
      });
      if (newCount == null) {
        return BookUpdateCheckResult(bookUrl: book.bookUrl, newChapterCount: 0);
      }
      // 目錄寫好了：新章節（或之前沒排到的章節）接著下載。不在書架上的書
      // 由下載服務略過。
      try {
        await _keepDownloaded(book.bookUrl, hasNewChapters: newCount > 0);
      } catch (error) {
        AppLog.w('書架自動下載排程失敗 ${book.bookUrl}: $error');
      }
      return BookUpdateCheckResult(
        bookUrl: book.bookUrl,
        newChapterCount: newCount,
      );
    } catch (e) {
      AppLog.w('檢查書籍更新失敗 ${book.name}: $e');
      await _bookDao.updateLastCheckTime(book.bookUrl, checkedAt);
      return BookUpdateCheckResult(
        bookUrl: book.bookUrl,
        newChapterCount: 0,
        error: e,
      );
    }
  }
}
