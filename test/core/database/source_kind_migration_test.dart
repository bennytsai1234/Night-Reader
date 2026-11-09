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

  test('upgrading to schema 15 keeps comic and audio sources', () async {
    final dir = await Directory.systemTemp.createTemp('nr-source-kinds');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    final current = AppDatabase.forTesting(NativeDatabase(file));
    // schema 14 的夜讀匯入時把非小說書源停用、加上「非小說源」。
    await BookSourceDao(current).insertOrUpdateAll([
      BookSource(
        bookSourceUrl: 'https://comic.test',
        bookSourceName: '包子漫画',
        bookSourceGroup: '精選,$nonNovelSourceGroupTag',
        enabled: false,
        enabledExplore: false,
      ),
      BookSource(
        bookSourceUrl: 'https://audio.test',
        bookSourceName: '懒人听书',
        enabled: false,
      ),
      BookSource(
        bookSourceUrl: 'https://film.test',
        bookSourceName: '电影天堂',
        bookSourceGroup: nonNovelSourceGroupTag,
        enabled: false,
      ),
      BookSource(bookSourceUrl: 'https://novel.test', bookSourceName: '番茄小说'),
    ]);
    await current.close();

    final old = AppDatabase.forTesting(
      NativeDatabase(
        file,
        setup: (raw) => raw.execute('PRAGMA user_version = 14'),
      ),
    );
    addTearDown(old.close);

    final sources = {
      for (final s in await BookSourceDao(old).getAllPart()) s.bookSourceUrl: s,
    };
    final comic = sources['https://comic.test']!;
    expect(comic.bookSourceType, 2);
    expect(comic.groupTags, {'精選'});
    expect(comic.enabled, isTrue);
    expect(comic.enabledExplore, isTrue);
    // 沒有「非小說源」標記的停用是使用者自己關的，只補類型。
    final audio = sources['https://audio.test']!;
    expect(audio.bookSourceType, 1);
    expect(audio.enabled, isFalse);
    final film = sources['https://film.test']!;
    expect(film.sourceKind, BookSourceKind.unsupported);
    expect(film.enabled, isFalse);
    expect(sources['https://novel.test']!.sourceKind, BookSourceKind.novel);
  });
}
