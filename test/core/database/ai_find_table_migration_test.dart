import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/book_source.dart';

void main() {
  // 同一個檔案先後開兩次（建好、再照舊版本重開），是刻意的。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test(
    'upgrading to schema 19 adds the past finds and keeps the sources',
    () async {
      final dir = await Directory.systemTemp.createTemp('nr-ai-find');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/app.db');

      final current = AppDatabase.forTesting(NativeDatabase(file));
      await BookSourceDao(current).insertOrUpdateAll([
        BookSource(bookSourceUrl: 'https://a.test', bookSourceName: '甲'),
      ]);
      await current.close();

      // schema 18 還沒有過去的找書。
      final old = AppDatabase.forTesting(
        NativeDatabase(
          file,
          setup: (raw) => raw
            ..execute('DROP TABLE ai_find_records')
            ..execute('PRAGMA user_version = 18'),
        ),
      );
      addTearDown(old.close);

      expect(
        (await BookSourceDao(old).getByUrl('https://a.test'))!.bookSourceName,
        '甲',
      );
      final dao = AiFindDao(old);
      expect(await dao.getNewestFirst(), isEmpty);
      await dao.upsert(
        AiFindRecord(
          id: 'x',
          description: '修仙',
          depth: 'normal',
          createdAt: 1,
          outcome: AiFindOutcome.found,
        ),
      );
      expect((await dao.getNewestFirst()).single.description, '修仙');
    },
  );
}
