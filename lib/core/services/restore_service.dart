import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/login_data_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/models/book_group.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:night_reader/core/models/reader_chapter_content.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/sync/read_stats_sync.dart';
import 'package:path/path.dart' as p;

typedef _DecodedFile = ({String fileName, Object? decoded, Object? error});
typedef _DecodedBackup = ({
  Map<String, dynamic>? manifest,
  Object? manifestError,
  List<_DecodedFile> files,
});

/// 一次還原的結果。單一檔案失敗時仍繼續還原其他檔案，失敗的檔名記在
/// [failedFiles]；[invalidArchive] 表示不是可用的備份檔，什麼都沒寫入。
class RestoreResult {
  const RestoreResult({
    this.restoredAny = false,
    this.failedFiles = const [],
    this.invalidArchive = false,
  });

  const RestoreResult.invalid() : this(invalidArchive: true);

  final bool restoredAny;
  final List<String> failedFiles;
  final bool invalidArchive;
}

/// RestoreService - 統一恢復調度器
/// (原 Android help/storage/Restore.kt)
class RestoreService {
  static final RestoreService _instance = RestoreService._internal();
  factory RestoreService() => _instance;
  RestoreService._internal();

  final BookDao _bookDao = getIt<BookDao>();
  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final ReplaceRuleDao _ruleDao = getIt<ReplaceRuleDao>();
  final BookGroupDao _groupDao = getIt<BookGroupDao>();
  final DownloadDao _downloadDao = getIt<DownloadDao>();
  final ReadRecordDao _readRecordDao = getIt<ReadRecordDao>();
  final ReaderChapterContentDao _chapterContentDao =
      getIt<ReaderChapterContentDao>();

  /// 從備份包 (ZIP) 恢復所有數據
  ///
  /// 讀不到檔案時丟出例外，交給呼叫端顯示原因。
  Future<RestoreResult> restoreFromZip(File zipFile) async {
    final path = zipFile.path;
    // 解壓縮與 JSON 解析在背景 isolate 做：備份含已下載的正文時有幾十 MB，
    // 在畫面執行緒上一次解完會卡住將近半秒。
    final backup = await Isolate.run(() => _decodeBackup(path));
    if (backup == null) {
      AppLog.w('Restore aborted: not a zip archive or empty');
      return const RestoreResult.invalid();
    }
    if (backup.manifestError != null) {
      AppLog.e(
        'Restore aborted: unreadable manifest',
        error: backup.manifestError,
      );
    }
    if (!_isManifestCompatible(backup.manifest)) {
      AppLog.w('Restore aborted: missing or incompatible manifest');
      return const RestoreResult.invalid();
    }

    var restoredAny = false;
    final failedFiles = <String>[];
    // 閱讀紀錄的累計與每日秒數要一起還原，不受 ZIP 裡的檔案順序影響；
    // 先收起來，其他檔案還原完再處理。
    final readStatsFiles = <_DecodedFile>[];
    for (final file in backup.files) {
      final (:fileName, :decoded, :error) = file;
      if (_readStatsFiles.contains(fileName)) {
        readStatsFiles.add(file);
        continue;
      }
      try {
        if (error != null) throw error;
        if (LoginDataBackup.files.contains(fileName)) {
          if (decoded is! List<dynamic>) throw FormatException(fileName);
          final restored = await LoginDataBackup.restore(fileName, decoded);
          restoredAny = restoredAny || restored;
        } else if (decoded is List<dynamic>) {
          final restored = await _importListData(fileName, decoded);
          restoredAny = restoredAny || restored;
        } else if (fileName == 'config.json' &&
            decoded is Map<String, dynamic>) {
          final restored = await _restorePreferences(decoded);
          restoredAny = restoredAny || restored;
        }
      } catch (e) {
        // 單一檔案失敗不中斷，其他檔案照樣還原，最後一起回報。
        AppLog.e('Restore failed for $fileName: $e', error: e);
        failedFiles.add(fileName);
      }
    }
    if (readStatsFiles.isNotEmpty) {
      try {
        restoredAny =
            await _restoreReadingStats(
              readStatsFiles,
              fromDevice: backup.manifest?['syncDeviceId'] as String?,
            ) ||
            restoredAny;
      } catch (e) {
        AppLog.e('Restore failed for reading stats: $e', error: e);
        failedFiles.addAll(readStatsFiles.map((file) => file.fileName));
      }
    }
    return RestoreResult(restoredAny: restoredAny, failedFiles: failedFiles);
  }

  static const Set<String> _readStatsFiles = {
    'readRecord.json',
    'readRecords.json',
    'readDay.json',
  };

  /// 任一檔讀不出來就整組不還原，免得累計與每日只換了一半。備份那台用過
  /// 同步（[fromDevice]）時記下還原了哪些，同步時不再算一次（ADR 0039）。
  Future<bool> _restoreReadingStats(
    List<_DecodedFile> files, {
    required String? fromDevice,
  }) async {
    final records = <ReadRecord>[];
    final days = <ReadDay>[];
    for (final (:fileName, :decoded, :error) in files) {
      if (error != null) throw error;
      if (decoded is! List<dynamic>) throw FormatException(fileName);
      for (final item in decoded.whereType<Map<String, dynamic>>()) {
        if (fileName == 'readDay.json') {
          days.add(ReadDay.fromJson(item));
        } else {
          records.add(ReadRecord.fromJson(item));
        }
      }
    }
    await _readRecordDao.restoreReadingStats(records: records, days: days);
    await RestoredStats.remember(
      await SharedPreferences.getInstance(),
      from: fromDevice,
      records: records,
      days: days,
    );
    return records.isNotEmpty || days.isNotEmpty;
  }

