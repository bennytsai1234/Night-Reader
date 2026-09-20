import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeChapterDao extends Fake implements ChapterDao {
  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async => <BookChapter>[];

  @override
  Future<void> insertChapters(List<BookChapter> chapterList) async {}
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  _FakeSourceDao([this.source]);

  final BookSource? source;

  @override
  Future<BookSource?> getByUrl(String url) async => source;
}

class _ThrowingChapterListService extends BookSourceService {
  _ThrowingChapterListService(this.error);

  final Object error;

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    throw error;
  }
}

void main() {
  test('既有不支援本地書不會從章節內容或快取繞過格式檢查', () async {
    final book = Book(
      bookUrl: r'local://C:\books\legacy.epub',
      origin: 'local',
      name: '舊本地書',
    );
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: <BookChapter>[
        BookChapter(
          url: '${book.bookUrl}#0',
          bookUrl: book.bookUrl,
          title: '第一章',
          content: '不應繼續讀取的既有內容',
        ),
      ],
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );

    await expectLater(
      repository.loadContent(0),
      throwsA(
        isA<ReaderV2ContentUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('本地書格式不受支援'),
        ),
      ),
    );
  });
  test(
    'reloaded materialized chapter identity advances semantic generation',
    () async {
      final book = Book(
        bookUrl: 'local://identity-drift.txt',
        origin: 'local',
        name: 'identity-drift',
      );
      final chapters = List<BookChapter>.generate(
        21,
        (index) => BookChapter(
          url: 'chapter_$index',
          bookUrl: book.bookUrl,
          title: '第 $index 章',
          index: index,
          content: '正文 $index',
        ),
      );
      final raw = <int, String>{
        for (var index = 0; index < chapters.length; index++)
          index: '正文 $index',
      };
      final repository = ReaderV2ChapterRepository(
        book: book,
        initialChapters: chapters,
        contentLoader: (index, __) async => raw[index],
        bookDao: _FakeBookDao(),
        chapterDao: _FakeChapterDao(),
        sourceDao: _FakeSourceDao(),
      );

      await repository.loadContent(0);
      for (var index = 1; index < chapters.length; index += 1) {
        await repository.loadContent(index);
      }
      expect(repository.cachedContent(0), isNull);
      expect(repository.contentGeneration, 0);

      raw[0] = '正文 0 已由外部持久層更新';
      final changed = await repository.loadContent(0);

      expect(changed.displayText, contains('外部持久層更新'));
      expect(repository.contentGeneration, 1);
    },
  );

  test('semantic content generation advances only after a committed reload', () async {
    var raw = '第一版正文';
    var fail = false;
    final book = Book(
      bookUrl: 'local://generation.txt',
      origin: 'local',
      name: 'generation',
    );
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: <BookChapter>[
        BookChapter(
          url: 'chapter_0',
          bookUrl: book.bookUrl,
          title: '第一章',
          content: raw,
        ),
      ],
      contentLoader: (_, __) async {
        if (fail) {
          throw const ReaderV2ContentUnavailableException('refresh unavailable');
        }
        return raw;
      },
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );

    await repository.loadContent(0);
    expect(repository.contentGeneration, 0);

    raw = '第二版正文';
    final committed = await repository.reloadContent(0);
    expect(committed.displayText, contains('第二版正文'));
    expect(repository.contentGeneration, 1);

    final cached = repository.cachedContent(0);
    fail = true;
    await expectLater(
      repository.reloadContent(0),
      throwsA(isA<ReaderV2ContentUnavailableException>()),
    );

    expect(repository.contentGeneration, 1);
    expect(repository.cachedContent(0), same(cached));
  });

  test('known source failure becomes explicit TOC content-unavailable', () async {
    final source = BookSource(bookSourceUrl: 'https://source.example');
    final repository = ReaderV2ChapterRepository(
      book: Book(
        bookUrl: 'https://book.example/1',
        origin: source.bookSourceUrl,
      ),
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(source),
      service: _ThrowingChapterListService(
        SourceException('目錄規則不可用', sourceUrl: source.bookSourceUrl),
      ),
    );

    await expectLater(
      repository.ensureChapters(),
      throwsA(
        isA<ReaderV2ContentUnavailableException>().having(
          (error) => error.message,
          'message',
          contains('目錄規則不可用'),
        ),
      ),
    );
  });

  test('network TOC cancellation is not converted to unavailable', () async {
    final source = BookSource(bookSourceUrl: 'https://source.example');
    final cancellation = DioException(
      requestOptions: RequestOptions(path: source.bookSourceUrl),
      type: DioExceptionType.cancel,
      message: 'superseded',
    );
    final repository = ReaderV2ChapterRepository(
      book: Book(
        bookUrl: 'https://book.example/1',
        origin: source.bookSourceUrl,
      ),
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(source),
      service: _ThrowingChapterListService(cancellation),
    );

    await expectLater(
      repository.ensureChapters(),
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
  });

  test('unknown TOC failure keeps its original root cause', () async {
    final source = BookSource(bookSourceUrl: 'https://source.example');
    final error = StateError('TOC invariant broke');
    final repository = ReaderV2ChapterRepository(
      book: Book(
        bookUrl: 'https://book.example/1',
        origin: source.bookSourceUrl,
      ),
      bookDao: _FakeBookDao(),
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(source),
      service: _ThrowingChapterListService(error),
    );

    await expectLater(repository.ensureChapters(), throwsA(same(error)));
  });
}
