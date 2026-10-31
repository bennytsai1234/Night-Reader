import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';

import 'legacy_chapters_table.dart';

/// 書籤功能移除的遷移契約：舊版（schema 2）資料庫升級後，bookmarks 表與
/// 其索引被刪除，資料庫仍可正常開啟使用。
void main() {
  test('upgrading from schema 2 drops the bookmarks table', () async {
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
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(db.close);

    final leftovers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name IN "
          "('bookmarks', 'idx_bookmarks_book')",
        )
        .get();
    expect(leftovers, isEmpty);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, db.schemaVersion);
  });
}
