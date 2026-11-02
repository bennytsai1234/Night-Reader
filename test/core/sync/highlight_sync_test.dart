import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/sync/highlight_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/core/sync/sync_settings.dart';
import 'package:night_reader/core/sync/sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements SyncStore {
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
    temp = await Directory.systemTemp.createTemp('nr-sync-highlights');
    addTearDown(() => temp.delete(recursive: true));
  });

  ({SyncService sync, HighlightDao dao}) phone(String name) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = HighlightDao(db);
    return (
      sync: SyncService(
        settings: SyncSettings(),
        bases: SyncBaseStorage(
          directory: () async => Directory('${temp.path}/$name'),
        ),
        storeFactory: (_, _, _) => store,
        kinds: (_) => [HighlightSync(dao: dao)],
      ),
      dao: dao,
    );
  }

  Highlight paint() => Highlight(
    id: 0,
    bookName: '夜雨聽書',
    bookAuthor: '沈知秋',
    chapterIndex: 3,
    chapterTitle: '第三章 松煙墨',
    charOffset: 120,
    quote: '百年以上的松煙墨',
  );

  test('a highlight added on one phone shows up on the other with its color; '
      'recoloring and deleting it there follow back here', () async {
    final a = phone('a');
    final b = phone('b');
    final saved = await a.dao.add(paint());
    await a.sync.syncNow();
    await b.sync.syncNow();

    final onB = (await b.dao.getAll()).single;
    expect(onB.id, saved.id);
    expect(onB.quote, '百年以上的松煙墨');
    expect(onB.color, HighlightColor.amber);
    expect(onB.style, HighlightStyle.fill);

    await b.dao.upsertAll([
      onB.copyWith(color: HighlightColor.blue, style: HighlightStyle.underline),
    ]);
    await b.sync.syncNow();
    await a.sync.syncNow();
    final onA = (await a.dao.getAll()).single;
    expect(onA.color, HighlightColor.blue);
    expect(onA.style, HighlightStyle.underline);

    await a.dao.upsertAll([onA.copyWith(note: '想起外婆的墨盒')]);
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect((await b.dao.getAll()).single.note, '想起外婆的墨盒');

    await b.dao.deleteByIds([saved.id]);
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(await a.dao.getAll(), isEmpty);
  });

  test('the chapter number alone is not a change', () async {
    final a = phone('a');
    final b = phone('b');
    final saved = await a.dao.add(paint());
    await a.sync.syncNow();
    await b.sync.syncNow();
    final before = store.files[HighlightSync(dao: b.dao).fileName];

    await b.dao.upsertAll([saved.copyWith(chapterIndex: 5)]);
    await b.sync.syncNow();
    expect(store.files[HighlightSync(dao: b.dao).fileName], before);
  });

  test('two phones adding highlights at the same time keep both', () async {
    final a = phone('a');
    final b = phone('b');
    await a.dao.add(paint());
    await b.dao.add(paint());
    await a.sync.syncNow();
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(await a.dao.getAll(), hasLength(2));
    expect(await b.dao.getAll(), hasLength(2));
  });

  test(
    'a record from a version without notes keeps the note written here',
    () async {
      final a = phone('a');
      final saved = await a.dao.add(paint().copyWith(note: '想起外婆的墨盒'));
      final kind = HighlightSync(dao: a.dao);
      // 舊版改了顏色後上傳的那筆：沒有 note。
      final old = HighlightSync.recordOf(
        saved.copyWith(color: HighlightColor.pink),
      ).data..remove('note');
      await kind.apply({'${saved.id}': SyncRecord(time: 0, data: old)});

      final after = (await a.dao.getAll()).single;
      expect(after.color, HighlightColor.pink);
      expect(after.note, '想起外婆的墨盒');
    },
  );
}
