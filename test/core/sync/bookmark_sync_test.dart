import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/sync_store_blobs.dart';

import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/sync/bookmark_sync.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore with SyncStoreBlobs implements SyncStore {
  final Map<String, String> files = {};

  @override
  Future<void> check() async {}

  @override
  Future<SyncFile?> read(String name) async =>
      files[name] == null ? null : SyncFile(files[name]!);

  @override
  Future<String?> version(String name) async => null;

  @override
  Future<void> write(
    String name,
    String content, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async => files[name] = content;
}

void main() {
  late _MemoryStore store;
  late Directory temp;

  // 兩台手機各一個資料庫，是刻意的。
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = _MemoryStore();
    temp = await Directory.systemTemp.createTemp('nr-sync-bookmarks');
    addTearDown(() => temp.delete(recursive: true));
  });

  ({SyncService sync, BookmarkDao dao}) phone(String name) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = BookmarkDao(db);
    return (
      sync: SyncService(
        settings: SyncSettings(),
        bases: SyncBaseStorage(
          directory: () async => Directory('${temp.path}/$name'),
        ),
        storeFactory: (_, _, _) => store,
        kinds: (_) => [BookmarkSync(dao: dao)],
      ),
      dao: dao,
    );
  }

  Bookmark mark({int chapterIndex = 3}) => Bookmark(
    id: 0,
    bookName: '夜雨聽書',
    bookAuthor: '沈知秋',
    chapterIndex: chapterIndex,
    chapterTitle: '第三章 松煙墨',
    charOffset: 120,
    excerpt: '那是只有百年以上的松煙墨才會有的味道',
  );

  test('a bookmark added on one phone shows up on the other, and deleting '
      'it there deletes it here too', () async {
    final a = phone('a');
    final b = phone('b');
    final saved = await a.dao.add(mark());
    await a.sync.syncAll();
    await b.sync.syncAll();

    final onB = (await b.dao.getAll()).single;
    expect(onB.id, saved.id);
    expect(onB.bookName, '夜雨聽書');
    expect(onB.chapterTitle, '第三章 松煙墨');
    expect(onB.charOffset, 120);
    expect(onB.excerpt, saved.excerpt);

    await b.dao.deleteByIds([saved.id]);
    await b.sync.syncAll();
    await a.sync.syncAll();
    expect(await a.dao.getAll(), isEmpty);
  });

  test('a bookmark from an older version still carrying "作者：" lands on '
      'the cleaned book, and is not sent back', () async {
    final a = phone('a');
    final b = phone('b');
    // A 是還沒升級的舊版：作者帶著字樣。
    await a.dao.add(mark().copyWith(bookAuthor: '作者：沈知秋'));
    await a.sync.syncAll();
    final sent = store.files[BookmarkSync(dao: b.dao).fileName];

    await b.sync.syncAll();
    expect((await b.dao.getAll()).single.bookAuthor, '沈知秋');
    await b.sync.syncAll();
    expect(store.files[BookmarkSync(dao: b.dao).fileName], sent);
  });

  test('the chapter number alone is not a change: a phone whose source '
      'numbers chapters differently does not send its copy back', () async {
    final a = phone('a');
    final b = phone('b');
    final saved = await a.dao.add(mark());
    await a.sync.syncAll();
    await b.sync.syncAll();
    final before = store.files[BookmarkSync(dao: b.dao).fileName];

    // B 換了書源，同一章在新目錄是第 5 章。
    await b.dao.upsertAll([saved.copyWith(chapterIndex: 5)]);
    await b.sync.syncAll();
    expect(store.files[BookmarkSync(dao: b.dao).fileName], before);

    await a.sync.syncAll();
    expect((await a.dao.getAll()).single.chapterIndex, 3);
  });

  test('two phones never hand out the same number, even in the same '
      'millisecond or after a clock that ran fast', () {
    const now = 1790000000000;
    // 兩台同一毫秒新增。
    final a = BookmarkDao.newId(now, 0, Random(1));
    final b = BookmarkDao.newId(now, 0, Random(2));
    expect(a, isNot(b));
    // 兩台都同步到一個比現在大的編號（某台時鐘曾經偏快），各自接在後面。
    final ahead = (now + 60000) * 1000;
    final c = BookmarkDao.newId(now, ahead, Random(1));
    final d = BookmarkDao.newId(now, ahead, Random(2));
    expect([c, d], everyElement(greaterThan(ahead)));
    expect(c, isNot(d));
    // 後建立的編號比較大（「最近留過書籤的書」照它排）。
    expect(
      BookmarkDao.newId(now + 1, 0, Random(3)),
      greaterThan(BookmarkDao.newId(now, 0, Random(4))),
    );
  });

  test('two phones adding bookmarks at the same time keep both', () async {
    final a = phone('a');
    final b = phone('b');
    await a.dao.add(mark());
    await b.dao.add(mark(chapterIndex: 7));
    await a.sync.syncAll();
    await b.sync.syncAll();
    await a.sync.syncAll();

    expect(await a.dao.getAll(), hasLength(2));
    expect(await b.dao.getAll(), hasLength(2));
    final records = SyncDocument.decode(
      store.files[BookmarkSync(dao: a.dao).fileName]!,
    ).records;
    expect(records.values.where((r) => !r.deleted), hasLength(2));
  });
}
