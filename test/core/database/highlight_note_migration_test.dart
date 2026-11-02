import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';

/// 標註的備忘（schema 12）：schema 11 的標註表補上備忘欄，原本的標註留著、
/// 備忘是空的。
void main() {
  test(
    'upgrading from schema 11 adds an empty note to existing highlights',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('''
            CREATE TABLE highlights (
              id INTEGER NOT NULL PRIMARY KEY,
              bookName TEXT NOT NULL,
              bookAuthor TEXT NOT NULL DEFAULT '',
              chapterIndex INTEGER NOT NULL DEFAULT 0,
              chapterTitle TEXT NOT NULL DEFAULT '',
              charOffset INTEGER NOT NULL DEFAULT 0,
              anchor TEXT NULL,
              quote TEXT NOT NULL DEFAULT '',
              color TEXT NOT NULL DEFAULT 'amber',
              style TEXT NOT NULL DEFAULT 'fill'
            )''');
            raw.execute(
              "INSERT INTO highlights (id, bookName, quote, color) "
              "VALUES (7, '夜雨聽書', '雨聲', 'blue')",
            );
            raw.execute('PRAGMA user_version = 11');
          },
        ),
      );
      addTearDown(db.close);

      final dao = HighlightDao(db);
      final kept = (await dao.getAll()).single;
      expect(kept.id, 7);
      expect(kept.quote, '雨聲');
      expect(kept.note, '');
      await dao.upsertAll([kept.copyWith(note: '窗外')]);
      expect((await dao.getAll()).single.note, '窗外');
    },
  );
}