  /// 在背景 isolate 讀檔、解壓縮並解析每個 JSON 檔。不是 zip 或沒有檔案時
  /// 回傳 null；單一檔案解析失敗記在該檔的 `error`，由呼叫端回報。背景
  /// isolate 沒有 App 的服務，這裡不寫紀錄，交給呼叫端。
  static Future<_DecodedBackup?> _decodeBackup(String path) async {
    final bytes = await File(path).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final files = archive.where((file) => file.isFile).toList();
    if (files.isEmpty) return null;

    Map<String, dynamic>? manifest;
    Object? manifestError;
    final decodedFiles = <_DecodedFile>[];
    var manifestSeen = false;
    for (final file in files) {
      final fileName = p.basename(file.name);
      Object? decoded;
      Object? error;
      try {
        decoded = jsonDecode(
          utf8.decode(file.content as List<int>, allowMalformed: true),
        );
      } catch (e) {
        error = e;
      }
      if (fileName == 'manifest.json') {
        // 只看第一個 manifest。
        if (manifestSeen) continue;
        manifestSeen = true;
        manifestError = error;
        if (decoded is Map<String, dynamic>) manifest = decoded;
        continue;
      }
      decodedFiles.add((fileName: fileName, decoded: decoded, error: error));
    }
    return (
      manifest: manifest,
      manifestError: manifestError,
      files: decodedFiles,
    );
  }

  Future<bool> _importListData(String fileName, List<dynamic> list) async {
    const supportedFiles = <String>{
      'books.json',
      'bookshelf.json',
      'bookSources.json',
      'bookSource.json',
      'replaceRules.json',
      'replaceRule.json',
      'bookGroups.json',
      'bookGroup.json',
      'downloadTask.json',
      'downloadTasks.json',
      'readerChapterContent.json',
      'readerChapterContents.json',
    };
    if (!supportedFiles.contains(fileName)) return false;

    // 一個檔案在一個交易裡寫完：書架、書源這些清單只在交易結束時重新查詢
    // 一次，不會每寫一筆就讓發現、書源管理整份重算（上百個書源時還原會
    // 卡住數秒）。檔案中途失敗時整個檔案不寫入，由呼叫端記為失敗。
    var importedAny = false;
    await getIt<AppDatabase>().transaction(() async {
      importedAny = await _importItems(fileName, list);
    });
    return list.isEmpty || importedAny;
  }

  Future<bool> _importItems(String fileName, List<dynamic> list) async {
    var importedAny = false;
    for (var item in list) {
      if (item is Map<String, dynamic>) {
        importedAny = true;
        switch (fileName) {
          case 'books.json':
          case 'bookshelf.json':
            await _bookDao.upsert(Book.fromJson(item));
            break;
          case 'bookSources.json':
          case 'bookSource.json':
            await _sourceDao.upsert(BookSource.fromJson(item));
            break;
          case 'replaceRules.json':
          case 'replaceRule.json':
            await _ruleDao.upsert(ReplaceRule.fromJson(item));
            break;
          case 'bookGroups.json':
          case 'bookGroup.json':
            await _groupDao.upsert(BookGroup.fromJson(item));
            break;
          case 'downloadTask.json':
          case 'downloadTasks.json':
            await _downloadDao.upsert(DownloadTask.fromJson(item));
            break;
          case 'readerChapterContent.json':
          case 'readerChapterContents.json':
            await _chapterContentDao.upsertEntry(
              ReaderChapterContentEntry.fromJson(item),
            );
            break;
        }
      }
    }
    return importedAny;
  }

  Future<bool> _restorePreferences(Map<String, dynamic> values) async {
    if (values.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    var restoredAny = false;
    for (final entry in values.entries) {
      final val = entry.value;
      if (val is String) {
        restoredAny = await prefs.setString(entry.key, val) || restoredAny;
      } else if (val is int) {
        restoredAny = await prefs.setInt(entry.key, val) || restoredAny;
      } else if (val is bool) {
        restoredAny = await prefs.setBool(entry.key, val) || restoredAny;
      } else if (val is double) {
        restoredAny = await prefs.setDouble(entry.key, val) || restoredAny;
      } else if (val is List) {
        final strings = val.whereType<String>().toList();
        if (strings.length == val.length) {
          restoredAny =
              await prefs.setStringList(entry.key, strings) || restoredAny;
        }
      }
    }
    return restoredAny;
  }

  bool _isManifestCompatible(Map<String, dynamic>? manifest) {
    if (manifest == null) return false;
    final schemaVersion = manifest['schemaVersion'];
    if (schemaVersion is! int) return false;
    return schemaVersion <= getIt<AppDatabase>().schemaVersion;
  }
}
