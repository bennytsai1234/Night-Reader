import 'dart:io' as io;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/cache.dart';
import 'package:night_reader/core/services/backup_service.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/login_data_backup.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/restore_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 這個測試檔自己的 App 資料夾：沒有平台外掛時 App 的資料夾都落在系統暫存區
/// 的同一處，和同時在跑的備份測試共用備份暫存資料夾會互相刪掉。
class _OwnPathProvider extends PathProviderPlatform {
  _OwnPathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late AppDatabase db;
  late io.Directory appDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    appDir = io.Directory.systemTemp.createTempSync('nr-login-backup-');
    PathProviderPlatform.instance = _OwnPathProvider(appDir.path);
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: '夜讀',
      packageName: 'com.inkpage.reader',
      version: '0.3.7',
      buildNumber: '1',
      buildSignature: '',
    );
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<AppDatabase>(db)
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ReplaceRuleDao>(ReplaceRuleDao(db))
      ..registerSingleton<BookGroupDao>(BookGroupDao(db))
      ..registerSingleton<DownloadDao>(DownloadDao(db))
      ..registerSingleton<ReadRecordDao>(ReadRecordDao(db))
      ..registerSingleton<ReaderChapterContentDao>(ReaderChapterContentDao(db))
      ..registerSingleton<CacheDao>(CacheDao(db))
      ..registerSingleton<CookieDao>(CookieDao(db));
    await NetworkService().init(ephemeral: true);
  });

  tearDownAll(() async {
    await db.close();
    await GetIt.instance.reset();
    appDir.deleteSync(recursive: true);
  });

  test('login data survives a backup and restore on a clean phone', () async {
    final source = BookSource(
      bookSourceUrl: 'https://a.example',
      bookSourceName: '甲',
    );
    await source.putLoginInfo('{"帳號":"reader","密碼":"secret"}');
    await source.putLoginHeader('{"Authorization":"Bearer t"}');
    await CacheManager().put('token', 'from-cache-put');
    await CacheManager().put('short', 'still-valid', saveTimeSeconds: 3600);
    final now = DateTime.now().millisecondsSinceEpoch;
    await CacheDao(db)
        .upsert(Cache(key: 'gone', value: 'x', deadline: now - 1));
    await CookieStore().setCookie('https://a.example/login', 'sid=abc');
    final jar = NetworkService().cookieJar;
    await jar.saveFromResponse(Uri.parse('https://api.a.example/v1/login'), [
      io.Cookie('session', 'jar-value')..path = '/v1',
      io.Cookie('shared', 'domain-value')..domain = '.a.example',
      io.Cookie('old', 'expired')
        ..expires = DateTime.now().subtract(const Duration(days: 1)),
    ]);

    final zip = await BackupService().createBackupZip();
    expect(zip, isNotNull);

    for (final key in [
      source.loginInfoCacheKey,
      source.loginHeaderCacheKey,
      'token',
      'short',
      'gone',
    ]) {
      await CacheManager().delete(key);
    }
    await CookieStore().clearAll();
    await jar.deleteAll();
    expect(await source.getLoginInfo(), isNull);

    final result = await RestoreService().restoreFromZip(zip!);

    expect(result.failedFiles, isEmpty);
    expect(await source.getLoginInfoMap(), {'帳號': 'reader', '密碼': 'secret'});
    expect(await source.getLoginHeader(), '{"Authorization":"Bearer t"}');
    expect(await CacheManager().get('token'), 'from-cache-put');
    final short = await CacheDao(db).get('short');
    expect(short?.value, 'still-valid');
    expect(short!.deadline, greaterThan(now));
    expect(await CacheDao(db).get('gone'), isNull);
    expect(await CookieStore().getCookie('https://a.example'), 'sid=abc');
    final sent = await jar.loadForRequest(
      Uri.parse('https://api.a.example/v1/books'),
    );
    expect(
      {for (final cookie in sent) cookie.name: cookie.value},
      {'session': 'jar-value', 'shared': 'domain-value'},
    );
  });

  group('Cookie 檔', () {
    late io.Directory dir;
    PersistCookieJar freshJar() =>
        PersistCookieJar(storage: FileStorage('${dir.path}/'));

    setUp(() => dir = io.Directory.systemTemp.createTempSync('nr-jar-'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('App 啟動後還沒發過請求也讀得到，壞掉的網站檔略過、不刪', () async {
      final writer = freshJar();
      await writer.saveFromResponse(Uri.parse('https://a.example/'), [
        io.Cookie('sid', 'abc'),
        io.Cookie('shared', 'x')..domain = '.a.example',
      ]);
      // 再加一個壞掉的網站檔。
      final storage = writer.storage;
      final index = await storage.read('.index');
      await storage.write(
        '.index',
        index!.replaceFirst(']', ',"broken.example"]'),
      );
      await storage.write('broken.example', '{broken');

      final exported = await LoginDataBackup.exportCookieJar(freshJar());

      expect(
        exported.map((e) => io.Cookie.fromSetCookieValue(e['cookie']!).name),
        unorderedEquals(['sid', 'shared']),
      );
      expect(await storage.read('broken.example'), '{broken');
    });

    test('還原併進網站原本的 Cookie，沒在備份裡的照樣留著', () async {
      await freshJar().saveFromResponse(Uri.parse('https://a.example/'), [
        io.Cookie('keep', '1'),
      ]);

      await LoginDataBackup.restore(LoginDataBackup.cookieJarFile, [
        {'url': 'https://a.example/', 'cookie': 'restored=2; Path=/'},
      ], cookieJar: freshJar());

      final sent = await freshJar().loadForRequest(
        Uri.parse('https://a.example/'),
      );
      expect(
        {for (final cookie in sent) cookie.name: cookie.value},
        {'keep': '1', 'restored': '2'},
      );
    });

    test('存活秒數與到期時刻都有時，照先到的那個', () async {
      final soon = DateTime.now().add(const Duration(minutes: 5));
      await freshJar().saveFromResponse(Uri.parse('https://a.example/'), [
        io.Cookie('both', 'v')
          ..expires = soon
          ..maxAge = 3600,
        io.Cookie('age', 'v')..maxAge = 3600,
      ]);

      final exported = {
        for (final entry in await LoginDataBackup.exportCookieJar(freshJar()))
          if (io.Cookie.fromSetCookieValue(entry['cookie']!) case final cookie)
            cookie.name: cookie.expires!,
      };

      expect(exported['both']!.difference(soon).inSeconds.abs(), lessThan(2));
      final ageExpiry = DateTime.now().add(const Duration(hours: 1));
      expect(
        exported['age']!.difference(ageExpiry).inSeconds.abs(),
        lessThan(5),
      );
    });
  });

  test('有一筆格式不對就整份不寫', () async {
    await CookieStore().clearAll();
    await expectLater(
      LoginDataBackup.restore(LoginDataBackup.cookieFile, [
        {'url': 'partial.example', 'cookie': 'sid=written'},
        42,
      ]),
      throwsFormatException,
    );
    expect(await CookieDao(db).getByUrl('partial.example'), isNull);

    await expectLater(
      LoginDataBackup.restore(LoginDataBackup.cacheFile, [
        {'key': 'ok', 'value': 'v', 'deadline': 0},
        {'key': 'no-value', 'deadline': 0},
      ]),
      throwsFormatException,
    );
    expect(await CacheDao(db).get('ok'), isNull);

    await expectLater(
      LoginDataBackup.restore(LoginDataBackup.cookieJarFile, [
        {'url': 'https://a.example/', 'cookie': 'ok=1'},
        {'url': '', 'cookie': 'bad=1'},
      ]),
      throwsFormatException,
    );
  });

  test('快取照原本的到期時刻寫回', () async {
    final deadline = DateTime.now().millisecondsSinceEpoch + 90 * 60 * 1000;
    await LoginDataBackup.restore(LoginDataBackup.cacheFile, [
      {'key': 'exact', 'value': 'v', 'deadline': deadline},
    ]);
    expect((await CacheDao(db).get('exact'))!.deadline, deadline);
  });
}
