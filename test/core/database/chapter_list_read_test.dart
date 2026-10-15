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
}
