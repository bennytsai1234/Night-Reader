import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
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
}
