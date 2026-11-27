import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';

/// 書源網站：記下每次抓正文用的書源網址。
class _Site extends BookSourceService {
  final List<String> fetchedWith = [];

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    fetchedWith.add(source.bookSourceUrl);
    return '${chapter.title}的正文，從頭到尾完整，字數夠長，讀得到。';
  }
}

/// 閱讀器開著時別處（書源編輯、AI 修復、同步、合併重複書源）換了這本書的
/// 書源網址：之後翻到的章照新書源抓，已下載的正文照新網址讀。
void main() {
  const oldUrl = 'https://old.example';
  const newUrl = 'https://new.example';

  late AppDatabase db;
  late _Site site;
  late Book book;
  late ReaderChapterRepository repository;

  final chapters = [
    for (var i = 0; i < 3; i++)
      BookChapter(
        url: '$oldUrl/c/$i.html',
        title: '第${i + 1}章',
        index: i,
        bookUrl: '$oldUrl/book/1',
      ),
  ];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    site = _Site();
    await db.bookSourceDao.upsert(
      BookSource(bookSourceUrl: oldUrl, bookSourceName: '舊書源'),
    );
    book = Book(
      bookUrl: '$oldUrl/book/1',
      origin: oldUrl,
      originName: '舊書源',
      name: '夜雨聽書',
      author: '沈知秋',
      isInBookshelf: true,
    );
    await db.bookDao.upsert(book);
    await db.chapterDao.insertChapters(chapters);
    repository = ReaderChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      contentDao: db.readerChapterContentDao,
      service: site,
    );
  });

  tearDown(() async {
    repository.dispose();
    await db.close();
  });

  /// 資料庫裡的書源、書與正文都搬到 [newUrl]，再發搬家（同
  /// `BookSourceService.saveEditedSource`）。
  Future<void> moveSource() async {
    await db.bookSourceDao.upsert(
      BookSource(bookSourceUrl: newUrl, bookSourceName: '新書源'),
    );
    await db.bookDao.moveOrigin(oldUrl, newUrl, toName: '新書源');
    await db.readerChapterContentDao.moveOrigin(oldUrl, newUrl);
    AppEventBus().fire(
      AppEventBus.sourceMoved,
      data: const SourceMovedEvent(fromUrl: oldUrl, toUrl: newUrl),
    );
    await pumpEventQueue();
  }

  test('翻到的下一章照新書源抓、存在新網址底下', () async {
    await repository.loadContent(0);
    expect(site.fetchedWith, [oldUrl]);

    await moveSource();
    await repository.loadContent(1);

    expect(book.origin, newUrl);
    expect(book.originName, '新書源');
    expect(site.fetchedWith, [oldUrl, newUrl]);
    final key = ReaderChapterContentDao.contentKey(
      origin: newUrl,
      bookUrl: book.bookUrl,
      chapterUrl: chapters[1].url,
    );
    expect(
      await db.readerChapterContentDao.getContent(contentKey: key),
      isNotNull,
    );
  });

  test('搬家前下載好的章照新網址讀得到，不再向書源抓', () async {
    await repository.loadContent(0);
    await moveSource();
    // 快取的那份不算：關掉再開同一本（同一個 Book）。
    repository.dispose();
    repository = ReaderChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: db.bookDao,
      chapterDao: db.chapterDao,
      sourceDao: db.bookSourceDao,
      contentDao: db.readerChapterContentDao,
      service: site,
    );

    await repository.loadContent(0);

    expect(site.fetchedWith, [oldUrl]);
  });

  test('同一本書的另一個頁面先改了網址，閱讀器照樣換上新書源', () async {
    await repository.loadContent(0);
    final moved = <String>[];
    repository.onOriginMoved = () => moved.add(book.origin);
    book.origin = newUrl;

    await moveSource();
    await repository.loadContent(1);

    expect(site.fetchedWith, [oldUrl, newUrl]);
    expect(moved, [newUrl]);
  });

  test('別的書源搬家，閱讀器不動', () async {
    await repository.loadContent(0);
    var moved = 0;
    repository.onOriginMoved = () => moved++;

    AppEventBus().fire(
      AppEventBus.sourceMoved,
      data: const SourceMovedEvent(
        fromUrl: 'https://other.example',
        toUrl: 'https://other-new.example',
      ),
    );
    await pumpEventQueue();
    await repository.loadContent(1);

    expect(book.origin, oldUrl);
    expect(site.fetchedWith, [oldUrl, oldUrl]);
    expect(moved, 0);
  });
}
