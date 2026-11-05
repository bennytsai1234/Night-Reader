import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book.dart';

import 'legacy_download_tasks_table.dart';

void main() {
  // 同一個檔案先後開兩次（建好、再照舊版本重開），是刻意的。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('upgrading to schema 13 keeps every book and leaves the fingerprint '
      'to be filled in the background', () async {
    final dir = await Directory.systemTemp.createTemp('nr-fingerprint');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    final current = AppDatabase.forTesting(NativeDatabase(file));
    await BookDao(current).upsert(
      Book(
        bookUrl: 'local:///books/夜航.txt',
        name: '夜航',
        author: '本地',
        isInBookshelf: true,
        chapterIndex: 3,
        charOffset: 40,
        progressTime: 500,
      ),
    );
    await current.close();

    // 退回 schema 12：還沒有原檔指紋，也還沒有之後加的下載失敗欄位。
    final old = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (raw) {
          raw.execute('ALTER TABLE books DROP COLUMN fileFingerprint');
          dropDownloadFailureColumns.forEach(raw.execute);
          raw.execute('PRAGMA user_version = 12');
        },
      ),
    );
    addTearDown(old.close);

    final dao = BookDao(old);
    final book = (await dao.getByUrl('local:///books/夜航.txt'))!;
    expect(book.fileFingerprint, isNull);
    expect(book.chapterIndex, 3);
    expect(book.charOffset, 40);
    expect(book.progressTime, 500);

    await dao.updateFileFingerprint(book.bookUrl, 'abc');
    expect(
      (await dao.getInBookshelfByFingerprint('abc')).single.bookUrl,
      book.bookUrl,
    );
  });
}
