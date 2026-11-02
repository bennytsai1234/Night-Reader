import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/models/bookmark.dart';

import 'legacy_books_table.dart';
import 'legacy_chapters_table.dart';

/// 書籤表的遷移：舊版（schema 2）照書的網址記的書籤表與索引刪掉，換成現在
/// 照書名加作者記的書籤表，升級後可以照常新增書籤。
void main() {
  test('upgrading from schema 2 replaces the old bookmarks table', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE bookmarks (id INTEGER PRIMARY KEY, bookUrl TEXT)',
          );
          raw.execute('CREATE INDEX idx_bookmarks_book ON bookmarks (bookUrl)');
          raw.execute("INSERT INTO bookmarks (bookUrl) VALUES ('book-a')");
          // 舊版本來就有下載佇列表；之後的遷移（schema 4、6）會改它。
          raw.execute('''
            CREATE TABLE download_tasks (
              bookUrl TEXT NOT NULL PRIMARY KEY,
              bookName TEXT NOT NULL,
              startChapterIndex INTEGER NOT NULL DEFAULT 0,
              endChapterIndex INTEGER NOT NULL DEFAULT 0,
              currentChapterIndex INTEGER NOT NULL DEFAULT 0,
              totalChapterCount INTEGER NOT NULL DEFAULT 0,
              status INTEGER NOT NULL DEFAULT 0,
              successCount INTEGER NOT NULL DEFAULT 0,
              errorCount INTEGER NOT NULL DEFAULT 0,
              addTime INTEGER NOT NULL DEFAULT 0
            )''');
          raw.execute(legacyChaptersTable);
          raw.execute(legacyBooksTable);
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(db.close);

    final leftovers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name = 'idx_bookmarks_book'",
        )
        .get();
    expect(leftovers, isEmpty);
    final dao = BookmarkDao(db);
    expect(await dao.getAll(), isEmpty, reason: '舊表的資料不搬');
    final saved = await dao.add(
      Bookmark(id: 0, bookName: '夜雨聽書', chapterTitle: '第一章', charOffset: 12),
    );
    expect((await dao.getAll()).single.id, saved.id);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, db.schemaVersion);
  });
}
