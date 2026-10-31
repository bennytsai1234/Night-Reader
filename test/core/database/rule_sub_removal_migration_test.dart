import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';

import 'legacy_chapters_table.dart';

/// 書源訂閱移除的遷移契約：舊版（schema 4）資料庫升級後，rule_subs 與更早
/// 移除時留下的 source_subscriptions 連同索引都被刪除，資料庫仍可正常開啟。
void main() {
  test('upgrading from schema 4 drops the subscription tables', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE rule_subs (id INTEGER PRIMARY KEY, name TEXT, '
            'url TEXT, "order" INTEGER)',
          );
          raw.execute(
            'CREATE INDEX idx_rule_subs_order ON rule_subs ("order")',
          );
          raw.execute(
            "INSERT INTO rule_subs (name, url) VALUES ('a', 'https://a')",
          );
          raw.execute(
            'CREATE TABLE source_subscriptions (url TEXT PRIMARY KEY, '
            'name TEXT, "order" INTEGER)',
          );
          raw.execute(
            'CREATE INDEX idx_source_subscriptions_order '
            'ON source_subscriptions ("order")',
          );
          // schema 4 本來就有下載佇列表；之後的遷移（schema 6）會改它。
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
              addTime INTEGER NOT NULL DEFAULT 0,
              sortOrder INTEGER NOT NULL DEFAULT 0
            )''');
          raw.execute(legacyChaptersTable);
          raw.execute('PRAGMA user_version = 4');
        },
      ),
    );
    addTearDown(db.close);

    final leftovers = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name IN "
          "('rule_subs', 'idx_rule_subs_order', 'source_subscriptions', "
          "'idx_source_subscriptions_order')",
        )
        .get();
    expect(leftovers, isEmpty);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, db.schemaVersion);
  });
}
