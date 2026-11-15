import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/sync_store_blobs.dart';

import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/sync/ai_find_sync.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
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
    temp = await Directory.systemTemp.createTemp('nr-sync-ai-finds');
    addTearDown(() => temp.delete(recursive: true));
  });

  ({SyncService sync, AiFindDao dao}) phone(String name) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = AiFindDao(db);
    return (
      sync: SyncService(
        settings: SyncSettings(),
        bases: SyncBaseStorage(
          directory: () async => Directory('${temp.path}/$name'),
        ),
        storeFactory: (_, _, _) => store,
        kinds: (_) => [AiFindSync(dao: dao)],
      ),
      dao: dao,
    );
  }

  AiFindRecord found() => AiFindRecord(
    id: 'find-1',
    description: '爽文、穿越',
    depth: 'normal',
    createdAt: 1763140000000,
    outcome: AiFindOutcome.found,
    summary: '搜了穿越與爽文',
    picks: [
      (
        book: SearchBook(
          bookUrl: 'https://a.test/b',
          name: '獵魔人',
          author: '作者',
          origin: 'https://a.test',
          originName: 'A 站',
        ),
        reason: '穿越後獵魔',
      ),
    ],
    rounds: 9,
    tokens: 213000,
  );

  test('a find on one phone shows up on the other with its picks; deleting '
      'it there deletes it here', () async {
    final a = phone('a');
    final b = phone('b');
    await a.dao.upsert(found());
    await a.sync.syncAll();
    await b.sync.syncAll();

    final onB = (await b.dao.getAll()).single;
    expect(onB.id, 'find-1');
    expect(onB.description, '爽文、穿越');
    expect(onB.outcome, AiFindOutcome.found);
    expect(onB.picks.single.book.name, '獵魔人');
    expect(onB.picks.single.book.origin, 'https://a.test');
    expect(onB.picks.single.reason, '穿越後獵魔');
    expect((onB.rounds, onB.tokens), (9, 213000));

    await b.dao.deleteById('find-1');
    await b.sync.syncAll();
    await a.sync.syncAll();
    expect(await a.dao.getAll(), isEmpty);
  });

  test('a record survives the backup JSON', () {
    final back = AiFindRecord.fromJson(found().toJson());
    expect(back.toJson(), found().toJson());
  });
}
