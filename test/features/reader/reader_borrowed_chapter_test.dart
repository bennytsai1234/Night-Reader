import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/source_switch/chapter_borrow.dart';
import 'package:night_reader/features/reader/chapter/reader_chapter_repository.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_progress_controller.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';

const _mainText = '主書源這一章的正文，後半是防盜的亂碼，讀者看不下去。';
const _borrowedText = '借來的這一章正文，從頭到尾完整，字數夠長，讀得到。';

/// 書源網站：每個網址回一段正文。
class _Site extends BookSourceService {
  _Site(this.bodies);

  final Map<String, String> bodies;

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async => bodies[chapter.url] ?? '';
}

class _SourceDao extends Fake implements BookSourceDao {
  _SourceDao(this.source);

  final BookSource source;

  @override
  Future<BookSource?> getByUrl(String url) async => source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ChapterDao chapterDao;
  late ReaderChapterContentDao contentDao;
  late ReaderRuntime runtime;
  late Map<String, String> mainBodies;

  final mainSource = BookSource(
    bookSourceUrl: 'https://main.example',
    bookSourceName: '主書源',
  );
  final lender = BookSource(
    bookSourceUrl: 'https://lender.example',
    bookSourceName: '借的書源',
  );
  final book = Book(
    bookUrl: 'https://main.example/book/1',
    origin: mainSource.bookSourceUrl,
    name: '夜雨聽書',
    author: '沈知秋',
  );
  final lenderBook = Book(
    bookUrl: 'https://lender.example/b/9',
    origin: lender.bookSourceUrl,
    name: '夜雨聽書',
    author: '沈知秋',
  );
  final chapters = [
    for (var i = 0; i < 2; i++)
      BookChapter(
        url: 'https://main.example/c/$i.html',
        title: '第${i + 1}章',
        index: i,
        bookUrl: book.bookUrl,
      ),
  ];
  final lenderChapters = [
    for (var i = 0; i < 2; i++)
      BookChapter(
        url: 'https://lender.example/c/$i.html',
        title: '第${i + 1}章',
        index: i,
        bookUrl: lenderBook.bookUrl,
      ),
  ];
  final spec = ReaderLayoutSpec.fromViewport(
    viewportSize: const Size(220, 180),
    style: const ReaderLayoutStyle(
      fontSize: 18,
      lineHeight: 1.5,
      letterSpacing: 0,
      paragraphSpacing: 0.8,
      paddingTop: 12,
      paddingBottom: 12,
      paddingLeft: 12,
      paddingRight: 12,
      textIndent: 2,
    ),
  );

  ReaderRuntime makeRuntime(ReaderLocation at) {
    final bookDao = BookDao(db);
    final repository = ReaderChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: bookDao,
      chapterDao: chapterDao,
      sourceDao: _SourceDao(mainSource),
      contentDao: contentDao,
      service: _Site(mainBodies),
    );
    return ReaderRuntime(
      book: book,
      repository: repository,
      progressController: ReaderProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: spec,
      initialLocation: at,
    )..registerViewportRestore(Object(), (_) async => true);
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chapterDao = ChapterDao(db);
    contentDao = ReaderChapterContentDao(db);
    await chapterDao.insertChapters(chapters);
    mainBodies = {
      chapters[0].url: '第一章的正文，好好的，讀得到。',
      chapters[1].url: _mainText,
    };
    runtime = makeRuntime(const ReaderLocation(chapterIndex: 0, charOffset: 0));
  });

  tearDown(() async {
    runtime.dispose();
    await db.close();
  });

  Future<void> borrowSecondChapter() => borrowChapter(
    book: book,
    chapter: runtime.chapterAt(1)!,
    source: lender,
    lenderBook: lenderBook,
    lenderChapters: lenderChapters,
    lenderIndex: 1,
    chapterDao: chapterDao,
    contentDao: contentDao,
    service: _Site({lenderChapters[1].url: _borrowedText}),
  );

  test('跳章取不到時借來的那一章：借源面板開著時主書源又抓到了，跳過去讀到的'
      '仍是借來的正文', () async {
    await runtime.openBook();
    // 跳章取不到、退回原處後預載相鄰的章，這次主書源抓到了。
    expect((await runtime.loadContentAt(1)).plainText, contains('防盜'));
    await borrowSecondChapter();
    final generationBefore = runtime.state.contentGeneration;

    await runtime.rereadStoredContent(1);
    await runtime.jumpToChapter(1);

    expect(runtime.state.visibleLocation.chapterIndex, 1);
    expect((await runtime.loadContentAt(1)).plainText, contains('借來的'));
    expect(
      runtime.state.contentGeneration,
      greaterThan(generationBefore),
      reason: '正文層手上排好的那一章也要換掉',
    );
  });

  test('開書失敗時借來的那一章，重讀後重開讀到的是借來的正文', () async {
    runtime.dispose();
    mainBodies[chapters[1].url] = '';
    const failed = ReaderLocation(chapterIndex: 1, charOffset: 0);
    runtime = makeRuntime(failed);
    await runtime.openBook();
    expect(runtime.state.unavailableMessage, isNotNull);
    await borrowSecondChapter();

    await runtime.rereadStoredContent(1);
    await runtime.openBook(at: failed);

    expect(runtime.state.hasStableWorld, isTrue);
    expect(runtime.state.visibleLocation.chapterIndex, 1);
    expect((await runtime.loadContentAt(1)).plainText, contains('借來的'));
  });
}
