import 'dart:io' hide Cookie;
import 'dart:io' as io show Cookie;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/cookie.dart';
import 'package:night_reader/core/services/login_data_backup.dart';
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

class _StatsPhone {
  _StatsPhone({
    required this.sync,
    required this.bases,
    required this.dao,
    required this.prefs,
  });

  final SyncService sync;
  final SyncBaseStorage bases;
  final ReadRecordDao dao;
  final SharedPreferences prefs;

  Future<OtherDevicesStats> others() =>
      ReadStatsSync.others(bases: bases, prefs: prefs);
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
    storeFactory: (_, _, _) => store,
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
      PreferKey.readerLineChars: 24,
      PreferKey.lightStyle: 'tea',
      PreferKey.readerBrightness: 0.3,
    });
    await phone('a', [SettingsSync(prefs: a)]).syncAll();
    expect(store.files['settings.json'], isNot(contains('reader_brightness')));

    final b = await prefsOf({
      PreferKey.readerFontSize: 18.0,
      PreferKey.readerBrightness: 0.9,
    });
    final applied = SettingsSync.applied.value;
    final onB = phone('b', [SettingsSync(prefs: b)]);
    await onB.syncAll();

    expect(b.getDouble(PreferKey.readerFontSize), 22.0);
    expect(b.getInt(PreferKey.readerLineChars), 24);
    expect(b.getString(PreferKey.lightStyle), 'tea');
    expect(b.getDouble(PreferKey.readerBrightness), 0.9);
    expect(SettingsSync.applied.value, applied + 1);

    // B 之後改的字級送上去；改回預設（移除）也跟著同步。
    await b.setDouble(PreferKey.readerFontSize, 20.0);
    await b.remove(PreferKey.lightStyle);
    await onB.syncAll();
    final records = SyncDocument.decode(store.files['settings.json']!).records;
    expect(records[PreferKey.readerFontSize]!.data['v'], 20.0);
    expect(records[PreferKey.lightStyle]!.deleted, isTrue);
  });

  group('reading stats', () {
    final start = DateTime(2026, 11, 2, 10);
    const today = '2026-11-02';

    Future<_StatsPhone> statsPhone(String name) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final prefs = await prefsOf({});
      final settings = SyncSettings(prefs);
      final bases = SyncBaseStorage(
        directory: () async => Directory('${temp.path}/$name'),
      );
      final dao = ReadRecordDao(db);
      return _StatsPhone(
        sync: SyncService(
          settings: settings,
          bases: bases,
          storeFactory: (_, _, _) => store,
          kinds: (_) => [
            ReadStatsSync(
              settings: settings,
              bases: bases,
              dao: dao,
              prefs: prefs,
            ),
          ],
        ),
        bases: bases,
        dao: dao,
        prefs: prefs,
      );
    }

    Future<void> read(_StatsPhone phone, String book, int minutes) =>
        phone.dao.recordReadActivity(
          bookName: book,
          startedAt: start,
          stoppedAt: start.add(Duration(minutes: minutes)),
        );

    test('reading time from every phone adds up; no phone overwrites '
        'another', () async {
      final a = await statsPhone('a');
      final b = await statsPhone('b');
      await read(a, '夜航', 30);
      await read(b, '夜航', 20);
      await read(b, '別本', 10);

      await a.sync.syncAll();
      await b.sync.syncAll();
      await a.sync.syncAll();

      final onA = await a.others();
      expect(onA.books['夜航']!.readTime, 20 * 60);
      expect(onA.books['別本']!.readTime, 10 * 60);
      expect(onA.secondsBetween(today, today), 30 * 60);
      final onB = await b.others();
      expect(onB.books['夜航']!.readTime, 30 * 60);
      expect(onB.books.containsKey('別本'), isFalse);
    });

    test('a phone keeps sending its own time after sync is turned off and '
        'on again', () async {
      final a = await statsPhone('a');
      final b = await statsPhone('b');
      await read(a, '夜航', 10);
      await a.sync.syncAll();

      // 停用（上次同步的紀錄清掉）後又讀了 5 分鐘，再打開同一個空間。
      await a.bases.clear();
      await read(a, '夜航', 5);
      await a.sync.syncAll();
      await b.sync.syncAll();

      expect((await b.others()).books['夜航']!.readTime, 15 * 60);
    });

    test('time restored from the other phone\'s backup is not counted '
        'twice', () async {
      final a = await statsPhone('a');
      await read(a, '夜航', 10);
      await a.sync.syncAll();
      final aId = await SyncSettings(a.prefs).deviceId();

      // B 還原了 A 的備份（10 分鐘），之後自己又讀了 5 分鐘。
      final b = await statsPhone('b');
      final records = await a.dao.getAll();
      final days = await a.dao.getAllDays();
      await b.dao.restoreReadingStats(records: records, days: days);
      await RestoredStats.remember(
        b.prefs,
        from: aId,
        records: records,
        days: days,
      );
      await read(b, '夜航', 5);
      await b.sync.syncAll();
      await a.sync.syncAll();

      // A：自己的 10 分鐘 + B 自己讀的 5 分鐘。
      expect((await a.others()).books['夜航']!.readTime, 5 * 60);
      // B：這台的 15 分鐘（含還原的 10 分鐘）+ A 那筆扣掉還原的部分。
      final bLocal = (await b.dao.getByBookName('夜航'))!.readTime;
      expect(bLocal + (await b.others()).books['夜航']!.readTime, 15 * 60);
    });
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
      await phone('a', [LoginCookieSync(dao: cookies)]).syncAll();
      final uploaded = store.files['login_cookies.json']!;
      expect(uploaded, contains('token=abc'));
      expect(uploaded, isNot(contains('cf_clearance')));

      // 另一台：自己有 Cloudflare 通行 Cookie，沒有登入。
      await cookies.upsert(
        Cookie(url: 'example.com', cookie: 'cf_clearance=theirs'),
      );
      await phone('b', [LoginCookieSync(dao: cookies)]).syncAll();

      final stored = (await cookies.getByUrl('example.com'))!.cookie;
      expect(
        stored.split('; '),
        unorderedEquals(['token=abc', 'cf_clearance=theirs']),
      );
    });

    final site = Uri.parse('https://example.com/');
    final subsite = Uri.parse('https://app.example.com/');

    /// 同名、同路徑的兩個 Cookie：一個只給 example.com，一個帶 Domain，
    /// 子網域也帶得出去。
    Future<DefaultCookieJar> jarWithBothScopes() async {
      final jar = DefaultCookieJar();
      await jar.saveFromResponse(site, [
        io.Cookie('sid', 'host-only')..path = '/',
        io.Cookie('sid', 'shared')
          ..domain = 'example.com'
          ..path = '/',
      ]);
      return jar;
    }

    Future<Map<Uri, List<String>>> sentBy(CookieJar jar) async => {
      for (final uri in [site, subsite])
        uri: [
          for (final cookie in await jar.loadForRequest(uri))
            '${cookie.name}=${cookie.value}',
        ]..sort(),
    };

    test(
      'same-named cookies of host-only and Domain scope are both kept',
      () async {
        final jar = await jarWithBothScopes();
        expect(await LoginDataBackup.exportCookieJar(jar), hasLength(2));

        final records = await LoginCookieJarSync(cookieJar: jar).local();
        expect(records, hasLength(2));
        expect(
          records.values.map((r) => (r.data['cookie'] as String)),
          containsAll([contains('sid=host-only'), contains('sid=shared')]),
        );
        // 主機限定的鍵和舊版一樣。
        expect(records.keys, contains('https://example.com/|sid'));
      },
    );

    test(
      'both scopes reach the other phone and send the right cookie',
      () async {
        final a = await jarWithBothScopes();
        await phone('a', [LoginCookieJarSync(cookieJar: a)]).syncAll();
        expect(
          SyncDocument.decode(store.files['login_cookie_jar.json']!).records,
          hasLength(2),
        );

        final b = DefaultCookieJar();
        await phone('b', [LoginCookieJarSync(cookieJar: b)]).syncAll();

        expect(await sentBy(b), await sentBy(a));
        // 原主機兩個都帶（路徑相同時主機限定的先送），子網域只有帶 Domain 的。
        expect((await sentBy(b))[site], ['sid=host-only', 'sid=shared']);
        expect((await sentBy(b))[subsite], ['sid=shared']);
        // 再同步一次不增不減。
        await phone('b', [LoginCookieJarSync(cookieJar: b)]).syncAll();
        expect(await LoginDataBackup.exportCookieJar(b), hasLength(2));
      },
    );

    test('records uploaded by the old key format are re-keyed, not '
        'duplicated or applied over newer content', () async {
      // 舊版：不分適用範圍，帶 Domain 的 Cookie 放在 `網址|名稱`。
      final b = DefaultCookieJar();
      await b.saveFromResponse(site, [
        io.Cookie('sid', 'new')..domain = 'example.com',
      ]);
      store.files['login_cookie_jar.json'] = SyncDocument({
        'https://example.com/|sid': SyncRecord(
          time: 1,
          data: {
            'url': 'https://example.com/',
            'cookie': (io.Cookie(
              'sid',
              'old',
            )..domain = 'example.com').toString(),
          },
        ),
        'https://example.com/|token': SyncRecord(
          time: 1,
          data: {
            'url': 'https://example.com/',
            'cookie': io.Cookie('token', 't').toString(),
          },
        ),
      }).encode();

      final kind = LoginCookieJarSync(cookieJar: b);
      expect(
        kind
            .prune(
              SyncDocument.decode(store.files['login_cookie_jar.json']!)
                  .records,
            )
            .keys,
        unorderedEquals([
          'https://example.com/|sid|domain=example.com',
          'https://example.com/|token',
        ]),
      );

      // 這台已經有新內容、雲端只有舊鍵：舊內容照新鍵比，這台沒同步過所以
      // 雲端的贏，但只會是一筆 sid，不會變成兩筆。
      await phone('b', [kind]).syncAll();
      final sent = await sentBy(b);
      expect(sent[site]!.where((c) => c.startsWith('sid=')), hasLength(1));
      expect(sent[subsite], ['sid=old']);
      expect(sent[site], contains('token=t'));
      expect(await LoginDataBackup.exportCookieJar(b), hasLength(2));
    });

    test(
      'an old-key record next to its new-key record keeps the newer one',
      () {
        final kind = LoginCookieJarSync(cookieJar: DefaultCookieJar());
        String cookie(String value) =>
            (io.Cookie('sid', value)..domain = 'example.com').toString();
        SyncRecord record(int time, String value) => SyncRecord(
          time: time,
          data: {'url': 'https://example.com/', 'cookie': cookie(value)},
        );
        const newKey = 'https://example.com/|sid|domain=example.com';

        var pruned = kind.prune({
          'https://example.com/|sid': record(5, 'stale'),
          newKey: record(9, 'fresh'),
        });
        expect(pruned.keys, [newKey]);
        expect(pruned[newKey]!.data['cookie'], contains('fresh'));

        pruned = kind.prune({
          'https://example.com/|sid': record(9, 'fresh'),
          newKey: record(5, 'stale'),
        });
        expect(pruned[newKey]!.data['cookie'], contains('fresh'));
      },
    );

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
