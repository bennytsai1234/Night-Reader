import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/chapter.dart';

void main() {
  test('a long table of contents is read whole and in order', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ChapterDao(db);
    // 分批讀（一批 200）跨過好幾批，最後一批不滿；另一本書的章節不混進來。
    const count = 450;
    await dao.insertChapters([
      for (var i = count - 1; i >= 0; i--)
        BookChapter(url: 'u$i', title: '第$i章', bookUrl: 'book', index: i),
      BookChapter(url: 'other', title: '別本', bookUrl: 'other', index: 0),
    ]);

    final chapters = await dao.getByBook('book');

    expect(chapters.map((c) => c.index), [for (var i = 0; i < count; i++) i]);
    expect(chapters.map((c) => c.bookUrl).toSet(), {'book'});
  });

  test(
    'two books with the same chapter URL each keep their own chapter',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = ChapterDao(db);
      // 沒有連結的分卷由章名與序號補網址，兩本書的「第一卷」都是 `第一卷0`。
      BookChapter volume(String book) => BookChapter(
        url: '第一卷0',
        title: '第一卷',
        bookUrl: book,
        index: 0,
        isVolume: true,
      );
      await dao.insertChapters([volume('book-A')]);
      await dao.replaceByBook('book-B', [volume('book-B')]);

      await dao.updateFetchedChapter(
        volume('book-B').copyWith(variable: '{"from":"B"}', index: 5),
      );

      final a = (await dao.getByBook('book-A')).single;
      final b = (await dao.getByBook('book-B')).single;
      expect(a.variable, isNull, reason: '另一本書的寫回不改這一本');
      expect(b.variable, '{"from":"B"}');
      expect(b.index, 0, reason: '序號沿用資料庫的');
      expect((await dao.getByUrl('book-A', '第一卷0'))?.bookUrl, 'book-A');
    },
  );
}
