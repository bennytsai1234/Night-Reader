import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:share_plus/share_plus.dart';

class ExportBookService {
  final ChapterDao _chapterDao = getIt<ChapterDao>();
  final ReaderChapterContentDao _chapterContentDao =
      getIt<ReaderChapterContentDao>();
  BookSourceDao get _sourceDao => getIt<BookSourceDao>();
  final BookSourceService _sourceService = BookSourceService();

  /// 匯出全書為 TXT 檔案
  Future<void> exportToTxt(
    Book book, {
    Function(double progress)? onProgress,
    bool fetchMissingRemote = false,
  }) async {
    final chapters = await _chapterDao.getByBook(book.bookUrl);
    if (chapters.isEmpty) return;
    final source =
        fetchMissingRemote && !book.isLocal
            ? await _resolveReadableSource(book)
            : null;

    final buffer = StringBuffer();
    buffer.writeln(book.name);
    buffer.writeln('作者：${book.author}');
    buffer.writeln('---');

    for (var i = 0; i < chapters.length; i++) {
      final entry = await _chapterContentDao.getEntry(
        contentKey: ReaderChapterContentDao.contentKey(
          origin: book.origin,
          bookUrl: book.bookUrl,
          chapterUrl: chapters[i].url,
        ),
      );
      var content = entry?.isReady == true ? entry?.content : null;
      if ((content == null || content.isEmpty) && book.origin == 'local') {
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
          await _chapterContentDao.saveContent(
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
        }
      }
      if (content != null) {
        buffer.writeln('\n${chapters[i].title}\n');
        buffer.writeln(content);
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
