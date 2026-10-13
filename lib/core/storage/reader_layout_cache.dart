import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../services/app_version.dart';
import 'app_storage_paths.dart';

/// 閱讀器排版快取在磁碟上的位置與清理。
///
/// 兩種快取都只用來省掉重算，刪掉只會讓下次開書重新量測與換行：
/// - 段落尺寸：`hybrid_metrics/<書>/<樣式>.bin`
/// - 章節換行：`hybrid_plans/<App 版本>/<書>/<樣式>/<章>.json`
///
/// 清理時機：書從資料庫刪除時一起刪；App 啟動時刪掉資料庫裡已經沒有的
/// 書，以及其他 App 版本的換行快取（換行規則跟著程式走，換版後都失效）；
/// 每本書寫入時只留最近使用的 [keptStylesPerBook] 組樣式。
abstract final class ReaderLayoutCache {
  static const String _metricsDirName = 'hybrid_metrics';
  static const String _plansDirName = 'hybrid_plans';

  /// 每本書保留的排版樣式組數。留兩組，讓轉向或把某個設定切過去再切
  /// 回來時不必整本重算；更早的樣式在下一次寫入時刪掉。
  static const int keptStylesPerBook = 2;

  static Future<Directory> baseDirectory() => AppStoragePaths.supportDir();

  /// 換行快取所屬的 App 版本；換版後舊版本的換行結果一律不沿用。
  static Future<String> currentBuild() async {
    final version = await AppVersion.current();
    return '${version.versionName}+${version.buildNumber}';
  }

  static String _key(String value) =>
      sha1.convert(utf8.encode(value)).toString();

  static Directory metricsBookDir(Directory base, String bookUrl) =>
      Directory(p.join(base.path, _metricsDirName, _key(bookUrl)));

  static File metricsFile(Directory base, String bookUrl, String styleKey) =>
      File(p.join(metricsBookDir(base, bookUrl).path, '${_key(styleKey)}.bin'));

  static Directory plansBookDir(Directory base, String build, String bookUrl) =>
      Directory(p.join(base.path, _plansDirName, _key(build), _key(bookUrl)));

  static Directory plansStyleDir(
    Directory base,
    String build,
    String bookUrl,
    String styleKey,
  ) => Directory(
    p.join(plansBookDir(base, build, bookUrl).path, _key(styleKey)),
  );

  /// 刪掉一本書的全部排版快取。
  static Future<void> deleteBook(String bookUrl, {Directory? base}) async {
    final root = base ?? await baseDirectory();
    final bookKey = _key(bookUrl);
    await _deleteIfExists(metricsBookDir(root, bookUrl));
    final plans = Directory(p.join(root.path, _plansDirName));
    if (!await plans.exists()) return;
    await for (final build in plans.list()) {
      if (build is Directory) {
        await _deleteIfExists(Directory(p.join(build.path, bookKey)));
      }
    }
  }

  /// 只留下 [bookUrls] 這些書、以及目前 App 版本的排版快取。
  static Future<void> retainOnly({
    required Iterable<String> bookUrls,
    required String build,
    Directory? base,
  }) async {
    final root = base ?? await baseDirectory();
    final keep = {for (final url in bookUrls) _key(url)};
    await _retainChildren(Directory(p.join(root.path, _metricsDirName)), keep);
    final plans = Directory(p.join(root.path, _plansDirName));
    final buildKey = _key(build);
    await _retainChildren(plans, {buildKey});
    await _retainChildren(Directory(p.join(plans.path, buildKey)), keep);
  }

  /// [bookDir] 底下每個樣式一項；只留最近寫入的 [keptStylesPerBook] 項。
  static Future<void> pruneStyles(Directory bookDir) async {
    if (!await bookDir.exists()) return;
    final entries = <(FileSystemEntity, DateTime)>[];
    await for (final entry in bookDir.list()) {
      if (p.extension(entry.path) == '.tmp') continue;
      try {
        entries.add((entry, (await entry.stat()).modified));
      } on FileSystemException {
        // 另一個寫入者剛好刪掉或改名了這一項。
      }
    }
    if (entries.length <= keptStylesPerBook) return;
    entries.sort((a, b) => b.$2.compareTo(a.$2));
    for (final (entry, _) in entries.skip(keptStylesPerBook)) {
      await _deleteIfExists(entry);
    }
  }

  static Future<void> _retainChildren(Directory dir, Set<String> keep) async {
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (!keep.contains(p.basename(entry.path))) await _deleteIfExists(entry);
    }
  }

  static Future<void> _deleteIfExists(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } on FileSystemException {
      // 不存在或已被另一個清理刪掉。
    }
  }
}
