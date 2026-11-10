import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/highlight.dart';

/// 升級到 schema 16：書、書籤與標註的作者拿掉以前書籍詳情解析留下的
/// 「作者：」字樣，三張表一起改，書名加作者照樣對得上。
void main() {
  test('upgrading from schema 15 cleans "作者：" from books, bookmarks and '
      'highlights alike', () async {
    final dir = await Directory.systemTemp.createTemp('nr-author-cleanup');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    // 照現在的樣子建好、放進帶字樣的資料，再把版本號退回 15。
    final before = AppDatabase.forTesting(NativeDatabase(file));
    await BookDao(before).upsert(
      Book(bookUrl: 'b1', name: '夜航', author: '作者：某人', isInBookshelf: true),
    );
    await BookDao(before).upsert(
      Book(bookUrl: 'b2', name: '白晝', author: '某甲 著', isInBookshelf: true),
    );
    await BookDao(before).upsert(
      Book(bookUrl: 'b3', name: '作者手記', author: '作家', isInBookshelf: true),
    );
    await BookmarkDao(before)
        .add(Bookmark(id: 0, bookName: '夜航', bookAuthor: '作者：某人'));
    await HighlightDao(before)
        .add(Highlight(id: 0, bookName: '夜航', bookAuthor: '作者：某人', quote: '雨'));
    await before.customStatement('PRAGMA user_version = 15');
    await before.close();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final books = BookDao(db);
    expect((await books.getByUrl('b1'))!.author, '某人');
    expect((await books.getByUrl('b2'))!.author, '某甲');
    expect((await books.getByUrl('b3'))!.author, '作家', reason: '沒有字樣的不動');
    expect((await BookmarkDao(db).getAll()).single.bookAuthor, '某人');
    expect((await HighlightDao(db).getAll()).single.bookAuthor, '某人');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, db.schemaVersion);
  });
}
