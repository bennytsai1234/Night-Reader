import 'dart:convert';

import 'package:archive/archive.dart';
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
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/backup_service.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'reader.fontSize': 20});
    PackageInfo.setMockInitialValues(
      appName: '夜讀',
      packageName: 'com.inkpage.reader',
      version: '0.3.3',
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
      ..registerSingleton<BookmarkDao>(BookmarkDao(db))
      ..registerSingleton<HighlightDao>(HighlightDao(db))
      ..registerSingleton<ReaderChapterContentDao>(ReaderChapterContentDao(db))
      ..registerSingleton<CacheDao>(CacheDao(db))
      ..registerSingleton<CookieDao>(CookieDao(db));
    await NetworkService().init(ephemeral: true);
  });

  tearDownAll(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('the backup zip is complete once createBackupZip returns', () async {
    await BookSourceDao(db).upsert(
      BookSource(bookSourceUrl: 'https://a.example', bookSourceName: '甲'),
    );

    final zip = await BackupService().createBackupZip();

    expect(zip, isNotNull);
    expect(await zip!.exists(), isTrue);
    expect(
      await zip.parent.list().map((e) => e.path).toList(),
      isNot(contains(endsWith('.tmp'))),
    );

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    String entry(String name) =>
        utf8.decode(archive.findFile(name)!.content as List<int>);

    expect(
      archive.files.map((f) => f.name),
      containsAll([
        'manifest.json',
        'bookshelf.json',
        'bookSource.json',
        'replaceRule.json',
        'bookGroup.json',
        'downloadTask.json',
        'readerChapterContent.json',
        'readRecord.json',
        'cache.json',
        'cookie.json',
        'cookieJar.json',
        'config.json',
      ]),
    );
    expect(jsonDecode(entry('manifest.json'))['appVersion'], '0.3.3');
    expect(
      jsonDecode(entry('bookSource.json')).single['bookSourceUrl'],
      'https://a.example',
    );
    expect(jsonDecode(entry('config.json'))['reader.fontSize'], 20);
  });

  test('the backup carries only shelf books, their downloads and the chapters '
      'downloaded for them', () async {
    const origin = 'https://a.example';
    for (final (url, onShelf) in [('shelf', true), ('preview', false)]) {
      await BookDao(db).upsert(
        Book(bookUrl: url, origin: origin, name: url, isInBookshelf: onShelf),
      );
      await DownloadDao(db).upsert(DownloadTask(bookUrl: url, bookName: url));
    }
    Future<void> save(String bookUrl, String chapter, {String o = origin}) =>
        ReaderChapterContentDao(db).saveContent(
          contentKey: ReaderChapterContentDao.contentKey(
            origin: o,
            bookUrl: bookUrl,
            chapterUrl: chapter,
          ),
          origin: o,
          bookUrl: bookUrl,
          chapterUrl: chapter,
          chapterIndex: 0,
          content: '正文',
          updatedAt: 1,
        );
    await save('shelf', 'c1');
    await save('shelf', 'c2', o: 'https://old.example');
    await save('preview', 'c1');
    await ReaderChapterContentDao(db).saveFailure(
      contentKey: ReaderChapterContentDao.contentKey(
        origin: origin,
        bookUrl: 'shelf',
        chapterUrl: 'c3',
      ),
      origin: origin,
      bookUrl: 'shelf',
      chapterUrl: 'c3',
      chapterIndex: 2,
      message: '找不到書源',
      updatedAt: 1,
    );

    final zip = await BackupService().createBackupZip();
    final archive = ZipDecoder().decodeBytes(await zip!.readAsBytes());
    List<dynamic> entry(String name) =>
        jsonDecode(utf8.decode(archive.findFile(name)!.content as List<int>));

    expect(entry('bookshelf.json').map((book) => book['bookUrl']), ['shelf']);
    expect(entry('downloadTask.json').map((task) => task['bookUrl']), [
      'shelf',
    ]);
    expect(
      entry('readerChapterContent.json')
          .map((content) => '${content['bookUrl']} ${content['chapterUrl']}'),
      ['shelf c1'],
    );
  });
}
