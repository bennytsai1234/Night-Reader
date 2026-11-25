import 'dart:io';

import 'package:dio/dio.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/source/chapter_content_kind.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/storage/reader_chapter_content_store.dart';
import 'package:night_reader/core/utils/illustration_markers.dart';

/// 借的書源目錄裡這一章能不能借：有正文（不是分卷標題、有網址），不是付費
/// 章節（ADR 0057）。
bool chapterBorrowable(BookChapter chapter) => chapterIsDownloadable(chapter);

/// 單章借源（ADR 0080）：用借的書源 [source] 上那本書 [lenderBook] 的第
/// [lenderIndex] 章（[lenderChapters]）抓正文與插圖，蓋進主書源那本 [book]
/// 的 [chapter]；主書源的書與目錄都不動。
///
/// 同一章分頁的停止點用借的書源目錄的下一章（最後一章用第一章，同引擎沒給
/// 停點時的做法），不拿主書源的。插圖用借的書源抓進這本書的插圖資料夾；
/// 連不上的照現狀留給書架自動下載補。正文要讀得到（同換源）；寫進去的
/// 同一個交易裡再看一次主書源這一章還在目錄裡、沒有改成付費章節，寫完、
/// 交易收尾前 [cancelToken] 沒有取消。傳回存進去的正文；借不成丟 [AppException]
/// （書源搜不到、抓不到時照書源工作原本丟的）。
Future<String> borrowChapter({
  required Book book,
  required BookChapter chapter,
  required BookSource source,
  required Book lenderBook,
  required List<BookChapter> lenderChapters,
  required int lenderIndex,
  required ChapterDao chapterDao,
  required ReaderChapterContentDao contentDao,
  BookSourceService? service,
  CancelToken? cancelToken,
}) async {
  final sources = service ?? BookSourceService();
  // 抓正文時規則會改章節的欄位：改在複本上，借的書源的目錄留著原樣。
  final lenderChapter = lenderChapters[lenderIndex].copyWith();
  if (!chapterBorrowable(lenderChapter)) {
    throw SourceException('這一章沒有正文', sourceUrl: source.bookSourceUrl);
  }
  final content = await sources.getContent(
    source,
    lenderBook,
    lenderChapter,
    nextChapterUrl: _stopAt(lenderChapters, lenderIndex),
    cancelToken: cancelToken,
  );
  if (!chapterContentUsable(BookSourceKind.novel, content)) {
    throw SourceException('借來的正文讀不到', sourceUrl: source.bookSourceUrl);
  }
  final dir = content.contains('<img')
      ? await BookIllustrationStorage.dirFor(book)
      : null;
  // 插圖資料夾裡本來就有的那些（別的章節或動作抓的）不是這次的。
  final existed = dir == null
      ? const <String>{}
      : await _illustrationsOnDisk(dir, content);
  try {
    if (dir != null) {
      final pending = await sources.fetchIllustrations(
        source,
        lenderBook,
        content,
        dir: dir,
        cancelToken: cancelToken,
      );
      if (pending > 0) await BookIllustrationStorage.markUnfetched(book);
    }
    // 這一章還在不在目錄、是不是付費章節，和寫入在同一個交易裡看：中間不會
    // 被換目錄插進來。資料庫在另一個 isolate，交易裡每等一次，畫面都可能收
    // 到關面板、改選別章而取消：交易最後再看一次取消，取消了就丟出錯誤、整個
    // 交易退回，原本的正文留著。
    return await chapterDao.transaction(() async {
      if (cancelToken?.cancelError case final cancelled?) throw cancelled;
      final current = await chapterDao.getByUrl(book.bookUrl, chapter.url);
      if (current == null) {
        throw SourceException('這一章已經不在目錄裡', sourceUrl: book.origin);
      }
      final saved =
          await ReaderChapterContentStore(
            chapterDao: chapterDao,
            contentDao: contentDao,
          ).saveRawContent(
            book: book,
            chapter: current,
            content: content,
            // 主書源目錄的章名、字數這類不改。
            saveChapterMetadata: false,
            replaceStored: true,
          );
      if (!saved) throw LockedChapterException();
      if (cancelToken?.cancelError case final cancelled?) throw cancelled;
      return content;
    });
  } catch (_) {
    // 正文沒寫進去（取消，或這一章不在目錄、改成付費）：這次才抓下、這本
    // 書存著的正文也沒用到的插圖刪掉，不留著佔空間。
    if (dir != null) {
      await _removeNewIllustrations(
        contentDao: contentDao,
        book: book,
        content: content,
        dir: dir,
        existed: existed,
      );
    }
    rethrow;
  }
}

/// [content] 的插圖裡，插圖資料夾已經有圖檔的網址。
Future<Set<String>> _illustrationsOnDisk(String dir, String content) async => {
  for (final src in IllustrationMarkers.sourcesOf(content).toSet())
    if (await File(BookIllustrationStorage.pathFor(dir, src)).exists()) src,
};

/// 這次才抓下的插圖裡，這本書存著的正文沒用到的刪掉；同一個網址別的章節
/// 也用到時留著。
Future<void> _removeNewIllustrations({
  required ReaderChapterContentDao contentDao,
  required Book book,
  required String content,
  required String dir,
  required Set<String> existed,
}) async {
  try {
    final stored = await contentDao.getStoredContentsWithIllustrations(
      origin: book.origin,
      bookUrl: book.bookUrl,
    );
    final used = {
      for (final chapterContent in stored.values)
        ...IllustrationMarkers.sourcesOf(chapterContent),
    };
    for (final src in IllustrationMarkers.sourcesOf(content).toSet()) {
      if (existed.contains(src) || used.contains(src)) continue;
      final file = File(BookIllustrationStorage.pathFor(dir, src));
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (error) {
        AppLog.w('借源沒寫進正文，這次抓的插圖刪不掉 $src: $error');
      }
    }
  } catch (error) {
    AppLog.w('借源沒寫進正文，這次抓的插圖沒清掉 ${book.bookUrl}: $error');
  }
}

String _stopAt(List<BookChapter> chapters, int index) {
  for (var i = index + 1; i < chapters.length; i++) {
    if (chapterHasContent(chapters[i])) return chapters[i].url;
  }
  return chapters.first.url;
}
