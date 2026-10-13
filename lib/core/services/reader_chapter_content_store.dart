import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/reader_chapter_content.dart';

/// 有正文可下載的章節：分卷標題與沒有網址的章節沒有正文。
bool chapterHasContent(BookChapter chapter) =>
    !chapter.isVolume && chapter.url.isNotEmpty;

/// [chapters] 中有正文、但網址不在 [storedUrls] 裡的章節。
List<BookChapter> chaptersMissingContent(
  List<BookChapter> chapters,
  Set<String> storedUrls,
) => chapters
    .where((c) => chapterHasContent(c) && !storedUrls.contains(c.url))
    .toList();

class ReaderChapterContentStore {
  ReaderChapterContentStore({
    required this.chapterDao,
    required this.contentDao,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ChapterDao chapterDao;
  final ReaderChapterContentDao contentDao;
  final DateTime Function() _now;

  Future<String?> getRawContent({
    required Book book,
    required BookChapter chapter,
  }) async {
    final entry = await getContentEntry(book: book, chapter: chapter);
    final storedContent = entry?.content;
    return storedContent == null || storedContent.isEmpty
        ? null
        : storedContent;
  }

  Future<ReaderChapterContentEntry?> getContentEntry({
    required Book book,
    required BookChapter chapter,
  }) {
    return contentDao.getEntry(
      contentKey: contentKeyFor(book: book, chapter: chapter),
    );
  }

  Future<bool> hasReadyContent({
    required Book book,
    required BookChapter chapter,
  }) {
    return contentDao.hasReadyContent(
      contentKey: contentKeyFor(book: book, chapter: chapter),
    );
  }

  Future<void> saveRawContent({
    required Book book,
    required BookChapter chapter,
    required String content,
    bool saveChapterMetadata = true,
  }) async {
    if (content.isEmpty) return;
    if (saveChapterMetadata) {
      await chapterDao.updateFetchedChapter(chapter);
    }

    await contentDao.saveContent(
      contentKey: contentKeyFor(book: book, chapter: chapter),
      origin: book.origin,
      bookUrl: book.bookUrl,
      chapterUrl: chapter.url,
      chapterIndex: chapter.index,
      content: content,
      updatedAt: _now().millisecondsSinceEpoch,
    );
  }

  Future<void> saveFailure({
    required Book book,
    required BookChapter chapter,
    required String message,
    bool saveChapterMetadata = true,
  }) async {
    if (message.isEmpty) return;
    if (saveChapterMetadata) {
      await chapterDao.updateFetchedChapter(chapter);
    }

    await contentDao.saveFailure(
      contentKey: contentKeyFor(book: book, chapter: chapter),
      origin: book.origin,
      bookUrl: book.bookUrl,
      chapterUrl: chapter.url,
      chapterIndex: chapter.index,
      message: message,
      updatedAt: _now().millisecondsSinceEpoch,
    );
  }

  Future<void> clearChapter({
    required Book book,
    required BookChapter chapter,
  }) {
    return contentDao.deleteContent(
      contentKey: contentKeyFor(book: book, chapter: chapter),
    );
  }

  Future<void> saveChapterMetadata(List<BookChapter> chapters) async {
    if (chapters.isEmpty) return;
    await chapterDao.insertChapters(chapters);
  }

  /// [chapters] 裡還沒有正文的章節（依章節網址比對，分卷標題不算）。
  Future<List<BookChapter>> missingChapters({
    required Book book,
    required List<BookChapter> chapters,
  }) async {
    final stored = await contentDao.getStoredChapterUrls(
      origin: book.origin,
      bookUrl: book.bookUrl,
    );
    return chaptersMissingContent(chapters, stored);
  }

  Future<void> deleteStoredContentForBook({required Book book}) async {
    await contentDao.deleteByBook(book.origin, book.bookUrl);
  }

  static String contentKeyFor({
    required Book book,
    required BookChapter chapter,
  }) => ReaderChapterContentDao.contentKey(
    origin: book.origin,
    bookUrl: book.bookUrl,
    chapterUrl: chapter.url,
  );

  static String inFlightKeyFor({
    required Book book,
    required BookChapter chapter,
    required int chapterIndex,
    required BookSource? sourceOverride,
    required bool forceRefresh,
    required bool saveChapterMetadata,
    required int maxAttempts,
  }) {
    final sourceKey = sourceOverride?.bookSourceUrl.trim() ?? '';
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    return '${contentKeyFor(book: book, chapter: chapter)}\n'
        'source=$sourceKey\n'
        'index=$chapterIndex\n'
        'refresh=$forceRefresh\n'
        'metadata=$saveChapterMetadata\n'
        'attempts=$attempts';
  }
}
