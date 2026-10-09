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
