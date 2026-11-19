import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';

void main() {
  // 同一個檔案先後開兩次（建好、再照舊版本重開），是刻意的。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('upgrading to schema 20 drops the check marks Legado left on stored '
      'sources', () async {
    final checkedAt = DateTime(2026, 11, 1).millisecondsSinceEpoch;
    final dir = await Directory.systemTemp.createTemp('nr-foreign-marks');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    final current = AppDatabase.forTesting(NativeDatabase(file));
    await BookSourceDao(current).insertOrUpdateAll([
      BookSource(
        bookSourceUrl: 'https://legado.test',
        bookSourceName: 'Legado 校驗過',
        bookSourceGroup: '精品,搜索失效,正文失效',
        bookSourceComment: '// Error: 未获取到正文\n\n作者说明',
        lastCheckTime: checkedAt,
      ),
      BookSource(
        bookSourceUrl: 'https://checked.test',
        bookSourceName: '夜讀校驗過',
        bookSourceGroup:
            '$abnormalSourceGroupTag,$contentBrokenSourceGroupTag,网站失效',
        bookSourceComment: '// Error: 正文為空',
        lastCheckTime: checkedAt,
      ),
      BookSource(
        bookSourceUrl: 'https://clean.test',
        bookSourceName: '沒事',
        bookSourceGroup: '精品',
        lastCheckTime: checkedAt,
      ),
    ]);
    await current.close();

    final old = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (raw) => raw.execute('PRAGMA user_version = 19'),
      ),
    );
    addTearDown(old.close);
    final dao = BookSourceDao(old);

    final legado = (await dao.getByUrl('https://legado.test'))!;
    expect(legado.groupTags, {'精品'});
    expect(legado.bookSourceComment, '作者说明');
    expect(legado.lastCheckTime, 0);

    final checked = (await dao.getByUrl('https://checked.test'))!;
    expect(checked.groupTags, {
      abnormalSourceGroupTag,
      contentBrokenSourceGroupTag,
    });
    expect(checked.bookSourceComment, '// Error: 正文為空');
    expect(checked.lastCheckTime, checkedAt);

    final clean = (await dao.getByUrl('https://clean.test'))!;
    expect(clean.bookSourceGroup, '精品');
    expect(clean.lastCheckTime, checkedAt);
  });
}
