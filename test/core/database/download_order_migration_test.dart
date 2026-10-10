import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';

void main() {
  test(
    'a schema 3 download queue upgrades in the order it was added',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            // schema 3 的 download_tasks：還沒有 sortOrder。
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
            // 加入順序 A、B，但 A 的進度比較晚更新：舊版依更新時間排會變成
            // B、A，升級後要照加入順序。
            raw.execute(
              "INSERT INTO download_tasks (bookUrl, bookName, addTime) "
              "VALUES ('a', 'A', 200), ('b', 'B', 100)",
            );
            raw.execute('PRAGMA user_version = 3');
          },
        ),
      );
      addTearDown(db.close);
      final dao = DownloadDao(db);

      final upgraded = await dao.getAll();
      expect(upgraded.map((t) => t.bookUrl), ['a', 'b']);

      // 使用者把 B 移到前面，寫回後重新讀取仍是 B、A。
      await dao.saveOrder(['b', 'a']);
      final reordered = await dao.getAll();
      expect(reordered.map((t) => t.bookUrl), ['b', 'a']);
      expect(reordered.map((t) => t.sortOrder), [0, 1]);
    },
  );
}
