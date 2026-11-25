import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';

/// 書籤與標註記下章節序號時的目錄方向（schema 22，ADR 0085）：schema 21 的
/// 兩張表補上這一欄，原本的書籤與標註留著、方向是沒記（null）；之後存得進
/// 記下的方向。
void main() {
  test('upgrading from schema 21 adds an unrecorded TOC direction to existing '
      'bookmarks and highlights', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''
            CREATE TABLE bookmarks (
              id INTEGER NOT NULL PRIMARY KEY,
              bookName TEXT NOT NULL,
              bookAuthor TEXT NOT NULL DEFAULT '',
              chapterIndex INTEGER NOT NULL DEFAULT 0,
              chapterTitle TEXT NOT NULL DEFAULT '',
              charOffset INTEGER NOT NULL DEFAULT 0,
              anchor TEXT NULL,
              excerpt TEXT NOT NULL DEFAULT ''
            )''');
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
              style TEXT NOT NULL DEFAULT 'fill',
              note TEXT NOT NULL DEFAULT ''
            )''');
          raw.execute(
            "INSERT INTO bookmarks (id, bookName, chapterIndex, chapterTitle) "
            "VALUES (5, '夜雨聽書', 3, '番外')",
          );
          raw.execute(
            "INSERT INTO highlights (id, bookName, chapterIndex, quote) "
            "VALUES (7, '夜雨聽書', 1, '雨聲')",
          );
          raw.execute('PRAGMA user_version = 21');
        },
      ),
    );
    addTearDown(db.close);

    final bookmarks = BookmarkDao(db);
    final highlights = HighlightDao(db);
    final bookmark = (await bookmarks.getAll()).single;
    final highlight = (await highlights.getAll()).single;
    expect((bookmark.id, bookmark.chapterIndex), (5, 3));
    expect(bookmark.tocReversed, isNull);
    expect((highlight.id, highlight.quote), (7, '雨聲'));
    expect(highlight.tocReversed, isNull);

    await bookmarks.upsertAll([bookmark.copyWith(tocReversed: true)]);
    await highlights.upsertAll([highlight.copyWith(tocReversed: false)]);
    expect((await bookmarks.getAll()).single.tocReversed, isTrue);
    expect((await highlights.getAll()).single.tocReversed, isFalse);
  });
}
