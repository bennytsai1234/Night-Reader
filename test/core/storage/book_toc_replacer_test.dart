import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/book_toc_replacer.dart';

void main() {
  late AppDatabase db;
  late ChapterDao chapterDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chapterDao = ChapterDao(db);
  });

  tearDown(() => db.close());

  List<BookChapter> toc(String host, List<String> titles) => [
    for (final (i, title) in titles.indexed)
      BookChapter(
        url: 'https://$host/c/$i',
        title: title,
        bookUrl: 'https://s.example/book/1',
        index: i,
      ),
  ];

  test('檢查更新時章節網址全換了、章號改寫成中文數字：進度對回讀到的那一章', () async {
    final book = Book(
      bookUrl: 'https://s.example/book/1',
      origin: 'https://s.example',
      name: '書',
      chapterIndex: 2,
      durChapterTitle: '第3章 風起',
      durChapterTime: 1,
    );
    await chapterDao.replaceByBook(
      book.bookUrl,
      toc('old.example', ['第1章 開端', '第2章 雲湧', '第3章 風起', '第4章 雨落']),
    );

    final result = await BookTocReplacer(chapterDao: chapterDao).replace(
      book,
      toc('new.example', ['序章', '第一章 開端', '第二章 雲湧', '第三章 風起', '第四章 雨落']),
    );

    expect(book.chapterIndex, 3);
    expect(book.durChapterTitle, '第三章 風起');
    expect(result.chapters[book.chapterIndex].url, 'https://new.example/c/3');
    expect(result.chapters, hasLength(5));
  });

  Book reading(int index, String title) => Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
    chapterIndex: index,
    durChapterTitle: title,
    durChapterTime: 1,
  );

  test('正在讀的「大戰（上）」被書源拿掉、「大戰（下）」還在：留著，進度不動', () async {
    final book = reading(1, '大戰（上）');
    final old = toc('s.example', ['序', '大戰（上）', '大戰（下）', '尾聲']);
    await chapterDao.replaceByBook(book.bookUrl, old);

    final result = await BookTocReplacer(chapterDao: chapterDao)
        .replace(book, [old[0], old[2], old[3]]);

    expect(result.chapters.map((c) => c.title), ['序', '大戰（上）', '大戰（下）', '尾聲']);
    expect(result.chapters[book.chapterIndex].url, old[1].url);
    expect(result.progressMoved, isFalse);
  });

  test('書源只回最新 100 章、章名都是「正文」：已下載與正在讀的舊章留著，進度不動', () async {
    final book = reading(120, '正文');
    final old = toc('s.example', [for (var i = 0; i < 240; i++) '正文']);
    await chapterDao.replaceByBook(book.bookUrl, old);
    final contentDao = ReaderChapterContentDao(db);
    await contentDao.saveContent(
      contentKey: ReaderChapterContentDao.contentKey(
        origin: book.origin,
        bookUrl: book.bookUrl,
        chapterUrl: old[60].url,
      ),
      origin: book.origin,
      bookUrl: book.bookUrl,
      chapterUrl: old[60].url,
      chapterIndex: 60,
      content: '已下載的正文',
      updatedAt: 1,
    );

    final result = await BookTocReplacer(
      chapterDao: chapterDao,
      contentDao: contentDao,
    ).replace(book, old.sublist(140));

    final urls = result.chapters.map((c) => c.url).toList();
    expect(urls, containsAll([old[60].url, old[120].url]));
    expect(urls, hasLength(102));
    expect(result.chapters[book.chapterIndex].url, old[120].url);
  });

  test('沒有章名的「第3章」改寫成「第三章」、網址全換：判成同一章，進度對過去', () async {
    final book = reading(2, '第3章');
    await chapterDao.replaceByBook(
      book.bookUrl,
      toc('old.example', ['第1章', '第2章', '第3章', '第4章']),
    );

    final result = await BookTocReplacer(chapterDao: chapterDao)
        .replace(book, toc('new.example', ['第一章', '第二章', '第三章', '第四章']));

    expect(result.chapters, hasLength(4));
    expect(result.chapters[book.chapterIndex].title, '第三章');
  });

  group('書源換了部分章節網址', () {
    // 60 章，書源換了前 25 章的網址，正在讀的「第25章 風起」改成「第二十五章
    // 風起」。
    List<BookChapter> forward({required bool moved}) => [
      for (var n = 1; n <= 60; n++)
        BookChapter(
          url: moved && n <= 25
              ? 'https://new.example/c/$n'
              : 'https://old.example/c/$n',
          title: n == 25 ? (moved ? '第二十五章 風起' : '第25章 風起') : '第$n章 名$n',
          bookUrl: 'https://s.example/book/1',
        ),
    ];
    List<BookChapter> numbered(List<BookChapter> chapters) => [
      for (final (i, chapter) in chapters.indexed) chapter.copyWith(index: i),
    ];

    for (final reversed in [false, true]) {
      test(reversed ? '反轉目錄：不多留一章，進度對到新網址' : '正向：不多留一章，進度對到新網址', () async {
        List<BookChapter> ordered(List<BookChapter> chapters) =>
            numbered(reversed ? chapters.reversed.toList() : chapters);
        final old = ordered(forward(moved: false));
        final at = old.indexWhere((c) => c.title == '第25章 風起');
        final book = reading(at, '第25章 風起');
        await chapterDao.replaceByBook(book.bookUrl, old);

        final result = await BookTocReplacer(chapterDao: chapterDao)
            .replace(book, ordered(forward(moved: true)));

        expect(result.chapters, hasLength(60));
        expect(
          result.chapters[book.chapterIndex].url,
          'https://new.example/c/25',
        );
        expect(book.durChapterTitle, '第二十五章 風起');
        // 每一章換掉的網址都記下新網址，開著的閱讀器存進度照它找。
        expect(result.moved, hasLength(25));
        expect(
          result.moved['https://old.example/c/3'],
          'https://new.example/c/3',
        );
        expect(
          result.moved['https://old.example/c/25'],
          'https://new.example/c/25',
        );
      });
    }
  });

  test('「番外（校訂）」換網址並改名「番外」：進度對到它，不是網址沒變的另一篇「番外」', () async {
    final old = toc('s.example', ['第1章 甲', '第2章 乙', '第3章 丙', '番外', '番外（校訂）']);
    final book = reading(4, '番外（校訂）');
    await chapterDao.replaceByBook(book.bookUrl, old);
    final renamed = BookChapter(
      url: 'https://new.example/extra',
      title: '番外',
      bookUrl: book.bookUrl,
    );
    // 網站把改過的番外移到最前面。
    final fetched = [
      for (final (i, chapter) in [renamed, ...old.sublist(0, 4)].indexed)
        chapter.copyWith(index: i),
    ];

    final result = await BookTocReplacer(chapterDao: chapterDao)
        .replace(book, fetched);

    expect(result.chapters, hasLength(5));
    expect(result.chapters[book.chapterIndex].url, renamed.url);
    expect(result.moved, {old[4].url: renamed.url});
  });

  group('分段章節（上）（下）', () {
    BookChapter chapter(String url, String title) => BookChapter(
      url: url,
      title: title,
      bookUrl: 'https://s.example/book/1',
    );

    test('新目錄只剩換了網址的「（上）」：舊的「（下）」留著、不記成換網址', () {
      final old = [
        chapter('https://old.example/1', '第1章 序'),
        chapter('https://old.example/10a', '第10章 大戰（上）'),
        chapter('https://old.example/10b', '第10章 大戰（下）'),
        chapter('https://old.example/11', '第11章 尾'),
      ];
      final newUp = chapter('https://new.example/10a', '第10章 大戰（上）');
      final result = mergeFetchedToc(
        oldToc: old,
        fetched: [old[0], newUp, old[3]],
        keep: (chapter) => chapter.url == old[2].url,
      );

      expect(result.moved, {old[1].url: newUp.url});
      // 留下的「（下）」接在換了網址的「（上）」後面。
      expect(result.chapters.map((c) => c.url), [
        old[0].url,
        newUp.url,
        old[2].url,
        old[3].url,
      ]);
    });

    test('兩半都換了網址：舊的「（下）」對到新的「（下）」，不是「（上）」', () {
      final old = [
        chapter('https://old.example/1', '第1章 序'),
        chapter('https://old.example/10a', '第10章 大戰（上）'),
        chapter('https://old.example/10b', '第10章 大戰（下）'),
        chapter('https://old.example/11', '第11章 尾'),
      ];
      final newUp = chapter('https://new.example/10a', '第十章 大戰（上）');
      final newDown = chapter('https://new.example/10b', '第十章 大戰（下）');
      // 多兩章，照比例估的位置落在「（上）」。
      final result = mergeFetchedToc(
        oldToc: old,
        fetched: [
          old[0],
          chapter('https://new.example/x1', '作品相關1'),
          chapter('https://new.example/x2', '作品相關2'),
          newUp,
          newDown,
          old[3],
        ],
        keep: (_) => true,
      );

      expect(result.moved, {old[1].url: newUp.url, old[2].url: newDown.url});
      expect(result.chapters, hasLength(6));
    });
  });
}
