import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';

const _unusedTables = [
  'dict_rules',
  'http_tts_table',
  'servers',
  'txt_toc_rules',
  'keyboard_assists',
];

/// 從 Legado 帶過來、從沒有功能讀寫的五張表（字典規則、線上朗讀引擎、
/// 伺服器、TXT 目錄規則、鍵盤輔助）：舊版（schema 20）升級後連同索引刪掉，
/// 新建的資料庫也沒有。
void main() {
  Future<List<String>> leftovers(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE name IN "
          "(${[..._unusedTables, 'idx_txt_toc_rules_enabled_serial', 'idx_keyboard_assists_serial'].map((n) => "'$n'").join(', ')})",
        )
        .get();
    return [for (final row in rows) row.read<String>('name')];
  }

  test('upgrading from schema 20 drops the unused Legado tables', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          for (final table in _unusedTables) {
            raw.execute('CREATE TABLE $table (id INTEGER PRIMARY KEY)');
          }
          raw.execute(
            'CREATE INDEX idx_txt_toc_rules_enabled_serial ON txt_toc_rules (id)',
          );
          raw.execute(
            'CREATE INDEX idx_keyboard_assists_serial ON keyboard_assists (id)',
          );
          raw.execute('PRAGMA user_version = 20');
        },
      ),
    );
    addTearDown(db.close);

    expect(await leftovers(db), isEmpty);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, db.schemaVersion);
  });

  test('a new database has none of them', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(await leftovers(db), isEmpty);
  });
}
