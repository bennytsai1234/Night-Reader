import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

/// 網站把這本書改成付費：正文頁只回付費提示。
class _PaywalledSite extends BookSourceService {
  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async => '本章為付費章節，請訂閱後閱讀';
}

void main() {
  late AppDatabase db;
  late ReaderChapterContentStore store;
  late ChapterContentPreparationPipeline pipeline;

  final source = BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': 'https://s.example',
  });
  final book = Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
  );
  BookChapter lockedChapter() => BookChapter(
    url: 'https://s.example/c/1.html',
    title: '第一章',
    bookUrl: book.bookUrl,
    isVip: true,
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = ReaderChapterContentStore(
      chapterDao: ChapterDao(db),
      contentDao: ReaderChapterContentDao(db),
    );
    pipeline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: store,
      sourceDao: BookSourceDao(db),
      service: _PaywalledSite(),
      getSource: () => source,
    );
  });

  tearDown(() => db.close());

  test('a paid chapter not bought yet is shown but not stored', () async {
    final result = await pipeline.prepare(
      chapterIndex: 0,
      chapter: lockedChapter(),
    );

    expect(result.content, '本章為付費章節，請訂閱後閱讀');
    expect(
      await store.getContentEntry(book: book, chapter: lockedChapter()),
      isNull,
    );
  });

  test('content stored while the chapter was free is kept', () async {
    final chapter = lockedChapter();
    await store.saveRawContent(book: book, chapter: chapter, content: '免費時的正文');

    final reread = await pipeline.prepare(chapterIndex: 0, chapter: chapter);
    final refreshed = await pipeline.prepare(
      chapterIndex: 0,
      chapter: chapter,
      forceRefresh: true,
    );

    expect(reread.content, '免費時的正文');
    expect(refreshed.content, '本章為付費章節，請訂閱後閱讀');
    expect(
      (await store.getContentEntry(book: book, chapter: chapter))!.content,
      '免費時的正文',
    );
  });
}
