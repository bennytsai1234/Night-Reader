import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/source_switch_service.dart';

/// 受控的 BookSourceService 替身，讓 resolveSwitch 不需真實網路。
class _FakeBookSourceService extends BookSourceService {
  _FakeBookSourceService({
    required this.chapters,
    this.content = '這是一段足夠長的章節正文內容，用來通過可讀性檢查。',
    this.throwOnChapterList = false,
  });

  final List<BookChapter> chapters;
  final String content;
  final bool throwOnChapterList;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    return book;
  }

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    if (throwOnChapterList) return const <BookChapter>[];
    return chapters;
  }

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    return content;
  }
}

BookSource _source(String url, String name) {
  return BookSource(bookSourceUrl: url, bookSourceName: name);
}

SearchBook _candidate(String origin) {
  return SearchBook(
    bookUrl: '$origin/book/1',
    name: '測試書',
    author: '作者',
    origin: origin,
    originName: '新源',
    tocUrl: '$origin/toc/1',
  );
}

Book _currentBook({
  int chapterIndex = 5,
  String? durChapterTitle = '第6章',
  int totalChapterNum = 100,
}) {
  return Book(
    bookUrl: 'old-origin/book/1',
    origin: 'old-origin',
    originName: '舊源',
    name: '測試書',
    author: '作者',
    chapterIndex: chapterIndex,
    durChapterTitle: durChapterTitle,
    totalChapterNum: totalChapterNum,
    isInBookshelf: true,
  );
}

List<BookChapter> _chapters(String bookUrl, int count) {
  return List<BookChapter>.generate(
    count,
    (i) => BookChapter(
      url: '$bookUrl/c$i',
      title: '第${i + 1}章',
      bookUrl: bookUrl,
      index: i,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SourceSwitchService.resolveSwitch', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.bookSourceDao.upsert(_source('new-origin', '新源'));
    });

    tearDown(() async {
      await db.close();
    });

    test('按標題對齊到目標章節索引', () async {
      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 100);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );

      final resolution = await service.resolveSwitch(
        _currentBook(chapterIndex: 5, durChapterTitle: '第6章'),
        candidate,
        targetChapterIndex: 5,
        targetChapterTitle: '第6章',
        validateTargetContent: true,
      );

      // '第6章' 在新章節列表的 index 5。
      expect(resolution.targetChapterIndex, 5);
      expect(resolution.chapters.length, 100);
      expect(resolution.migratedBook.origin, 'new-origin');
      expect(resolution.validatedContent, isNotNull);
    });

    test('新源章節數較少時 clamp 不越界', () async {
      final candidate = _candidate('new-origin');
      // 新源只有 10 章，但目標索引指向 50。
      final chapters = _chapters(candidate.bookUrl, 10);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );

      final resolution = await service.resolveSwitch(
        _currentBook(
          chapterIndex: 50,
          durChapterTitle: '不存在的章節',
          totalChapterNum: 100,
        ),
        candidate,
        targetChapterIndex: 50,
        targetChapterTitle: '不存在的章節',
        validateTargetContent: true,
      );

      expect(resolution.targetChapterIndex, inInclusiveRange(0, 9));
    });

    test('目標章節內容不可讀時丟 StateError', () async {
      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 100);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(
          chapters: chapters,
          content: '加載章節失敗',
        ),
        sourceDao: db.bookSourceDao,
      );

      expect(
        () => service.resolveSwitch(
          _currentBook(),
          candidate,
          targetChapterIndex: 5,
          targetChapterTitle: '第6章',
          validateTargetContent: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            '目標章節內容不可讀',
          ),
        ),
      );
    });

    test('新源沒有目錄時丟 StateError', () async {
      final candidate = _candidate('new-origin');
      final service = SourceSwitchService(
        service: _FakeBookSourceService(
          chapters: const <BookChapter>[],
          throwOnChapterList: true,
        ),
        sourceDao: db.bookSourceDao,
      );

      expect(
        () => service.resolveSwitch(
          _currentBook(),
          candidate,
          targetChapterIndex: 5,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            '新來源沒有可用目錄',
          ),
        ),
      );
    });

    test('找不到對應書源時丟 StateError', () async {
      final candidate = _candidate('missing-origin');
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: _chapters('x', 3)),
        sourceDao: db.bookSourceDao,
      );

      expect(
        () => service.resolveSwitch(_currentBook(), candidate),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            '找不到對應書源',
          ),
        ),
      );
    });
  });

  group('SourceSwitchService.persistSwitch', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.bookSourceDao.upsert(_source('new-origin', '新源'));
    });

    tearDown(() async {
      await db.close();
    });

    test('遷移到不同 bookUrl 時刪除舊 row、寫入新 book 與章節', () async {
      final oldBook = _currentBook();
      // 預先把舊書與舊章節寫進 DB，模擬書架既有狀態。
      await db.bookDao.upsert(oldBook);
      await db.chapterDao.insertChapters(_chapters(oldBook.bookUrl, 3));

      final candidate = _candidate('new-origin');
      final chapters = _chapters(candidate.bookUrl, 100);
      final service = SourceSwitchService(
        service: _FakeBookSourceService(chapters: chapters),
        sourceDao: db.bookSourceDao,
      );

      final resolution = await service.resolveSwitch(
        oldBook,
        candidate,
        targetChapterIndex: 5,
        targetChapterTitle: '第6章',
        validateTargetContent: true,
      );

      await service.persistSwitch(
        oldBook,
        resolution,
        bookDao: db.bookDao,
        chapterDao: db.chapterDao,
      );

      // 舊書 row 與舊章節已刪除。
      expect(await db.bookDao.getByUrl(oldBook.bookUrl), isNull);
      expect(await db.chapterDao.getByBook(oldBook.bookUrl), isEmpty);

      // 新書 row 與新章節已寫入。
      final migrated = await db.bookDao.getByUrl(
        resolution.migratedBook.bookUrl,
      );
      expect(migrated, isNotNull);
      expect(migrated!.origin, 'new-origin');
      expect(migrated.isInBookshelf, isTrue);
      final newChapters = await db.chapterDao.getByBook(
        resolution.migratedBook.bookUrl,
      );
      expect(newChapters.length, 100);
    });
  });
}
