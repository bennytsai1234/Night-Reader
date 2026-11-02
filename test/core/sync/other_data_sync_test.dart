import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/cookie.dart';
import 'package:night_reader/core/sync/login_data_sync.dart';
import 'package:night_reader/core/sync/read_stats_sync.dart';
import 'package:night_reader/core/sync/settings_sync.dart';
import 'package:night_reader/core/sync/sync_base_storage.dart';
import 'package:night_reader/core/sync/sync_kind.dart';
import 'package:night_reader/core/sync/sync_records.dart';
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
    store = _MemoryStore();
    temp = await Directory.systemTemp.createTemp('nr-sync-settings');
    addTearDown(() => temp.delete(recursive: true));
  });

  SyncService phone(String name, List<SyncKind> kinds) => SyncService(
    settings: SyncSettings(),
    bases: SyncBaseStorage(
      directory: () async => Directory('${temp.path}/$name'),
    ),
    storeFactory: (_, _) => store,
    kinds: (_) => kinds,
  );

  /// 換成另一台手機的偏好設定（偏好設定在測試裡只有一份）。
  Future<SharedPreferences> prefsOf(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('reading and appearance settings follow the other phone; brightness '
      'stays on each phone', () async {
    final a = await prefsOf({
      PreferKey.readerFontSize: 22.0,
      PreferKey.lightStyle: 'tea',
      PreferKey.readerBrightness: 0.3,
    });
    await phone('a', [SettingsSync(prefs: a)]).syncNow();
    expect(store.files['settings.json'], isNot(contains('reader_brightness')));

    final b = await prefsOf({
      PreferKey.readerFontSize: 18.0,
      PreferKey.readerBrightness: 0.9,
    });
    final applied = SettingsSync.applied.value;
    final onB = phone('b', [SettingsSync(prefs: b)]);
    await onB.syncNow();

    expect(b.getDouble(PreferKey.readerFontSize), 22.0);
    expect(b.getString(PreferKey.lightStyle), 'tea');
    expect(b.getDouble(PreferKey.readerBrightness), 0.9);
    expect(SettingsSync.applied.value, applied + 1);

    // B 之後改的字級送上去；改回預設（移除）也跟著同步。
    await b.setDouble(PreferKey.readerFontSize, 20.0);
    await b.remove(PreferKey.lightStyle);
    await onB.syncNow();
    final records = SyncDocument.decode(store.files['settings.json']!).records;
    expect(records[PreferKey.readerFontSize]!.data['v'], 20.0);
    expect(records[PreferKey.lightStyle]!.deleted, isTrue);
  });

  test('reading time from every phone adds up; no phone overwrites '
      'another', () async {
    final dbA = AppDatabase.forTesting(NativeDatabase.memory());
    final dbB = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    final start = DateTime(2026, 11, 2, 10);
    Duration minutes(int n) => Duration(minutes: n);

    Future<(SyncService, SyncBaseStorage)> statsPhone(
      String name,
      AppDatabase db,
    ) async {
      final settings = SyncSettings(await prefsOf({}));
      final bases = SyncBaseStorage(
        directory: () async => Directory('${temp.path}/$name'),
      );
      final kind = ReadStatsSync(
        settings: settings,
        bases: bases,
        dao: ReadRecordDao(db),
      );
      return (
        SyncService(
          settings: settings,
          bases: bases,
          storeFactory: (_, _) => store,
          kinds: (_) => [kind],
        ),
        bases,
      );
    }

    final (a, basesA) = await statsPhone('a', dbA);
    final (b, basesB) = await statsPhone('b', dbB);
    await ReadRecordDao(dbA).recordReadActivity(
      bookName: '夜航',
      startedAt: start,
      stoppedAt: start.add(minutes(30)),
    );
    await ReadRecordDao(dbB).recordReadActivity(
      bookName: '夜航',
      startedAt: start,
      stoppedAt: start.add(minutes(20)),
    );
    await ReadRecordDao(dbB).recordReadActivity(
      bookName: '別本',
      startedAt: start,
      stoppedAt: start.add(minutes(10)),
    );

    await a.syncNow();
    await b.syncNow();
    await a.syncNow();

    final onA = await ReadStatsSync.others(bases: basesA);
    expect(onA.books['夜航']!.readTime, 20 * 60);
    expect(onA.books['別本']!.readTime, 10 * 60);
    expect(onA.secondsBetween('2026-11-02', '2026-11-02'), 30 * 60);
    final onB = await ReadStatsSync.others(bases: basesB);
    expect(onB.books['夜航']!.readTime, 30 * 60);
    expect(onB.books.containsKey('別本'), isFalse);
  });

  group('login data', () {
    late AppDatabase db;
    late CookieDao cookies;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      cookies = CookieDao(db);
      getIt.registerSingleton<CookieDao>(cookies);
      addTearDown(() async {
        await getIt.unregister<CookieDao>();
        await db.close();
      });
    });

    test('site cookies sync without the Cloudflare pass, and a phone keeps '
        'its own pass', () async {
      await cookies.upsert(
        Cookie(url: 'example.com', cookie: 'token=abc; cf_clearance=mine'),
      );
      await phone('a', [LoginCookieSync(dao: cookies)]).syncNow();
      final uploaded = store.files['login_cookies.json']!;
      expect(uploaded, contains('token=abc'));
      expect(uploaded, isNot(contains('cf_clearance')));

      // 另一台：自己有 Cloudflare 通行 Cookie，沒有登入。
      await cookies.upsert(
        Cookie(url: 'example.com', cookie: 'cf_clearance=theirs'),
      );
      await phone('b', [LoginCookieSync(dao: cookies)]).syncNow();

      final stored = (await cookies.getByUrl('example.com'))!.cookie;
      expect(
        stored.split('; '),
        unorderedEquals(['token=abc', 'cf_clearance=theirs']),
      );
    });

    test('expired cache entries in the cloud are dropped, not applied', () {
      final kind = LoginCacheSync();
      final pruned = kind.prune({
        'live': const SyncRecord(time: 1, data: {'value': 'v', 'deadline': 0}),
        'gone': const SyncRecord(time: 1, data: {'value': 'v', 'deadline': 1}),
      });
      expect(pruned.keys, ['live']);
    });
  });
}
