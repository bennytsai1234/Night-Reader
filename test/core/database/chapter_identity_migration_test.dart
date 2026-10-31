import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/chapter.dart';

import 'legacy_chapters_table.dart';

void main() {
  test('a schema 7 table of contents upgrades whole and then keeps two books '
      'with the same chapter URL apart', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(legacyChaptersTable);
          raw.execute(
            'INSERT INTO chapters (url, title, isVolume, bookUrl, "index", '
            'variable) VALUES '
            "('第一卷0', '第一卷', 1, 'book-A', 0, NULL), "
            "('a/1', '第一章', 0, 'book-A', 1, '{\"k\":\"v\"}')",
          );
          raw.execute('PRAGMA user_version = 7');
        },
      ),
    );
    addTearDown(db.close);
    final dao = ChapterDao(db);

    final upgraded = await dao.getByBook('book-A');
    expect(upgraded.map((c) => (c.url, c.title, c.isVolume, c.index)), [
      ('第一卷0', '第一卷', true, 0),
      ('a/1', '第一章', false, 1),
    ]);
    expect(upgraded.last.variable, '{"k":"v"}');

    await dao.insertChapters([
      BookChapter(
        url: '第一卷0',
        title: '第一卷',
        bookUrl: 'book-B',
        index: 0,
        isVolume: true,
      ),
    ]);
    expect((await dao.getByBook('book-A')).length, 2);
    expect((await dao.getByBook('book-B')).single.url, '第一卷0');

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'idx_chapters_book_index'",
        )
        .get();
    expect(indexes, hasLength(1), reason: '重建表之後章節的索引還在');
  });
}
