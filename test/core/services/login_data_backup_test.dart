import 'dart:io' as io;

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
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/restore_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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
}
