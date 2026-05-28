import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/models/reader_chapter_content.dart';

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
      await chapterDao.insertChapters(<BookChapter>[chapter]);
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
      await chapterDao.insertChapters(<BookChapter>[chapter]);
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

  Future<Set<int>> storedChapterIndices({required Book book}) async {
    return contentDao.getStoredChapterIndices(
      origin: book.origin,
      bookUrl: book.bookUrl,
    );
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
}
