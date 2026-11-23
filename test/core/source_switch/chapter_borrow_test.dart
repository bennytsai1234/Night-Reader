import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/source_switch/chapter_borrow.dart';
import 'package:night_reader/core/storage/reader_chapter_content_store.dart';

const _borrowed = '借來的這一章正文，字數夠長，讀得到，用來通過可讀性檢查。';

/// 借的書源：記下抓了哪一本、哪一章、停點是哪裡；規則會改章節的欄位
/// （同真的書源規則寫 variable）。
class _LenderService extends BookSourceService {
  _LenderService({this.content = _borrowed, this.onFetch});

  final String content;
  final void Function()? onFetch;
  final List<(String bookUrl, String chapterUrl, String? stopAt)> fetched = [];

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    fetched.add((book.bookUrl, chapter.url, nextChapterUrl));
    chapter.variable = '{"page":"2"}';
    onFetch?.call();
    return content;
  }
}

void main() {
  late AppDatabase db;
  late ChapterDao chapterDao;
  late ReaderChapterContentDao contentDao;

  final book = Book(
    bookUrl: 'https://main.example/book/1',
    origin: 'https://main.example',
    name: '夜雨聽書',
    author: '沈知秋',
  );
  final source = BookSource(
    bookSourceUrl: 'https://lender.example',
    bookSourceName: '借的書源',
  );
  final lenderBook = Book(
    bookUrl: 'https://lender.example/b/9',
    origin: source.bookSourceUrl,
    name: '夜雨聽書',
    author: '沈知秋',
  );

  BookChapter mainChapter({bool locked = false}) => BookChapter(
    url: 'https://main.example/c/412.html',
    title: '第412章 夜雨',
    index: 411,
    bookUrl: book.bookUrl,
    wordCount: '1200',
    isVip: locked,
  );

  List<BookChapter> lenderToc() => [
    for (final (i, title) in [
      '第411章 風起',
      '第412章 夜雨',
      '第二卷',
      '第413章 雲散',
    ].indexed)
      BookChapter(
        url: title == '第二卷' ? '' : 'https://lender.example/c/$i.html',
        title: title,
        index: i,
        bookUrl: lenderBook.bookUrl,
        isVolume: title == '第二卷',
      ),
  ];

  Future<String> borrow(
    BookSourceService service, {
    List<BookChapter>? toc,
    int index = 1,
    CancelToken? cancelToken,
  }) => borrowChapter(
    book: book,
    chapter: mainChapter(),
    source: source,
    lenderBook: lenderBook,
    lenderChapters: toc ?? lenderToc(),
    lenderIndex: index,
    chapterDao: chapterDao,
    contentDao: contentDao,
    service: service,
    cancelToken: cancelToken,
  );

  Future<String?> stored() => ReaderChapterContentStore(
    chapterDao: chapterDao,
    contentDao: contentDao,
  ).getRawContent(book: book, chapter: mainChapter());

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chapterDao = ChapterDao(db);
    contentDao = ReaderChapterContentDao(db);
    await chapterDao.insertChapters([mainChapter()]);
  });

  tearDown(() => db.close());

  test('借來的正文蓋進主書源這一章，主書源的目錄不動', () async {
    await ReaderChapterContentStore(
      chapterDao: chapterDao,
      contentDao: contentDao,
    ).saveRawContent(book: book, chapter: mainChapter(), content: '防盜章');
    final toc = lenderToc();
    final service = _LenderService();

    expect(await borrow(service, toc: toc), _borrowed);

    expect(await stored(), _borrowed);
    // 抓的是借的書源那本書的那一章，停點是借的書源目錄的下一章（跳過分卷）。
    expect(service.fetched, [
      (
        lenderBook.bookUrl,
        'https://lender.example/c/1.html',
        'https://lender.example/c/3.html',
      ),
    ]);
    final current = await chapterDao.getByUrl(book.bookUrl, mainChapter().url);
    expect(current?.title, '第412章 夜雨');
    expect(current?.wordCount, '1200');
    expect(current?.variable, isNull);
    // 規則改的欄位落在複本上，借的書源的目錄留著原樣。
    expect(toc[1].variable, isNull);
  });

  test('借的是借的書源目錄最後一章時，停點用第一章', () async {
    final service = _LenderService();

    await borrow(service, index: 3);

    expect(service.fetched.single.$3, 'https://lender.example/c/0.html');
  });

  test('借來的正文讀不到時不存', () async {
    await expectLater(
      borrow(_LenderService(content: '短')),
      throwsA(isA<SourceException>()),
    );
    expect(await stored(), isNull);
  });

  test('主書源這一章在抓的期間改成付費章節時不存', () async {
    final service = _LenderService(
      onFetch: () => chapterDao.insertChapters([mainChapter(locked: true)]),
    );

    await expectLater(borrow(service), throwsA(isA<LockedChapterException>()));
    expect(await stored(), isNull);
  });

  test('主書源這一章已經不在目錄裡時不存', () async {
    await chapterDao.deleteByBook(book.bookUrl);

    await expectLater(
      borrow(_LenderService()),
      throwsA(isA<SourceException>()),
    );
  });

  test('抓完之前取消（關掉面板）就不存', () async {
    final cancelToken = CancelToken();
    final service = _LenderService(onFetch: cancelToken.cancel);

    await expectLater(
      borrow(service, cancelToken: cancelToken),
      throwsA(isA<DioException>()),
    );
    expect(await stored(), isNull);
  });

  test('分卷標題與付費章節不能借', () {
    final toc = lenderToc();
    expect(chapterBorrowable(toc[1]), isTrue);
    expect(chapterBorrowable(toc[2]), isFalse);
    expect(chapterBorrowable(toc[1].copyWith(isVip: true)), isFalse);
  });
}
