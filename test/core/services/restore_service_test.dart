import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/services/book_illustration_storage.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/restore_service.dart';
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
      ..registerSingleton<ReaderChapterContentDao>(ReaderChapterContentDao(db));
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
    expect(restored!.from, 'phone-a');
    expect(restored.books, {'丁': 900});
    expect(restored.days, {'2026-10-20': 900});
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
}
