import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book.dart';

void main() {
  // 同一個檔案先後開兩次（建好、再照舊版本重開），是刻意的。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('upgrading to schema 9 estimates when each book last moved', () async {
    final dir = await Directory.systemTemp.createTemp('nr-progress-time');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    final current = AppDatabase.forTesting(NativeDatabase(file));
    await BookDao(current).upsert(
      Book(bookUrl: 'u', name: '夜航', isInBookshelf: true, durChapterTime: 500),
    );
    await current.close();

    // 退回 schema 8：還沒有 progressTime。
    final old = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('ALTER TABLE books DROP COLUMN progressTime');
          raw.execute('PRAGMA user_version = 8');
        },
      ),
    );
    addTearDown(old.close);

    final book = await BookDao(old).getByUrl('u');
    expect(book!.progressTime, 500);
  });

  test('progress time moves only when the reading position moves', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = BookDao(db);
    await dao.upsert(
      Book(
        bookUrl: 'u',
        name: '夜航',
        chapterIndex: 1,
        durChapterTitle: '第一章',
        charOffset: 10,
        progressTime: 100,
      ),
    );

    // 開書沒翻頁；目錄重新編號只改了序號。
    expect(await dao.updateProgress('u', 1, '第一章', 10), isNull);
    expect(await dao.updateProgress('u', 2, '第一章', 10), isNull);
    expect((await dao.getByUrl('u'))!.progressTime, 100);

    final moved = await dao.updateProgress('u', 2, '第一章', 40);
    expect(moved, isNotNull);
    expect((await dao.getByUrl('u'))!.progressTime, moved);
  });
}
