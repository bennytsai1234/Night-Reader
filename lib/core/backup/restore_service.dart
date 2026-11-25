import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:night_reader/shared/widgets/glass/tab_bar_look.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/storage/book_cover_storage_service.dart';
import 'package:night_reader/core/storage/book_storage_service.dart';
import 'package:night_reader/core/backup/backup_service.dart';
import 'package:night_reader/core/backup/login_data_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/constant/book_type.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/json_read.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/search/ai_find_record.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/models/book/book_group.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/models/reading/read_record.dart';
import 'package:night_reader/core/models/book/reader_chapter_content.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/download/download_service.dart';
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
  final BookmarkDao _bookmarkDao = getIt<BookmarkDao>();
  final HighlightDao _highlightDao = getIt<HighlightDao>();
  final AiFindDao _aiFindDao = getIt<AiFindDao>();
  final ReadRecordDao _readRecordDao = getIt<ReadRecordDao>();
  final ReaderChapterContentDao _chapterContentDao =
      getIt<ReaderChapterContentDao>();

  /// 從備份包 (ZIP) 恢復所有數據
  ///
  /// [restoreSettings] 是 false 時設定（`config.json`）不動、保留這台的，
  /// 其他資料照樣還原；登入資料不算設定（ADR 0039）。
  ///
  /// 讀不到檔案時丟出例外，交給呼叫端顯示原因。
  Future<RestoreResult> restoreFromZip(
    File zipFile, {
    bool restoreSettings = true,
  }) async {
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
    // Legado 的備份沒有 manifest（`Backup.kt`），照裡面的檔名認。
    final fromLegado =
        backup.manifest == null &&
        backup.files.any((file) => _legadoFiles.contains(file.fileName));
    if (!fromLegado && !_isManifestCompatible(backup.manifest)) {
      AppLog.w('Restore aborted: missing or incompatible manifest');
      return const RestoreResult.invalid();
    }

    // 備份裡有下載任務的書：正在下載的先停下、等它收尾，整份還原完才照
    // 還原的資料接著（[DownloadService.holdForRestore]）。
    final downloadBooks = {
      for (final file in backup.files)
        if (_downloadTaskFiles.contains(file.fileName) &&
            file.decoded is List<dynamic>)
          for (final item
              in (file.decoded as List<dynamic>)
                  .whereType<Map<String, dynamic>>())
            if (item['bookUrl'] case final String bookUrl) bookUrl,
    };
    final releaseDownloads = downloadBooks.isEmpty
        ? () async {}
        : await DownloadService().holdForRestore(downloadBooks);
    try {
      return await _restore(
        backup,
        fromLegado: fromLegado,
        restoreSettings: restoreSettings,
      );
    } finally {
      await releaseDownloads();
    }
  }

  static const Set<String> _downloadTaskFiles = {
    'downloadTask.json',
    'downloadTasks.json',
  };

  Future<RestoreResult> _restore(
    _DecodedBackup backup, {
    required bool fromLegado,
    required bool restoreSettings,
  }) async {
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
      // 夜讀不還原的檔（Legado 的 `config.xml`、夜讀沒有的功能）讀不懂也
      // 不算失敗。
      if (!_restorableFiles.contains(fileName) &&
          !LoginDataBackup.files.contains(fileName)) {
        continue;
      }
      // 不還原設定時連讀都不讀，設定檔壞了也不算失敗。
      if (!restoreSettings && fileName == _settingsFile) continue;
      try {
        if (error != null) throw error;
        if (LoginDataBackup.files.contains(fileName)) {
          if (decoded is! List<dynamic>) throw FormatException(fileName);
          final restored = await LoginDataBackup.restore(fileName, decoded);
          restoredAny = restoredAny || restored;
        } else if (decoded is List<dynamic>) {
          final restored = await _importListData(
            fileName,
            decoded,
            fromLegado: fromLegado,
          );
          restoredAny = restoredAny || restored;
        } else if (fileName == _settingsFile &&
            decoded is Map<String, dynamic>) {
          final restored = await _restorePreferences(
            TabBarLook.migrateBackup(decoded),
          );
          restoredAny = restoredAny || restored;
        }
      } catch (e) {
        // 單一檔案失敗不中斷，其他檔案照樣還原，最後一起回報。
        AppLog.e('Restore failed for $fileName: $e', error: e);
        failedFiles.add(fileName);
      }
    }
    // 書與書源照 ZIP 裡的順序分開寫進來：都寫完再讓書跟著書源的類型
    // （ADR 0053）。
    try {
      await _sourceDao.followAllKinds();
    } catch (e) {
      AppLog.e('Restore: books following source kinds failed: $e', error: e);
    }
    // 舊備份的書、書籤與標註可能還帶著「作者：」這類字樣：照升級時的
    // 同一套拿掉，書名加作者才和這台、別台對得上。
    try {
      await getIt<AppDatabase>().cleanBookAuthors();
    } catch (e) {
      AppLog.e('Restore: cleaning book authors failed: $e', error: e);
    }
    // 舊備份帶的正文與目錄可能屬於沒還原的書架以外的書，或早就刪掉的書。
    try {
      await BookStorageService().discardUnshelvedBooks();
    } catch (e) {
      AppLog.e('Restore: discard unshelved books failed: $e', error: e);
    }
    if (readStatsFiles.isNotEmpty) {
      try {
        restoredAny =
            await _restoreReadingStats(
              readStatsFiles,
              fromDevice: backup.manifest?['syncDeviceId'] as String?,
              inMillis:
                  fromLegado ||
                  backup.manifest?[BackupService.readTimeInMillisKey] == true,
            ) ||
            restoredAny;
      } catch (e) {
        AppLog.e('Restore failed for reading stats: $e', error: e);
        failedFiles.addAll(readStatsFiles.map((file) => file.fileName));
      }
    }
    return RestoreResult(restoredAny: restoredAny, failedFiles: failedFiles);
  }

  /// Legado 備份 ZIP 裡的檔（`Backup.kt` 的 `backupFileNames`，夜讀讀得懂的
  /// 那幾個）。
  static const Set<String> _legadoFiles = {
    'bookshelf.json',
    'bookmark.json',
    'bookGroup.json',
    'bookSource.json',
    'replaceRule.json',
    'readRecord.json',
    'config.xml',
  };

  static const Set<String> _readStatsFiles = {
    'readRecord.json',
    'readRecords.json',
    'readDay.json',
  };

  /// 一筆一筆寫進資料庫的清單檔（含舊備份的檔名）。
  static const Set<String> _listFiles = {
    'books.json',
    'bookshelf.json',
    'bookSources.json',
    'bookSource.json',
    'replaceRules.json',
    'replaceRule.json',
    'bookGroups.json',
    'bookGroup.json',
    'bookmark.json',
    'bookmarks.json',
    'highlight.json',
    'aiFind.json',
    'downloadTask.json',
    'downloadTasks.json',
    'readerChapterContent.json',
    'readerChapterContents.json',
  };

  /// 設定：備份那台偏好設定裡的每一項（[BackupService.deviceOnlyKeys] 以外），
  /// 含外觀、閱讀、朗讀、書架顯示、同步空間與 AI 服務。
  static const String _settingsFile = 'config.json';

  /// 夜讀會還原的檔；登入資料另見 [LoginDataBackup.files]，閱讀統計另外
  /// 收（[_readStatsFiles]）。
  static const Set<String> _restorableFiles = {..._listFiles, _settingsFile};

  /// 任一檔讀不出來就整組不還原，免得累計與每日只換了一半。備份那台用過
  /// 同步（[fromDevice]）時記下還原了哪些，同步時不再算一次（ADR 0039）。
  Future<bool> _restoreReadingStats(
    List<_DecodedFile> files, {
    required String? fromDevice,
    required bool inMillis,
  }) async {
    var records = <ReadRecord>[];
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
    if (inMillis) records = _fromMillisRecords(records);
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

  /// 閱讀時長以毫秒記的備份（Legado 的，與照 Legado 寫的夜讀備份，
  /// [BackupService.readTimeInMillisKey]）：Legado 一台一筆，夜讀以秒記、一本
  /// 書一筆：換成秒，同一本書各台的加起來（Legado 顯示的也是加總，
  /// `ReadRecordDao.getReadTime`），最後閱讀時間取最晚的。
  static List<ReadRecord> _fromMillisRecords(List<ReadRecord> records) {
    final byBook = <String, ReadRecord>{};
    for (final record in records) {
      final seconds = record.readTime ~/ 1000;
      final existing = byBook[record.bookName];
      if (existing == null) {
        byBook[record.bookName] = ReadRecord(
          deviceId: record.deviceId,
          bookName: record.bookName,
          readTime: seconds,
          lastRead: record.lastRead,
        );
        continue;
      }
      existing
        ..readTime += seconds
        ..lastRead = existing.lastRead > record.lastRead
            ? existing.lastRead
            : record.lastRead;
    }
    return byBook.values.toList();
  }

  /// Legado 的書：沒有「在不在書架上」這欄，記在類型的位元裡
  /// （`BookType.notShelf`）；閱讀進度叫 `durChapterIndex`、`durChapterPos`。
  static Map<String, dynamic> _fromLegadoBook(Map<String, dynamic> item) => {
    ...item,
    'isInBookshelf': BookType.isOnShelf(readJsonInt(item['type'], fallback: 0)),
    'chapterIndex': ?item['durChapterIndex'],
    'charOffset': ?item['durChapterPos'],
  };

  Future<bool> _importListData(
    String fileName,
    List<dynamic> list, {
    required bool fromLegado,
  }) async {
    if (!_listFiles.contains(fileName)) return false;

    // 一個檔案在一個交易裡寫完：書架、書源這些清單只在交易結束時重新查詢
    // 一次，不會每寫一筆就讓發現、書源管理整份重算（上百個書源時還原會
    // 卡住數秒）。檔案中途失敗時整個檔案不寫入，由呼叫端記為失敗。
    var importedAny = false;
    await getIt<AppDatabase>().transaction(() async {
      importedAny = await _importItems(fileName, list, fromLegado: fromLegado);
    });
    return list.isEmpty || importedAny;
  }

  Future<bool> _importItems(
    String fileName,
    List<dynamic> list, {
    required bool fromLegado,
  }) async {
    var importedAny = false;
    for (var item in list) {
      if (item is Map<String, dynamic>) {
        importedAny = true;
        switch (fileName) {
          case 'books.json':
          case 'bookshelf.json':
            // 舊備份也帶著書架以外的書（打開詳情或閱讀器時的暫存）：不還原，
            // 也不拿它把這台書架上的同一本蓋成不在書架上。
            final book = Book.fromJson(
              fromLegado ? _fromLegadoBook(item) : item,
            );
            if (book.isInBookshelf) {
              // 書本資料夾不在備份裡（`BookChapterFiles`）：新手機上沒有
              // 存好的封面檔，改用網址。
              await BookCoverStorageService.dropMissingCoverFiles(book);
              await _bookDao.upsert(book);
            }
            break;
          case 'bookSources.json':
          case 'bookSource.json':
            await _sourceDao.upsert(
              BookSource.fromJson(item)..prepareIncoming(),
            );
            break;
          case 'replaceRules.json':
          case 'replaceRule.json':
            await _ruleDao.upsert(ReplaceRule.fromJson(item));
            break;
          case 'bookGroups.json':
          case 'bookGroup.json':
            await _groupDao.upsert(BookGroup.fromJson(item));
            break;
          case 'bookmark.json':
          case 'bookmarks.json':
            // Legado 書籤的附註（`content`）在夜讀是標註的備忘（ADR 0044）：
            // 有附註的轉成一筆帶備忘的標註，畫在書籤記的原文上。
            final noted = Highlight.fromLegadoBookmark(item);
            if (noted != null) {
              await _highlightDao.upsertAll([noted]);
              break;
            }
            // 2026-09 以前的備份也有書籤，欄位不同，`Bookmark.fromJson` 都讀得懂。
            final bookmark = Bookmark.fromJson(item);
            if (bookmark.id > 0 && bookmark.bookName.isNotEmpty) {
              await _bookmarkDao.upsertAll([bookmark]);
            }
            break;
          case 'highlight.json':
            final highlight = Highlight.fromJson(item);
            if (highlight.id > 0 &&
                highlight.bookName.isNotEmpty &&
                highlight.quote.isNotEmpty) {
              await _highlightDao.upsertAll([highlight]);
            }
            break;
          case 'aiFind.json':
            final find = AiFindRecord.fromJson(item);
            if (find.id.isNotEmpty) await _aiFindDao.upsert(find);
            break;
          case 'downloadTask.json':
          case 'downloadTasks.json':
            await getIt<DownloadDao>().upsert(DownloadTask.fromJson(item));
            break;
          case 'readerChapterContent.json':
          case 'readerChapterContents.json':
            final entry = ReaderChapterContentEntry.fromJson(item);
            await _chapterContentDao.upsertEntry(entry);
            await BookIllustrationStorage.markUnfetchedIfIllustrated(entry);
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
      if (BackupService.deviceOnlyKeys.contains(entry.key)) continue;
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
