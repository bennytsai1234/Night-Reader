import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/app_update/app_version.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/backup/login_data_backup.dart';
import 'package:night_reader/core/sync/read_stats_sync.dart';
import 'package:night_reader/core/sync/sync_settings.dart';

class BackupService {
  /// 只屬於這台手機的設定：不寫進備份，還原時也不套用（舊的備份可能帶著）。
  /// 這台在同步裡的名字與從別台還原進來的閱讀時間、下載佇列的「暫停全部」、
  /// 找過沒有書源的書，與「離開時」（另一台不一定有指紋，
  /// ADR 0083）。
  static final Set<String> deviceOnlyKeys = {
    SyncSettings.deviceIdKey,
    RestoredStats.prefKey,
    SyncSettings.lastSyncKey,
    SyncSettings.lastSyncSpaceKey,
    PreferKey.downloadsPausedAll,
    PreferKey.orphanedBooksSwitched,
    PreferKey.appCoverOnLeave,
    PreferKey.appLockMode,
  };

  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  /// 備份檔案的 Schema 版本，應與 [AppDatabase.schemaVersion] 保持一致。
  int get currentSchemaVersion => getIt<AppDatabase>().schemaVersion;

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
      final prefs = await SharedPreferences.getInstance();
      final manifest = {
        'appVersion': version.versionName,
        'schemaVersion': currentSchemaVersion,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        // 這台在同步裡的名字：還原到另一台時，閱讀統計認得出哪些時間已經
        // 在雲端這台的那筆裡（`RestoredStats`）。
        'syncDeviceId': ?prefs.getString(SyncSettings.deviceIdKey),
        // readRecord.json 的閱讀時長照 Legado 寫成毫秒（[_legadoReadable]）。
        readTimeInMillisKey: true,
      };
      await File(p.join(backupFolder.path, 'manifest.json'))
          .writeAsString(jsonEncode(manifest));

