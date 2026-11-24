import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
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
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/backup/backup_service.dart';
import 'package:night_reader/core/backup/restore_service.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/reading/read_record.dart';
import 'package:night_reader/core/network/network_service.dart';
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
      ..registerSingleton<AiFindDao>(AiFindDao(db))
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

    // 這台手機自己的設定不進備份（ADR 0083）。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PreferKey.appLockMode, 'onLeave');
    await prefs.setBool(PreferKey.appCoverOnLeave, true);

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
    final config = jsonDecode(entry('config.json')) as Map<String, dynamic>;
    expect(config['reader.fontSize'], 20);
    expect(config.keys, isNot(contains(PreferKey.appLockMode)));
    expect(config.keys, isNot(contains(PreferKey.appCoverOnLeave)));
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

  test('書架、書源與替換規則照 Legado 讀得懂的型別寫（開關是 true／false）', () async {
    await BookDao(db).upsert(
      Book(
        bookUrl: 'legado-shelf',
        origin: 'https://a.example',
        name: '書',
        isInBookshelf: true,
        chapterIndex: 5,
        charOffset: 9,
        readConfig: ReadConfig(reSegment: true),
      ),
    );
    await BookSourceDao(db).upsert(
      BookSource(bookSourceUrl: 'https://b.example', bookSourceName: '乙'),
    );
    await ReplaceRuleDao(db)
        .upsert(ReplaceRule(id: 7, name: '規則', pattern: 'a', scopeTitle: true));

    final zip = await BackupService().createBackupZip();
    final archive = ZipDecoder().decodeBytes(await zip!.readAsBytes());
    List<dynamic> entry(String name) =>
        jsonDecode(utf8.decode(archive.findFile(name)!.content as List<int>));

    final book = entry('bookshelf.json')
        .firstWhere((b) => b['bookUrl'] == 'legado-shelf');
    expect(book['canUpdate'], isTrue);
    expect(book['isInBookshelf'], isTrue);
    expect(book['readConfig'], isA<Map<String, dynamic>>());
    expect(book['readConfig']['reSegment'], isTrue);
    expect(book['durChapterIndex'], 5);
    expect(book['durChapterPos'], 9);
    final source = entry('bookSource.json')
        .firstWhere((s) => s['bookSourceUrl'] == 'https://b.example');
    expect(source['enabled'], isTrue);
    expect(source['enabledExplore'], isA<bool>());
    expect(source['enabledCookieJar'], isA<bool>());
    final rule = entry('replaceRule.json').firstWhere((r) => r['id'] == 7);
    expect(
      [
        rule['scopeTitle'],
        rule['scopeContent'],
        rule['isEnabled'],
        rule['isRegex'],
      ],
      [true, true, true, true],
    );
  });

  test('閱讀時長照 Legado 寫成毫秒、書籤多寫 Legado 的欄位，夜讀還原回來不變', () async {
    await ReadRecordDao(db).restoreByBookName(
      ReadRecord(deviceId: 'd', bookName: '時長書', readTime: 7200, lastRead: 5),
    );
    await BookmarkDao(db).upsertAll([
      Bookmark(
        id: 1700000000123456,
        bookName: '時長書',
        chapterIndex: 2,
        chapterTitle: '第三章',
        charOffset: 40,
        excerpt: '這一句',
      ),
    ]);

    final zip = await BackupService().createBackupZip();
    final archive = ZipDecoder().decodeBytes(await zip!.readAsBytes());
    dynamic entry(String name) =>
        jsonDecode(utf8.decode(archive.findFile(name)!.content as List<int>));

    expect(entry('manifest.json')['readTimeInMillis'], isTrue);
    final record = (entry('readRecord.json') as List).firstWhere(
      (r) => r['bookName'] == '時長書',
    );
    expect(record['readTime'], 7200000);
    final mark = (entry('bookmark.json') as List).firstWhere(
      (b) => b['bookName'] == '時長書',
    );
    expect(mark['time'], 1700000000123);
    expect(mark['chapterName'], '第三章');
    expect(mark['chapterPos'], 40);
    expect(mark['bookText'], '這一句');

    // 夜讀還原自己的備份：時長換回秒、書籤照 id。
    await ReadRecordDao(db).clearAll();
    final marks = BookmarkDao(db);
    await marks.deleteByIds((await marks.getAll()).map((b) => b.id));
    await RestoreService().restoreFromZip(zip);
    expect((await ReadRecordDao(db).getByBookName('時長書'))?.readTime, 7200);
    final restored = (await marks.getAll()).firstWhere(
      (b) => b.bookName == '時長書',
    );
    expect(restored.id, 1700000000123456);
    expect(restored.charOffset, 40);
  });
}
