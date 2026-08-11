import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/services/restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

class _FakeReplaceRuleDao extends Fake implements ReplaceRuleDao {}

class _FakeBookGroupDao extends Fake implements BookGroupDao {}

class _FakeBookmarkDao extends Fake implements BookmarkDao {}

class _FakeDownloadDao extends Fake implements DownloadDao {}

class _FakeReaderChapterContentDao extends Fake
    implements ReaderChapterContentDao {}

void main() {
  final getIt = GetIt.instance;
  late Directory tempDir;
  late RestoreService service;

  setUpAll(() async {
    await getIt.reset();
    getIt.registerSingleton<BookDao>(_FakeBookDao());
    getIt.registerSingleton<BookSourceDao>(_FakeBookSourceDao());
    getIt.registerSingleton<ReplaceRuleDao>(_FakeReplaceRuleDao());
    getIt.registerSingleton<BookGroupDao>(_FakeBookGroupDao());
    getIt.registerSingleton<BookmarkDao>(_FakeBookmarkDao());
    getIt.registerSingleton<DownloadDao>(_FakeDownloadDao());
    getIt.registerSingleton<ReaderChapterContentDao>(
      _FakeReaderChapterContentDao(),
    );
    service = RestoreService();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('night-reader-restore-');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  tearDownAll(() async {
    await getIt.reset();
  });

  test('只有未知 JSON 清單的備份不會誤報還原成功', () async {
    final file = await _writeBackup(tempDir, <String, Object?>{
      'unrelated.json': <Object?>[],
    });

    expect(await service.restoreFromZip(file), isFalse);
  });

  test('已知的空資料表仍視為有效備份內容', () async {
    final file = await _writeBackup(tempDir, <String, Object?>{
      'bookshelf.json': <Object?>[],
    });

    expect(await service.restoreFromZip(file), isTrue);
  });

  test('已知資料表只有錯誤型別時不會誤報成功', () async {
    final file = await _writeBackup(tempDir, <String, Object?>{
      'bookshelf.json': <Object?>['not a book'],
    });

    expect(await service.restoreFromZip(file), isFalse);
  });

  test('偏好設定只有不支援型別時不會誤報成功', () async {
    final file = await _writeBackup(tempDir, <String, Object?>{
      'config.json': <String, Object?>{
        'unsupported': <String, Object?>{'nested': true},
      },
    });

    expect(await service.restoreFromZip(file), isFalse);
  });

  test('合法空偏好設定仍視為有效備份內容', () async {
    final file = await _writeBackup(tempDir, <String, Object?>{
      'config.json': <String, Object?>{},
    });

    expect(await service.restoreFromZip(file), isTrue);
  });
}

Future<File> _writeBackup(
  Directory directory,
  Map<String, Object?> payloads,
) async {
  final archive =
      Archive()..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode(<String, Object?>{
            'appVersion': 'test',
            'schemaVersion': 2,
            'timestamp': 1,
          }),
        ),
      );
  for (final entry in payloads.entries) {
    archive.addFile(ArchiveFile.string(entry.key, jsonEncode(entry.value)));
  }
  final file = File('${directory.path}/backup.zip');
  await file.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return file;
}
