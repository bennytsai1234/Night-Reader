import 'dart:io';
import 'dart:isolate';

import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

/// 暫存資料夾裡用完就該丟的檔案：開 App 進場播完後，刪掉放超過一天的。
///
/// 只動下面 [_sweepDirs] 這幾個資料夾，資料夾本身留著。暫存根目錄的其他
/// 東西各有用途或由別人管：`libCachedImageData` 是封面快取（照上限自己
/// 淘汰）、`updates` 是下載好的安裝檔、`explore`、`now_playing_art` 與
/// WebView 的資料夾由各自的功能在用；根目錄的零散檔案是書源規則
/// `java.downloadFile` 寫的（Legado 開 App 時也不清），其他套件自己的
/// 資料夾交給套件。
class TempFiles {
  TempFiles._();

  /// 每個資料夾裡放的都是一次性、隔天就用不到的資料：
  /// - `file_picker`：選檔器把使用者選到的檔案複製進來的暫存副本。
  /// - `share_plus`：分享出去前先複製進來的一份。
  /// - `exports`：App 匯出要分享的檔案（[AppStoragePaths.shareExportDir]）。
  /// - `legado_backup_zip`：備份打包的資料與成品（[AppStoragePaths.backupTempDir]）。
  /// - `repair-export`：AI 修復紀錄匯出的壓縮檔。
  /// - `comic_import`：匯入本地漫畫時先複製進來的原檔。
  /// - `comic_sync`：同步本地漫畫時下載下來、等著併進書裡的檔案。
  /// - `ArchiveTemp`：書源規則 `java.unzipFile` 解開的資料。
  static const List<String> _sweepDirs = [
    'file_picker',
    'share_plus',
    'exports',
    'legado_backup_zip',
    'repair-export',
    'comic_import',
    'comic_sync',
    'ArchiveTemp',
  ];

  /// 刪掉 [root] 底下 [_sweepDirs] 裡，修改時間比 `now - maxAge` 舊的項目。
  ///
  /// 走訪與刪除交給 [Isolate.run]，不佔開 App 後的主執行緒。[root] 與
  /// [now] 只給測試指定；平常問平台拿暫存資料夾、用現在的時間。
  static Future<void> sweep({
    Directory? root,
    DateTime? now,
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final rootPath = (root ?? await AppStoragePaths.temporaryDir()).path;
    final cutoff = (now ?? DateTime.now())
        .subtract(maxAge)
        .millisecondsSinceEpoch;
    final (:removed, :bytes) = await Isolate.run(
      () => _sweepSync(rootPath, cutoff),
    );
    if (removed > 0) {
      AppLog.i('暫存清理：刪除 $removed 項，約 $bytes 位元組');
    }
  }

  /// [sweep] 在背景 isolate 跑的部分：只收路徑與時間，不碰主 isolate 的
  /// 東西。
  static ({int removed, int bytes}) _sweepSync(String rootPath, int cutoffMs) {
    final cutoff = DateTime.fromMillisecondsSinceEpoch(cutoffMs);
    var removed = 0;
    var bytes = 0;
    for (final name in _sweepDirs) {
      final dir = Directory(p.join(rootPath, name));
      if (!dir.existsSync()) continue;
      List<FileSystemEntity> children;
      try {
        children = dir.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final child in children) {
        try {
          final (:newest, :size) = _measure(child);
          if (newest == null || !newest.isBefore(cutoff)) continue;
          if (child is Directory) {
            child.deleteSync(recursive: true);
          } else {
            child.deleteSync();
          }
          removed++;
          bytes += size;
        } on FileSystemException {
          // 一項刪不掉不影響其他項目；下次開 App 還會再試。
        }
      }
    }
    return (removed: removed, bytes: bytes);
  }

  /// 項目自己與（資料夾的話）底下每個檔案最新的修改時間，以及會跟著刪掉
  /// 的位元組數。符號連結不跟、也不算：跟著資料夾一起刪時只刪連結本身，
  /// 不會刪到它指向的東西。
  static ({DateTime? newest, int size}) _measure(FileSystemEntity entity) {
    if (entity is File) {
      final stat = entity.statSync();
      return (newest: stat.modified, size: stat.size);
    }
    if (entity is! Directory) return (newest: null, size: 0);
    var newest = entity.statSync().modified;
    var size = 0;
    for (final child in entity.listSync(recursive: true, followLinks: false)) {
      if (child is! File) continue;
      final stat = child.statSync();
      if (stat.modified.isAfter(newest)) newest = stat.modified;
      size += stat.size;
    }
    return (newest: newest, size: size);
  }
}
