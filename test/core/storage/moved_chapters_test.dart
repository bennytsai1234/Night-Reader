import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/moved_chapters.dart';

/// 記下讀了幾次整份目錄：對應記下來之後不該再讀。
class _CountingChapterDao extends ChapterDao {
  _CountingChapterDao(super.db);

  int reads = 0;

  @override
  Future<List<BookChapter>> getByBook(String bookUrl) {
    reads++;
    return super.getByBook(bookUrl);
  }
}

void main() {
  late AppDatabase db;
  late ChapterDao chapterDao;
  const bookUrl = 'https://s.example/book/1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chapterDao = ChapterDao(db);
    await chapterDao.replaceByBook(bookUrl, [
      for (final (i, url) in ['/a', '/b3', '/c'].indexed)
        BookChapter(
          url: 'https://s.example$url',
          title: url,
          bookUrl: bookUrl,
          index: i,
        ),
    ]);
  });

  tearDown(() async {
    MovedChapters.clear();
    await db.close();
  });

  Future<int?> indexOf(String path) =>
      MovedChapters.indexOf(chapterDao, bookUrl, 'https://s.example$path');

  List<BookChapter> titledToc() => [
    BookChapter(
      url: 'https://s.example/a',
      title: '第 1 章 開端',
      bookUrl: bookUrl,
      index: 0,
    ),
    BookChapter(
      url: 'https://s.example/x',
      title: '番外',
      bookUrl: bookUrl,
      index: 1,
    ),
    BookChapter(
      url: 'https://s.example/b4',
      title: '第 2 章',
      bookUrl: bookUrl,
      index: 2,
    ),
    BookChapter(
      url: 'https://s.example/c',
      title: '第 3 章 雲湧',
      bookUrl: bookUrl,
      index: 3,
    ),
  ];

  test('網址還在目錄裡就是它；換了網址照記下的新網址找；都沒有是 null', () async {
    MovedChapters.record(bookUrl, {
      'https://s.example/b2': 'https://s.example/b3',
    });
    expect(await indexOf('/c'), 2);
    expect(await indexOf('/b2'), 1);
    expect(await indexOf('/gone'), isNull);
  });

  test('換過兩次網址的章，第一次的網址也找得到', () async {
    MovedChapters.record(bookUrl, {
      'https://s.example/b1': 'https://s.example/b2',
    });
    MovedChapters.record(bookUrl, {
      'https://s.example/b2': 'https://s.example/b3',
    });
    expect(await indexOf('/b1'), 1);
  });

  test('別本書記下的對應不算', () async {
    MovedChapters.record('https://s.example/book/2', {
      'https://s.example/b2': 'https://s.example/b3',
    });
    expect(await indexOf('/b2'), isNull);
  });

  group('書源同時換了網址與序號、只認得章名', () {
    test('照章名與章號對到同一章，對應記下來，下次不必再讀整份目錄', () async {
      await chapterDao.replaceByBook(bookUrl, titledToc());
      final counting = _CountingChapterDao(db);

      expect(
        await MovedChapters.indexOf(
          counting,
          bookUrl,
          'https://s.example/b2',
          title: '第 2 章 風起',
          oldIndex: 1,
          oldTotalCount: 3,
        ),
        2,
      );
      expect(counting.reads, 1);
      // 認出的對應記下來了：再存一次直接照新網址找。
      expect(
        await MovedChapters.indexOf(
          counting,
          bookUrl,
          'https://s.example/b2',
          title: '第 2 章 風起',
          oldIndex: 1,
          oldTotalCount: 3,
        ),
        2,
      );
      expect(counting.reads, 1);
    });

    test('網址還在目錄裡時不比章名：同名的是別章也照網址', () async {
      await chapterDao.replaceByBook(bookUrl, [
        for (final (i, title) in ['第 1 章 開端', '第 2 章 風起', '第 2 章'].indexed)
          BookChapter(
            url: 'https://s.example/c/$i',
            title: title,
            bookUrl: bookUrl,
            index: i,
          ),
      ]);
      expect(
        await MovedChapters.indexOf(
          chapterDao,
          bookUrl,
          'https://s.example/c/0',
          title: '第 2 章 風起',
          oldIndex: 1,
          oldTotalCount: 3,
        ),
        0,
      );
    });

    test('目錄裡沒有這一章：不比章名，也不再讀整份目錄', () async {
      await chapterDao.replaceByBook(bookUrl, titledToc());
      final counting = _CountingChapterDao(db);

      for (var i = 0; i < 2; i++) {
        expect(
          await MovedChapters.indexOf(
            counting,
            bookUrl,
            'https://s.example/gone',
            title: '後記',
            oldIndex: 1,
            oldTotalCount: 3,
          ),
          isNull,
        );
      }
      expect(counting.reads, 1);

      // 換過目錄就再查一次。
      MovedChapters.record(bookUrl, {});
      expect(
        await MovedChapters.indexOf(
          counting,
          bookUrl,
          'https://s.example/gone',
          title: '後記',
          oldIndex: 1,
          oldTotalCount: 3,
        ),
        isNull,
      );
      expect(counting.reads, 2);
    });
  });
}
