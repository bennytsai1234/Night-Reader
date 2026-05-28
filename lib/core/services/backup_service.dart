import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/app_version.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/services/app_log_service.dart';

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  /// 備份檔案的 Schema 版本，應與 [AppDatabase.schemaVersion] 保持一致。
  int get currentSchemaVersion => AppDatabase().schemaVersion;

  /// 執行全量備份並返回 ZIP 檔案路徑
  Future<File?> createBackupZip() async {
    final backupTempDir = await AppStoragePaths.backupTempDir(
      ensureExists: true,
    );
    final backupFolder = Directory(p.join(backupTempDir.path, 'legado_backup'));
    if (await backupFolder.exists()) await backupFolder.delete(recursive: true);
    await backupFolder.create();

    try {
      // 0. 寫入備份 manifest（版本資訊，供還原時驗證）
      final version = await AppVersion.current();
      final manifest = {
        'appVersion': version.versionName,
        'schemaVersion': currentSchemaVersion,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await File(
        p.join(backupFolder.path, 'manifest.json'),
      ).writeAsString(jsonEncode(manifest));

      // 1. 導出資料庫表為 JSON (對標 Android Backup.kt)
      await _writeJson(
        backupFolder,
        'bookshelf.json',
        await getIt<BookDao>().getAll(),
      );
      await _writeJson(
        backupFolder,
        'bookSource.json',
        await getIt<BookSourceDao>().getAllFull(),
      );
      await _writeJson(
        backupFolder,
        'replaceRule.json',
        await getIt<ReplaceRuleDao>().getAll(),
      );
      await _writeJson(
        backupFolder,
        'bookmark.json',
        await getIt<BookmarkDao>().getAll(),
      );
      await _writeJson(
        backupFolder,
        'bookGroup.json',
        await getIt<BookGroupDao>().getAll(),
      );
      await _writeJson(
        backupFolder,
        'downloadTask.json',
        await getIt<DownloadDao>().getAll(),
      );
      await _writeJson(
        backupFolder,
        'readerChapterContent.json',
        await getIt<ReaderChapterContentDao>().getAllEntries(),
      );

      // 2. 導出偏好設定 (對標 config.xml)
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> config = {};
      for (var key in prefs.getKeys()) {
        config[key] = prefs.get(key);
      }
      await File(
        p.join(backupFolder.path, 'config.json'),
      ).writeAsString(jsonEncode(config));

      // 3. 打包為 ZIP（先寫暫存檔，再原子重新命名）
      final encoder = ZipFileEncoder();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final zipPath = p.join(backupTempDir.path, 'backup-$dateStr.zip');
      final tmpZipPath = '$zipPath.tmp';

      encoder.create(tmpZipPath);
      await for (var entity in backupFolder.list(recursive: true)) {
        if (entity is File) {
          encoder.addFile(entity);
        }
      }
      encoder.close();

      // 原子重新命名：確保不會寫到一半產生殘缺 ZIP
      final tmpFile = File(tmpZipPath);
      await tmpFile.rename(zipPath);

      return File(zipPath);
    } catch (e, stack) {
      AppLog.e('建立備份 ZIP 失敗: $e', error: e, stackTrace: stack);
      return null;
    }
  }

  Future<void> _writeJson(
    Directory folder,
    String name,
    List<dynamic> data,
  ) async {
    final file = File(p.join(folder.path, name));
    final jsonList =
        data.map((e) {
          try {
            return (e as dynamic).toJson();
          } catch (err) {
            AppLog.w('Backup: toJson failed for item in $name: $err');
            return e;
          }
        }).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }
}
