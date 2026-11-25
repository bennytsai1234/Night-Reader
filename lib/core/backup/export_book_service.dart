import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:share_plus/share_plus.dart';

class ExportBookService {
  ExportBookService({BookSourceService? sourceService})
    : _sourceService = sourceService ?? BookSourceService();

  final ChapterDao _chapterDao = getIt<ChapterDao>();
  final ReaderChapterContentDao _chapterContentDao =
      getIt<ReaderChapterContentDao>();
  BookSourceDao get _sourceDao => getIt<BookSourceDao>();
  BookDao get _bookDao => getIt<BookDao>();
  final BookSourceService _sourceService;

  /// 匯出全書為 TXT 檔案。漫畫是圖、沒有文字，丟出 [StateError]（書籍詳情
  /// 不給漫畫這個選項，ADR 0052）。
  ///
  /// 每一章交給 [present] 整理成要寫進檔案的章名與正文：照 Legado 套這本書
  /// 的替換規則、拿掉正文開頭重複的章名（閱讀器那一套，由呼叫端給）。
  Future<void> exportToTxt(
    Book book, {
    required Future<({String title, String text})> Function(
      BookChapter chapter,
      String rawContent,
    )
    present,
    Function(double progress)? onProgress,
    bool fetchMissingRemote = false,
  }) async {
    if (book.bookKind == BookSourceKind.comic) {
      throw StateError('漫畫沒有文字可以匯出');
    }
    var stored = await _chapterDao.getByBook(book.bookUrl);
    if (book.isLocal &&
        localBookExtensionFromPath(LocalBookService.filePathOf(book)) ==
            'epub') {
      // 本地 EPUB 轉好的文字不見或轉法改過：先重轉、對好目錄再讀，不拿舊
      // 範圍讀新檔。
      stored = (await LocalBookService().syncEpubChapters(
        book,
        stored,
        bookDao: _bookDao,
        chapterDao: _chapterDao,
        contentDao: _chapterContentDao,
      )).chapters;
    }
    // 付費章節沒有正文，不匯出（ADR 0057）。
    final chapters = [
      for (final chapter in stored)
        if (!chapter.isLocked) chapter,
    ];
    if (chapters.isEmpty) return;
    final source = fetchMissingRemote && !book.isLocal
        ? await _resolveReadableSource(book)
        : null;

    final buffer = StringBuffer();
    buffer.writeln(book.name);
    buffer.writeln('作者：${book.author}');
    buffer.writeln('---');

    for (var i = 0; i < chapters.length; i++) {
      // 分卷寫卷名；本地 EPUB 的分卷可能有卷首的字（同 Legado 照樣匯出）。
      if (chapters[i].isVolume) {
        final volume = await present(
          chapters[i],
          book.isLocal
              ? await LocalBookService().getContent(book, chapters[i])
              : '',
        );
        buffer.writeln('\n${volume.title}\n');
        if (volume.text.trim().isNotEmpty) buffer.writeln(volume.text);
        onProgress?.call((i + 1) / chapters.length);
        continue;
      }
      final entry = await _chapterContentDao.getEntry(
        contentKey: ReaderChapterContentDao.contentKey(
          origin: book.origin,
          bookUrl: book.bookUrl,
          chapterUrl: chapters[i].url,
        ),
      );
      var content = entry?.isReady == true ? entry?.content : null;
      if ((content == null || content.isEmpty) && book.isLocal) {
        content = await LocalBookService().getContent(book, chapters[i]);
      }
      if ((content == null || content.isEmpty) && source != null) {
        content = await _sourceService.getContent(
          source,
          book,
          chapters[i],
          nextChapterUrl: _nextReadableChapterUrl(chapters, i),
        );
        if (content.trim().isNotEmpty) {
          if (content.contains('<img')) {
            // 暫時連不上的圖留記號，書架自動下載之後再補（同閱讀器抓正文）。
            final pending = await _sourceService.fetchIllustrations(
              source,
              book,
              content,
              dir: await BookIllustrationStorage.dirFor(book),
            );
            if (pending > 0) await BookIllustrationStorage.markUnfetched(book);
          }
          // 補抓的期間使用者借來或重新取得的不蓋掉，匯出存著的那一份
          // （ADR 0080）。
          final filled = await _chapterContentDao.fillContent(
            contentKey: ReaderChapterContentDao.contentKey(
              origin: book.origin,
              bookUrl: book.bookUrl,
              chapterUrl: chapters[i].url,
            ),
            origin: book.origin,
            bookUrl: book.bookUrl,
            chapterUrl: chapters[i].url,
            chapterIndex: chapters[i].index,
            content: content,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          if (!filled) {
            content =
                await _chapterContentDao.getContent(
                  contentKey: ReaderChapterContentDao.contentKey(
                    origin: book.origin,
                    bookUrl: book.bookUrl,
                    chapterUrl: chapters[i].url,
                  ),
                ) ??
                content;
          }
        }
      }
      if (content != null) {
        final chapter = await present(chapters[i], content);
        buffer
          ..writeln('\n${chapter.title}\n')
          ..writeln(chapter.text);
      }
      if (onProgress != null) {
        onProgress((i + 1) / chapters.length);
      }
    }

    final fileName =
        '${book.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.txt';
    final file = await AppStoragePaths.shareExportFile(fileName);
    await file.writeAsString(buffer.toString());

    // 使用 SharePlus.instance.share
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: '匯出書籍: ${book.name}'),
    );
  }

  Future<BookSource?> _resolveReadableSource(Book book) async {
    final source = await _sourceDao.getByUrl(book.origin);
    if (source == null || !source.isReadingEnabledByRuntime) {
      throw StateError('目前來源無法補抓缺失章節');
    }
    return source;
  }

  String? _nextReadableChapterUrl(
    List<BookChapter> chapters,
    int currentIndex,
  ) {
    for (var i = currentIndex + 1; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (!chapter.isVolume && chapter.url.isNotEmpty) {
        return chapter.url;
      }
    }
    return null;
  }
}
