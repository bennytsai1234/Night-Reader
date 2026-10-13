import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

void main() {
  late AppDatabase db;
  late ReaderChapterContentStore store;

  final book = Book(
    bookUrl: 'https://s.example/book/1',
    origin: 'https://s.example',
    name: '書',
  );

  BookChapter chapter(int index, String url, {bool isVolume = false}) =>
      BookChapter(
        url: url,
        title: url,
        index: index,
        bookUrl: book.bookUrl,
        isVolume: isVolume,
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = ReaderChapterContentStore(
      chapterDao: ChapterDao(db),
      contentDao: ReaderChapterContentDao(db),
    );
  });

  tearDown(() => db.close());

  test('a chapter inserted mid-TOC does not hide what is missing', () async {
    final a = chapter(0, '/c/a.html');
    final b = chapter(1, '/c/b.html');
    await store.saveRawContent(book: book, chapter: a, content: '甲');
    await store.saveRawContent(book: book, chapter: b, content: '乙');

    // 書源在 a 與 b 之間補了一章：b 的序號從 1 變成 2。
    final updated = [
      chapter(0, '/c/a.html'),
      chapter(1, '/c/x.html'),
      chapter(2, '/c/b.html'),
    ];

    final missing = await store.missingChapters(book: book, chapters: updated);

    expect(missing.map((c) => c.url), ['/c/x.html']);
  });

  test(
    'saving content from a stale snapshot keeps the current index',
    () async {
      final chapterDao = ChapterDao(db);
      final a = chapter(0, '/c/a.html');
      final b = chapter(1, '/c/b.html');
      await chapterDao.insertChapters([a, b]);
      // 下載拿到 b 的快照（序號 1）之後，書架檢查在 a、b 之間插了一章。
      await chapterDao.insertChapters([
        chapter(1, '/c/x.html'),
        chapter(2, '/c/b.html'),
      ]);

      await store.saveRawContent(
        book: book,
        chapter: b..variable = '{"k":"v"}',
        content: '乙',
      );
      await store.saveFailure(
        book: book,
        chapter: chapter(0, '/c/gone.html'),
        message: '失敗',
      );

      final rows = await chapterDao.getByBook(book.bookUrl);
      expect(rows.map((c) => (c.index, c.url)), [
        (0, '/c/a.html'),
        (1, '/c/x.html'),
        (2, '/c/b.html'),
      ]);
      expect(rows.last.variable, '{"k":"v"}');
    },
  );

  test('volume headings and chapters without a URL are never missing', () {
    final missing = chaptersMissingContent([
      chapter(0, '第一卷', isVolume: true),
      chapter(1, ''),
      chapter(2, '/c/1.html'),
    ], const <String>{});

    expect(missing.map((c) => c.url), ['/c/1.html']);
  });
}
