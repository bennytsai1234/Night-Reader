import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';

void main() {
  // 同一個檔案先後開兩次（建好、再照舊版本重開），是刻意的。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test(
    'upgrading to schema 18 adds the check time to existing sources',
    () async {
      final dir = await Directory.systemTemp.createTemp('nr-check-time');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.db');

      final current = AppDatabase.forTesting(NativeDatabase(file));
      await BookSourceDao(current).insertOrUpdateAll([
        BookSource(bookSourceUrl: 'https://a.test', bookSourceName: '甲'),
      ]);
      await current.close();

      // schema 17 的書源表還沒有這一欄。
      final old = AppDatabase.forTesting(
        NativeDatabase(
          file,
          setup: (raw) => raw
            ..execute('ALTER TABLE book_sources DROP COLUMN lastCheckTime')
            ..execute('PRAGMA user_version = 17'),
        ),
      );
      addTearDown(old.close);

      final source = await BookSourceDao(old).getByUrl('https://a.test');
      expect(source!.bookSourceName, '甲');
      expect(source.lastCheckTime, 0);

      source.lastCheckTime = 42;
      await BookSourceDao(old).upsert(source);
      expect(
        (await BookSourceDao(old).getByUrl('https://a.test'))!.lastCheckTime,
        42,
      );
    },
  );

  test('the check time stays on this phone: it is not in the source JSON', () {
    final source = BookSource(
      bookSourceUrl: 'https://a.test',
      bookSourceName: '甲',
    )..lastCheckTime = 42;
    expect(source.toJson().containsKey('lastCheckTime'), isFalse);
    expect(BookSource.fromJson(source.toJson()).lastCheckTime, 0);
  });
}
