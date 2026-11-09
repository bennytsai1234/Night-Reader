import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../storage/app_storage_paths.dart';
import '../storage/storage_metrics.dart';
import '../utils/illustration_markers.dart';
import 'book_cover_storage_service.dart';

/// 一本書的插圖放在這本書的資料夾裡（`book_assets/<書>/images/`，ADR 0050）：
/// 網路書下載章節時抓進來，EPUB 轉文字時抽出來；移出書架時跟著整個書本
/// 資料夾刪掉。備份不帶插圖，還原後網路書照書架自動下載重抓。
abstract final class BookIllustrationStorage {
  static const String folderName = 'images';

  /// 抓過但網站回了錯誤碼、或回的不是圖：記成「確定抓不到」的空檔，接在
  /// 圖的檔名後面。已存的正文再打開時不再抓，重新取得這一章時再試。
  static const String missingSuffix = '.missing';

  /// 還原備份帶回的網路書正文裡有插圖、這台還沒抓圖時留的記號：書架自動
  /// 下載看到它，把已存正文裡還沒試過的插圖抓下來，都試過了就刪掉。
  static const String unfetchedFlagName = '.unfetched';

  /// [src]（網路書的網址、EPUB 裡的路徑）這張圖的檔名：一律雜湊成檔名，
  /// 同一張圖只存一份。
  static String fileNameFor(String src) =>
      sha1.convert(utf8.encode(src)).toString();

  static String pathFor(String illustrationsDir, String src) =>
      p.join(illustrationsDir, fileNameFor(src));

  static String missingPathFor(String illustrationsDir, String src) =>
      '${pathFor(illustrationsDir, src)}$missingSuffix';

  /// [content] 裡還沒試過的插圖網址：圖檔不在、也沒記成確定抓不到。剛
  /// 還原備份（插圖不在備份裡）時，已存正文裡的圖都是這種。
  static Future<List<String>> untriedSources(
    String illustrationsDir,
    String content,
  ) async => [
    for (final src in IllustrationMarkers.sourcesOf(content).toSet())
      if (!await File(pathFor(illustrationsDir, src)).exists() &&
          !await File(missingPathFor(illustrationsDir, src)).exists())
        src,
  ];

  /// 網路書清除正文快取時一起刪；下次抓章節時再抓回來。
  static Future<void> deleteFor(Book book) async {
    final dir = Directory(await dirFor(book));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 這本書的插圖共多少位元組。
  static Future<int> sizeOf(Book book) async =>
      StorageMetrics.directorySize(Directory(await dirFor(book)));

  static Future<String> dirFor(Book book) async {
    final dir = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(book),
    );
    return p.join(dir.path, folderName);
  }

  static Future<File> _unfetchedFlag(Book book) async =>
      File(p.join(await dirFor(book), unfetchedFlagName));

  static Future<void> markUnfetched(Book book) async {
    final flag = await _unfetchedFlag(book);
    await flag.create(recursive: true);
  }

  static Future<bool> isUnfetched(Book book) async =>
      (await _unfetchedFlag(book)).exists();

  static Future<void> clearUnfetched(Book book) async {
    final flag = await _unfetchedFlag(book);
    if (await flag.exists()) await flag.delete();
  }
}
