import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/backup/backup_service.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/core/backup/restore_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/sync/read_stats_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<AppDatabase>(db)
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<ChapterDao>(ChapterDao(db))
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
    tempDir = await Directory.systemTemp.createTemp('restore_test');
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
    await GetIt.instance.reset();
  });

  Future<File> writeZip(String name, Map<String, String> entries) async {
    final archive = Archive();
    entries.forEach((fileName, content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
    });
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file;
  }

  test('one broken file is reported while the rest is restored', () async {
    final zip = await writeZip('partial.zip', {
      'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
      'bookSources.json': jsonEncode([
        {'bookSourceUrl': 'https://a.example', 'bookSourceName': '甲'},
      ]),
      'replaceRules.json': '[{',
    });

    final result = await RestoreService().restoreFromZip(zip);

    expect(result.invalidArchive, isFalse);
    expect(result.restoredAny, isTrue);
    expect(result.failedFiles, ['replaceRules.json']);
    expect(await BookSourceDao(db).getByUrl('https://a.example'), isNotNull);
  });

  test(
    'settings that belong to one phone are not taken from a backup',
    () async {
      final zip = await writeZip('config.zip', {
        'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
        'config.json': jsonEncode({
          'reader.fontSize': 22,
          PreferKey.appLockMode: 'onLeave',
          PreferKey.appCoverOnLeave: true,
          PreferKey.downloadsPausedAll: true,
        }),
      });

      await RestoreService().restoreFromZip(zip);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('reader.fontSize'), 22);
      for (final key in BackupService.deviceOnlyKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
    },
  );

  test('a book follows its source kind whichever file comes first in the '
      'backup (ADR 0053)', () async {
    for (final (index, order) in [
      ['bookSource.json', 'bookshelf.json'],
      ['bookshelf.json', 'bookSource.json'],
    ].indexed) {
      final url = 'https://comic$index.example';
      final files = {
        // 舊備份：書源類型寫 0、名稱帶漫畫字樣，還原時補判成漫畫。
        'bookSource.json': jsonEncode([
          {'bookSourceUrl': url, 'bookSourceName': '漫畫站'},
        ]),
        'bookshelf.json': jsonEncode([
          {
            'bookUrl': '$url/b',
            'name': '夜行',
            'origin': url,
            'isInBookshelf': true,
          },
        ]),
      };
      final zip = await writeZip('kind$index.zip', {
        'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
        for (final name in order) name: files[name]!,
      });

      await RestoreService().restoreFromZip(zip);

      expect(
        (await BookDao(db).getByUrl('$url/b'))!.bookKind,
        BookSourceKind.comic,
        reason: order.join(' → '),
      );
      await BookDao(db).deleteByUrl('$url/b');
      await BookSourceDao(db).deleteByUrl(url);
    }
  });

  test('an old backup\'s "作者：" prefixes are cleaned from the book, its '
      'bookmarks and highlights', () async {
    final zip = await writeZip('author.zip', {
      'manifest.json': jsonEncode({'schemaVersion': 15}),
      'bookshelf.json': jsonEncode([
        {
          'bookUrl': 'https://author.example/b',
          'name': '夜航',
          'author': '作者：某人',
          'origin': 'https://author.example',
          'isInBookshelf': true,
        },
      ]),
      'bookmark.json': jsonEncode([
        {'id': 41, 'bookName': '夜航', 'bookAuthor': '作者：某人'},
      ]),
      'highlight.json': jsonEncode([
        {'id': 42, 'bookName': '夜航', 'bookAuthor': '作者：某人', 'quote': '雨'},
      ]),
    });
    // 資料庫各測試共用：失敗時也清掉，不影響後面的測試。
    addTearDown(() async {
      await BookDao(db).deleteByUrl('https://author.example/b');
      await BookmarkDao(db).deleteByIds([41]);
      await HighlightDao(db).deleteByIds([42]);
    });

    await RestoreService().restoreFromZip(zip);

    expect(
      (await BookDao(db).getByUrl('https://author.example/b'))!.author,
      '某人',
    );
    expect((await BookmarkDao(db).getAll()).single.bookAuthor, '某人');
    expect((await HighlightDao(db).getAll()).single.bookAuthor, '某人');
  });

  test('subscription data in an old backup is skipped silently', () async {
    final zip = await writeZip('with_subscriptions.zip', {
      'manifest.json': jsonEncode({'schemaVersion': 4}),
      'ruleSubs.json': jsonEncode([
        {'id': 1, 'name': '訂閱', 'url': 'https://sub.example'},
      ]),
      'bookSources.json': jsonEncode([
        {'bookSourceUrl': 'https://b.example', 'bookSourceName': '乙'},
      ]),
    });

    final result = await RestoreService().restoreFromZip(zip);

    expect(result.invalidArchive, isFalse);
    expect(result.restoredAny, isTrue);
    expect(result.failedFiles, isEmpty);
    expect(await BookSourceDao(db).getByUrl('https://b.example'), isNotNull);
  });

  test('bookmarks are restored, including ones from backups made before '
      'bookmarks were rebuilt', () async {
    final zip = await writeZip('bookmarks.zip', {
      'manifest.json': jsonEncode({'schemaVersion': 2}),
      'bookmark.json': jsonEncode([
        // 2026-09 以前的欄位。
        {
          'id': 1,
          'time': 1758000000000,
          'bookName': '夜雨聽書',
          'bookAuthor': '沈知秋',
          'chapterIndex': 2,
          'chapterPos': 88,
          'chapterName': '第三章 松煙墨',
          'bookUrl': 'https://old.example/book/1',
          'bookText': '松煙墨',
          'content': '',
        },
        // 現在的欄位。
        {
          'id': 1790000000000,
          'bookName': '夜雨聽書',
          'bookAuthor': '沈知秋',
          'chapterIndex': 4,
          'chapterTitle': '第五章',
          'charOffset': 10,
          'excerpt': '雨聲',
        },
      ]),
    });

    final result = await RestoreService().restoreFromZip(zip);

    expect(result.failedFiles, isEmpty);
    final restored = {
      for (final bookmark in await BookmarkDao(db).getAll())
        bookmark.id: bookmark,
    };
    expect(restored.keys, unorderedEquals([1758000000000, 1790000000000]));
    final legacy = restored[1758000000000]!;
    expect(legacy.chapterTitle, '第三章 松煙墨');
    expect(legacy.charOffset, 88);
    expect(legacy.excerpt, '松煙墨');
    expect(restored[1790000000000]!.excerpt, '雨聲');
  });

  test('highlights are restored with their color and style', () async {
    final zip = await writeZip('highlights.zip', {
      'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
      'highlight.json': jsonEncode([
        {
          'id': 1790000000000123,
          'bookName': '夜雨聽書',
          'bookAuthor': '沈知秋',
          'chapterIndex': 4,
          'chapterTitle': '第五章',
          'charOffset': 10,
          'quote': '雨聲',
          'color': 'pink',
          'style': 'underline',
          'note': '窗外的雨',
        },
        // 沒有畫到字的不還原。
        {'id': 2, 'bookName': '夜雨聽書', 'quote': ''},
      ]),
    });

    final result = await RestoreService().restoreFromZip(zip);

    expect(result.failedFiles, isEmpty);
    final restored = (await HighlightDao(db).getAll()).single;
    expect(restored.id, 1790000000000123);
    expect(restored.quote, '雨聲');
    expect(restored.color, HighlightColor.pink);
    expect(restored.style, HighlightStyle.underline);
    expect(restored.note, '窗外的雨');
  });

  test('reading totals and daily seconds are restored together', () async {
    final dao = ReadRecordDao(db);
    final today = DateTime(2026, 10, 15, 8);
    for (final book in ['甲', '乙']) {
      await dao.recordReadActivity(
        bookName: book,
        startedAt: today,
        stoppedAt: today.add(const Duration(hours: 1)),
      );
    }
    // 每日在總計前面：還原結果不該受 ZIP 裡的檔案順序影響。
    final zip = await writeZip('reading_stats.zip', {
      'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
      'readDay.json': jsonEncode([
        {'bookName': '甲', 'day': '2026-10-14', 'seconds': 600},
      ]),
      'readRecord.json': jsonEncode([
        {'bookName': '甲', 'deviceId': '', 'readTime': 600, 'lastRead': 1},
        {'bookName': '丙', 'deviceId': '', 'readTime': 300, 'lastRead': 1},
      ]),
    });

    final result = await RestoreService().restoreFromZip(zip);

    expect(result.failedFiles, isEmpty);
    expect((await dao.getByBookName('甲'))!.readTime, 600);
    expect((await dao.getByBookName('丙'))!.readTime, 300);
    expect((await dao.getByBookName('乙'))!.readTime, 3600);
    final days = {
      for (final day in await dao.getAllDays())
        '${day.bookName} ${day.day}': day.seconds,
    };
    // 甲換成備份的每日；丙在備份裡沒有每日，從空的開始；乙不在備份裡，不動。
    expect(days, {'甲 2026-10-14': 600, '乙 2026-10-15': 3600});
  });

  test('reading time from a phone that used sync is remembered as restored, '
      'so sync does not count it twice', () async {
    final zip = await writeZip('synced_phone.zip', {
      'manifest.json': jsonEncode({
        'schemaVersion': db.schemaVersion,
        'syncDeviceId': 'phone-a',
      }),
      'readRecord.json': jsonEncode([
        {'bookName': '丁', 'deviceId': '', 'readTime': 900, 'lastRead': 1},
      ]),
      'readDay.json': jsonEncode([
        {'bookName': '丁', 'day': '2026-10-20', 'seconds': 900},
      ]),
    });

    await RestoreService().restoreFromZip(zip);

    final restored = RestoredStats.read(await SharedPreferences.getInstance());
    expect(restored!.devices.keys, ['phone-a']);
    expect(restored.devices['phone-a']!.books, {'丁': 900});
    expect(restored.devices['phone-a']!.days, {
      '丁': {'2026-10-20': 900},
    });
  });

  test('books off the shelf in an old backup are not restored, and chapters '
      'and downloads for them or for long-gone books are dropped', () async {
    const origin = 'https://c.example';
    await BookDao(db).upsert(
      Book(bookUrl: 'mine', origin: origin, name: '我的', isInBookshelf: true),
    );
    Map<String, Object> book(String url, {required bool onShelf}) => {
      'bookUrl': url,
      'origin': origin,
      'name': url,
      'isInBookshelf': onShelf ? 1 : 0,
    };
    Map<String, Object> content(String bookUrl) => {
      'contentKey': ReaderChapterContentDao.contentKey(
        origin: origin,
        bookUrl: bookUrl,
        chapterUrl: 'c1',
      ),
      'origin': origin,
      'bookUrl': bookUrl,
      'chapterUrl': 'c1',
      'chapterIndex': 0,
      'status': 1,
      'content': '正文',
      'updatedAt': 1,
    };
    final zip = await writeZip('old_backup.zip', {
      'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
      // 正文與下載任務排在書前面：結果不該受 ZIP 裡的檔案順序影響。
      'downloadTask.json': jsonEncode([
        {'bookUrl': 'theirs', 'bookName': 'theirs'},
        {'bookUrl': 'preview', 'bookName': 'preview'},
      ]),
      'readerChapterContent.json': jsonEncode([
        content('theirs'),
        content('preview'),
        content('gone'),
      ]),
      'bookshelf.json': jsonEncode([
        book('mine', onShelf: false),
        book('theirs', onShelf: true),
        book('preview', onShelf: false),
      ]),
    });

    final result = await RestoreService().restoreFromZip(zip);

    expect(result.failedFiles, isEmpty);
    final restored = {
      for (final book in await BookDao(db).getAll())
        book.bookUrl: book.isInBookshelf,
    };
    expect(restored, {'mine': true, 'theirs': true});
    expect(
      (await db.select(db.readerChapterContents).get()).map(
        (row) => row.bookUrl,
      ),
      ['theirs'],
    );
    expect((await DownloadDao(db).getAll()).map((task) => task.bookUrl), [
      'theirs',
    ]);
  });

  test('cover files that are not on this phone fall back to the cover '
      'address; the ones still here are kept', () async {
    final here = File('${tempDir.path}/cover-here.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final gone = '${tempDir.path}/gone/cover.jpg';
    Map<String, Object?> book(String url, Map<String, Object?> covers) => {
      'bookUrl': url,
      'origin': 'https://cover.example',
      'name': url,
      'isInBookshelf': 1,
      'coverUrl': 'https://cover.example/$url.jpg',
      ...covers,
    };
    final zip = await writeZip('covers.zip', {
      'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
      'bookshelf.json': jsonEncode([
        // 新手機：書本資料夾不在備份裡。
        book('stored', {'coverLocalPath': gone}),
        // 從相簿選的自訂封面：網址本身也是那台的檔。
        book('gallery', {
          'customCoverUrl': 'file://$gone',
          'customCoverLocalPath': gone,
        }),
        // 同一台手機還原：檔案還在。
        book('same-phone', {'coverLocalPath': here.path}),
      ]),
    });

    final result = await RestoreService().restoreFromZip(zip);

    expect(result.failedFiles, isEmpty);
    Future<String?> cover(String url) async =>
        (await BookDao(db).getByUrl(url))!.getDisplayCover();
    expect(await cover('stored'), 'https://cover.example/stored.jpg');
    expect(await cover('gallery'), 'https://cover.example/gallery.jpg');
    expect(await cover('same-phone'), 'local://${here.path}');
  });

  test('restored text with illustrations (not in the backup) is queued for '
      'the shelf download until every illustration was tried', () async {
    AppStoragePaths.useRoots((
      documents: tempDir.path,
      support: tempDir.path,
      temporary: tempDir.path,
    ));
    const origin = 'https://i.example';
    final book = Book(
      bookUrl: 'illustrated',
      origin: origin,
      name: '有圖',
      isInBookshelf: true,
    );
    Map<String, Object> content(String chapterUrl, String text) => {
      'contentKey': ReaderChapterContentDao.contentKey(
        origin: origin,
        bookUrl: book.bookUrl,
        chapterUrl: chapterUrl,
      ),
      'origin': origin,
      'bookUrl': book.bookUrl,
      'chapterUrl': chapterUrl,
      'chapterIndex': 0,
      'status': 1,
      'content': text,
      'updatedAt': 1,
    };
    final zip = await writeZip('illustrated_backup.zip', {
      'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
      'bookshelf.json': jsonEncode([book.toJson()]),
      'readerChapterContent.json': jsonEncode([
        content('c1', '前文\n<img src="https://i.example/1.png">\n後文'),
        content('c2', '沒有圖'),
      ]),
    });

    final result = await RestoreService().restoreFromZip(zip);

    expect(result.failedFiles, isEmpty);
    expect(await BookIllustrationStorage.isUnfetched(book), isTrue);
    expect(await chaptersWithUntriedIllustrations(book), {'c1'});

    // 抓過了（這裡當作確定抓不到）：不再排，記號刪掉。
    await File(
      BookIllustrationStorage.missingPathFor(
        await BookIllustrationStorage.dirFor(book),
        'https://i.example/1.png',
      ),
    ).create(recursive: true);
    expect(await chaptersWithUntriedIllustrations(book), isEmpty);
    expect(await BookIllustrationStorage.isUnfetched(book), isFalse);
  });

  test('a file that is not a backup is reported as invalid', () async {
    final notZip = File('${tempDir.path}/notes.zip');
    await notZip.writeAsString('這不是壓縮檔');
    expect(
      (await RestoreService().restoreFromZip(notZip)).invalidArchive,
      isTrue,
    );

    final noManifest = await writeZip('no_manifest.zip', {
      'bookSources.json': '[]',
    });
    expect(
      (await RestoreService().restoreFromZip(noManifest)).invalidArchive,
      isTrue,
    );
  });
  group('Legado 的備份 ZIP（沒有 manifest）', () {
    Future<File> legadoZip(String name) => writeZip(name, {
      // 夜讀不讀的檔：Android 的偏好設定與夜讀沒有的功能。
      'config.xml': '<?xml version="1.0"?><map></map>',
      'httpTTS.json': '[]',
      'readConfig.json': '[{"name":"x"}]',
      'bookSource.json': jsonEncode([
        {'bookSourceUrl': 'https://lg.example', 'bookSourceName': '乙'},
      ]),
      'bookshelf.json': jsonEncode([
        {
          'bookUrl': 'https://lg.example/b/1',
          'origin': 'https://lg.example',
          'name': '雪中悍刀行',
          'author': '烽火戏诸侯',
          'type': 8,
          'durChapterIndex': 12,
          'durChapterPos': 345,
          'durChapterTitle': '第十三章',
          'durChapterTime': 1700000000000,
          'canUpdate': true,
          'readConfig': {'reSegment': false},
        },
        {
          'bookUrl': 'https://lg.example/b/2',
          'origin': 'https://lg.example',
          'name': '只是看過',
          'author': '某某',
          'type': 8 | 1024,
        },
      ]),
      'bookmark.json': jsonEncode([
        {
          'time': 1700000000123,
          'bookName': '雪中悍刀行',
          'bookAuthor': '烽火戏诸侯',
          'chapterIndex': 3,
          'chapterPos': 20,
          'chapterName': '第四章',
          'bookText': '天下第二',
          'content': '這句要記住',
        },
        {
          'time': 1700000000456,
          'bookName': '雪中悍刀行',
          'bookAuthor': '烽火戏诸侯',
          'chapterIndex': 5,
          'chapterPos': 0,
          'chapterName': '第六章',
          'bookText': '開頭',
          'content': '',
        },
      ]),
      'readRecord.json': jsonEncode([
        {
          'deviceId': 'phone',
          'bookName': '雪中悍刀行',
          'readTime': 3600000,
          'lastRead': 1700000000000,
        },
        {
          'deviceId': 'tablet',
          'bookName': '雪中悍刀行',
          'readTime': 1800000,
          'lastRead': 1700000500000,
        },
      ]),
    });

    test('沒有 manifest、有 Legado 的檔案就照 Legado 的備份還原', () async {
      final result = await RestoreService().restoreFromZip(
        await legadoZip('legado.zip'),
      );
      expect(result.invalidArchive, isFalse);
      expect(result.failedFiles, isEmpty);
      expect(await BookSourceDao(db).getByUrl('https://lg.example'), isNotNull);
    });

    test('書架上的書照 Legado 的類型還原、閱讀進度對上', () async {
      await RestoreService().restoreFromZip(
        await legadoZip('legado-shelf.zip'),
      );
      final book = await BookDao(db).getByUrl('https://lg.example/b/1');
      expect(book, isNotNull);
      expect(book!.isInBookshelf, isTrue);
      expect(book.chapterIndex, 12);
      expect(book.charOffset, 345);
      expect(book.durChapterTitle, '第十三章');
      expect(
        (await BookDao(db).getByUrl('https://lg.example/b/2'))?.isInBookshelf ??
            false,
        isFalse,
      );
    });

    test('書籤的位置與原文照 Legado 的欄位還原', () async {
      await RestoreService().restoreFromZip(await legadoZip('legado-mark.zip'));
      final bookmarks = (await BookmarkDao(
        db,
      ).getAll()).where((b) => b.bookName == '雪中悍刀行').toList();
      expect(bookmarks.map((b) => b.excerpt), containsAll(['天下第二', '開頭']));
      final first = bookmarks.firstWhere((b) => b.excerpt == '天下第二');
      expect(first.chapterTitle, '第四章');
      expect(first.charOffset, 20);
    });

    test('閱讀時長從毫秒換成秒，同一本書各台的時間加起來', () async {
      await RestoreService().restoreFromZip(await legadoZip('legado-time.zip'));
      final record = await ReadRecordDao(db).getByBookName('雪中悍刀行');
      expect(record?.readTime, 5400);
      expect(record?.lastRead, 1700000500000);
    });
  });

  group('設定也還原：不勾時設定保留這台的，資料照樣還原', () {
    /// 另一台手機的備份：設定與各種資料都有。[tag] 讓每個測試的資料各自
    /// 分得開（整個檔共用一個資料庫）。
    Future<File> otherPhoneZip(String name, {required String tag}) => writeZip(
      name,
      {
        'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
        'config.json': jsonEncode({
          PreferKey.readerFontSize: 30.0,
          PreferKey.themeMode: 'dark',
          'sync.webdav.url': 'https://other.example/dav',
        }),
        'bookSource.json': jsonEncode([
          {'bookSourceUrl': 'https://$tag.example', 'bookSourceName': tag},
        ]),
        'bookshelf.json': jsonEncode([
          {
            'bookUrl': 'https://$tag.example/b/1',
            'origin': 'https://$tag.example',
            'name': '$tag的書',
            'author': '某人',
            'isInBookshelf': true,
            'chapterIndex': 7,
            'charOffset': 120,
          },
        ]),
        'replaceRule.json': jsonEncode([
          {
            'id': 1800000000000 + tag.length,
            'name': '$tag的規則',
            'pattern': '廣告',
            'replacement': '',
          },
        ]),
        'bookmark.json': jsonEncode([
          {
            'id': 1800000000000 + tag.length,
            'bookName': '$tag的書',
            'bookAuthor': '某人',
            'chapterIndex': 7,
            'chapterTitle': '第八章',
            'charOffset': 120,
            'excerpt': '$tag的書籤',
          },
        ]),
        'highlight.json': jsonEncode([
          {
            'id': 1800000000000123 + tag.length,
            'bookName': '$tag的書',
            'bookAuthor': '某人',
            'chapterIndex': 7,
            'charOffset': 120,
            'quote': '$tag的標註',
          },
        ]),
        'readRecord.json': jsonEncode([
          {'bookName': '$tag的書', 'deviceId': '', 'readTime': 42, 'lastRead': 1},
        ]),
        'cookie.json': jsonEncode([
          {'url': 'https://$tag.example', 'cookie': 'sid=$tag'},
        ]),
      },
    );

    /// 這台手機原本的設定：字級 18、深淺沒設過、自己的同步空間。
    Future<SharedPreferences> thisPhoneSettings() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(PreferKey.readerFontSize, 18.0);
      await prefs.remove(PreferKey.themeMode);
      await prefs.setString('sync.webdav.url', 'https://mine.example/dav');
      return prefs;
    }

    Future<void> expectDataRestored(String tag) async {
      expect(
        await BookSourceDao(db).getByUrl('https://$tag.example'),
        isNotNull,
      );
      final book = await BookDao(db).getByUrl('https://$tag.example/b/1');
      expect(book?.isInBookshelf, isTrue);
      expect(book?.chapterIndex, 7);
      expect(book?.charOffset, 120);
      expect(
        (await ReplaceRuleDao(db).getAll()).map((rule) => rule.name),
        contains('$tag的規則'),
      );
      expect(
        (await BookmarkDao(db).getAll()).map((mark) => mark.excerpt),
        contains('$tag的書籤'),
      );
      expect(
        (await HighlightDao(db).getAll()).map((mark) => mark.quote),
        contains('$tag的標註'),
      );
      expect((await ReadRecordDao(db).getByBookName('$tag的書'))?.readTime, 42);
      expect(
        (await CookieDao(db).getAll()).map((cookie) => cookie.cookie),
        contains('sid=$tag'),
      );
    }

    test('勾著時設定換成備份的', () async {
      final prefs = await thisPhoneSettings();

      final result = await RestoreService().restoreFromZip(
        await otherPhoneZip('with-settings.zip', tag: 'withset'),
      );

      expect(result.failedFiles, isEmpty);
      expect(prefs.getDouble(PreferKey.readerFontSize), 30.0);
      expect(prefs.getString(PreferKey.themeMode), 'dark');
      expect(prefs.getString('sync.webdav.url'), 'https://other.example/dav');
      await expectDataRestored('withset');
    });

    test('不勾時設定保留這台的', () async {
      final prefs = await thisPhoneSettings();

      final result = await RestoreService().restoreFromZip(
        await otherPhoneZip('without-settings.zip', tag: 'noset'),
        restoreSettings: false,
      );

      expect(result.failedFiles, isEmpty);
      expect(result.restoredAny, isTrue);
      expect(prefs.getDouble(PreferKey.readerFontSize), 18.0);
      expect(prefs.containsKey(PreferKey.themeMode), isFalse);
      expect(prefs.getString('sync.webdav.url'), 'https://mine.example/dav');
      await expectDataRestored('noset');
    });

    test('不勾時只有設定的備份算沒有可還原的資料，讀不懂的設定檔也不算失敗', () async {
      final prefs = await thisPhoneSettings();
      final onlySettings = await writeZip('only-settings.zip', {
        'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
        'config.json': jsonEncode({PreferKey.readerFontSize: 30.0}),
      });
      final brokenSettings = await writeZip('broken-settings.zip', {
        'manifest.json': jsonEncode({'schemaVersion': db.schemaVersion}),
        'config.json': '{',
      });

      final only = await RestoreService().restoreFromZip(
        onlySettings,
        restoreSettings: false,
      );
      final broken = await RestoreService().restoreFromZip(
        brokenSettings,
        restoreSettings: false,
      );

      expect(only.restoredAny, isFalse);
      expect(only.failedFiles, isEmpty);
      expect(broken.failedFiles, isEmpty);
      expect(prefs.getDouble(PreferKey.readerFontSize), 18.0);
    });

    test('沒有 manifest 的備份（Legado 的路徑）不勾時也不套設定', () async {
      final prefs = await thisPhoneSettings();
      final zip = await writeZip('legado-with-config.zip', {
        'config.xml': '<?xml version="1.0"?><map></map>',
        'config.json': jsonEncode({PreferKey.readerFontSize: 30.0}),
        'bookSource.json': jsonEncode([
          {'bookSourceUrl': 'https://lgnoset.example', 'bookSourceName': '丙'},
        ]),
      });

      final result = await RestoreService().restoreFromZip(
        zip,
        restoreSettings: false,
      );

      expect(result.invalidArchive, isFalse);
      expect(prefs.getDouble(PreferKey.readerFontSize), 18.0);
      expect(
        await BookSourceDao(db).getByUrl('https://lgnoset.example'),
        isNotNull,
      );
    });
  });
}
