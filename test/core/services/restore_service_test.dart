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
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/services/restore_service.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUpAll(() async {
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
