import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/moved_chapters.dart';

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
}