      // 1. 導出資料庫表為 JSON (對標 Android Backup.kt)。書只帶書架上的，
      // 下載任務與已下載的正文也只帶它們的：書架以外的書是打開詳情或閱讀器
      // 時的暫存。抓失敗的章不帶，還原的那台自己重抓。
      final shelf = await getIt<BookDao>().getInBookshelf();
      final shelfOrigins = {
        for (final book in shelf) book.bookUrl: book.origin,
      };
      await _writeJson(backupFolder, 'bookshelf.json', shelf);
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
        'highlight.json',
        await getIt<HighlightDao>().getAll(),
      );
      await _writeJson(
        backupFolder,
        'aiFind.json',
        await getIt<AiFindDao>().getAll(),
      );
      await _writeJson(
        backupFolder,
        'bookGroup.json',
        await getIt<BookGroupDao>().getAll(),
      );
      await _writeJson(backupFolder, 'downloadTask.json', [
        for (final task in await getIt<DownloadDao>().getAll())
          if (shelfOrigins.containsKey(task.bookUrl)) task,
      ]);
      await _writeJson(backupFolder, 'readerChapterContent.json', [
        for (final entry
            in await getIt<ReaderChapterContentDao>().getEntriesByBookUrls(
              shelfOrigins.keys,
            ))
          if (entry.isReady && shelfOrigins[entry.bookUrl] == entry.origin)
            entry,
      ]);
      await _writeJson(
        backupFolder,
        'readRecord.json',
        await getIt<ReadRecordDao>().getAll(),
      );
      await _writeJson(
        backupFolder,
        'readDay.json',
        await getIt<ReadRecordDao>().getAllDays(),
      );

      // 登入資料（ADR 0039）
      await _writeMaps(
        backupFolder,
        LoginDataBackup.cacheFile,
        await LoginDataBackup.exportCache(),
      );
      await _writeMaps(
        backupFolder,
        LoginDataBackup.cookieFile,
        await LoginDataBackup.exportCookies(),
      );
      await _writeMaps(
        backupFolder,
        LoginDataBackup.cookieJarFile,
        await LoginDataBackup.exportCookieJar(),
      );

      // 2. 導出偏好設定 (對標 config.xml)
      final Map<String, dynamic> config = {};
      for (var key in prefs.getKeys()) {
        if (deviceOnlyKeys.contains(key)) continue;
        config[key] = prefs.get(key);
      }
      await File(p.join(backupFolder.path, 'config.json'))
          .writeAsString(jsonEncode(config));

      // 3. 打包為 ZIP（先寫暫存檔，再原子重新命名）
      final encoder = ZipFileEncoder();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final zipPath = p.join(backupTempDir.path, 'backup-$dateStr.zip');
      final tmpZipPath = '$zipPath.tmp';

      encoder.create(tmpZipPath);
      await for (var entity in backupFolder.list(recursive: true)) {
        if (entity is File) {
          await encoder.addFile(entity);
        }
      }
      await encoder.close();

      // 原子重新命名：確保不會寫到一半產生殘缺 ZIP
      final tmpFile = File(tmpZipPath);
      await tmpFile.rename(zipPath);

      return File(zipPath);
    } catch (e, stack) {
      AppLog.e('建立備份 ZIP 失敗: $e', error: e, stackTrace: stack);
      return null;
    }
  }

  Future<void> _writeMaps(
    Directory folder,
    String name,
    List<Map<String, dynamic>> data,
  ) => File(p.join(folder.path, name)).writeAsString(jsonEncode(data));

  Future<void> _writeJson(
    Directory folder,
    String name,
    List<dynamic> data,
  ) async {
    final file = File(p.join(folder.path, name));
    final jsonList = data.map((e) {
      try {
        final json = (e as dynamic).toJson();
        return json is Map<String, dynamic>
            ? _legadoReadable(name, json)
            : json;
      } catch (err) {
        AppLog.w('Backup: toJson failed for item in $name: $err');
        return e;
      }
    }).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  /// 同一份備份 Legado 也還原得了：Legado 用 Gson 整份讀，開關讀到 `1`／`0`、
  /// 閱讀設定讀到字串時整份放棄（書源還會改用舊格式讀成沒有規則的空殼，
  /// 蓋掉同網址的書源）。這裡只改備份檔：同步的紀錄照 `toJson` 算指紋，
  /// 改了會讓兩台認不出同一條規則。夜讀自己讀兩種寫法都認得。
  /// manifest 裡的這個鍵是 true：readRecord.json 的閱讀時長是毫秒。之前的
  /// 備份是秒。
  static const String readTimeInMillisKey = 'readTimeInMillis';

  static const Map<String, List<String>> _legadoSwitches = {
    'bookshelf.json': ['canUpdate', 'isInBookshelf'],
    'bookSource.json': ['enabled', 'enabledExplore', 'enabledCookieJar'],
    'replaceRule.json': ['scopeTitle', 'scopeContent', 'isEnabled', 'isRegex'],
  };

  static Map<String, dynamic> _legadoReadable(
    String name,
    Map<String, dynamic> json,
  ) {
    switch (name) {
      // Legado 的閱讀時長以毫秒記（`ReadBook.upReadTime`）。
      case 'readRecord.json':
        return {...json, 'readTime': (json['readTime'] as int? ?? 0) * 1000};
      // Legado 的書籤照建立時間（`time`）認，位置與原文的欄位名不同。
      case 'bookmark.json':
        return {
          ...json,
          'time': (json['id'] as int? ?? 0) ~/ 1000,
          'chapterName': json['chapterTitle'],
          'chapterPos': json['charOffset'],
          'bookText': json['excerpt'],
        };
    }
    final switches = _legadoSwitches[name];
    if (switches == null) return json;
    final out = {
      ...json,
      for (final key in switches)
        if (json[key] is int) key: json[key] == 1,
    };
    if (name == 'bookshelf.json') {
      // Legado 的閱讀設定是物件；「模擬追讀」的起始日 Legado 存成日期物件，
      // 夜讀沒有這個功能，不帶。
      final config = json['readConfig'];
      if (config is String) {
        out['readConfig'] = (jsonDecode(config) as Map<String, dynamic>)
          ..remove('startDate');
      }
      // Legado 的閱讀進度欄位。
      out['durChapterIndex'] = json['chapterIndex'];
      out['durChapterPos'] = json['charOffset'];
    }
    return out;
  }
}
