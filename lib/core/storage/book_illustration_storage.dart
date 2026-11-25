import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../diagnostics/app_log_service.dart';
import '../models/book/book.dart';
import '../models/book/reader_chapter_content.dart';
import 'app_storage_paths.dart';
import 'storage_metrics.dart';
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

  /// 還原備份、匯入書架檔帶回的網路書正文裡有插圖、這台還沒抓圖時留的
  /// 記號：書架自動下載看到它，把已存正文裡還沒試過的插圖抓下來，都試過了
  /// 就刪掉。
  static const String unfetchedFlagName = '.unfetched';

  /// 留著 [unfetchedFlagName] 時多留的記號：正文是別台分享的書架檔帶回來
  /// 的，插圖網址可能是別人寫的。補抓插圖只對書源同一個網站帶書源的 Cookie
  /// 與登入標頭（ADR 0086）。
  static const String foreignFlagName = '.unfetched-foreign';

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

  static Future<File> _foreignFlag(Book book) async =>
      File(p.join(await dirFor(book), foreignFlagName));

  /// 正文帶回了別台存好的插圖、這台還沒抓：[fromSource] 是從書源抓來的
  /// 正文（還原自己的備份、正常抓章節），[fromSource] 為 false 是別台分享
  /// 的書架檔帶回來的。外來的記號一直留到 [clearUnfetched]，中間別的來源
  /// 再留記號也不會把它變成可信。
  static Future<void> markUnfetched(Book book, {bool fromSource = true}) async {
    // 外來的記號先寫：中途被收掉時，還沒留「待抓」也只會少排一次補抓，
    // 不會把外來的正文當成從書源抓來的。
    if (!fromSource) {
      await (await _foreignFlag(book)).create(recursive: true);
    }
    final flag = await _unfetchedFlag(book);
    await flag.create(recursive: true);
  }

  /// 帶回了別台存好的正文、沒帶圖檔（還原備份、匯入書架檔）：網路書這章
  /// 已存好的正文裡有插圖就留記號，書架自動下載才會把圖補抓下來。記號
  /// 寫不進去也不擋正文：閱讀器打開那一章時還是會補抓。
  static Future<void> markUnfetchedIfIllustrated(
    ReaderChapterContentEntry entry, {
    bool fromSource = true,
  }) async {
    final book = Book(bookUrl: entry.bookUrl, origin: entry.origin);
    if (!entry.isReady ||
        book.isLocal ||
        !(entry.content ?? '').contains('<img')) {
      return;
    }
    try {
      await markUnfetched(book, fromSource: fromSource);
    } on FileSystemException catch (error) {
      AppLog.w('插圖待抓記號寫入失敗 ${entry.bookUrl}: $error');
    }
  }

  static Future<bool> isUnfetched(Book book) async =>
      (await _unfetchedFlag(book)).exists();

  /// 待抓的插圖是從書源抓來的正文（true），還是別台分享的書架檔帶回來的
  /// （false）：後者插圖網址的主機和書源不同時不帶登入資料。
  static Future<bool> isFromSource(Book book) async =>
      !await (await _foreignFlag(book)).exists();

  static Future<void> clearUnfetched(Book book) async {
    // 外來的先刪：中途被收掉時只剩「待抓」，下次照都試過了清掉，不會一直
    // 把正文當成外來的。
    final foreign = await _foreignFlag(book);
    if (await foreign.exists()) await foreign.delete();
    final flag = await _unfetchedFlag(book);
    if (await flag.exists()) await flag.delete();
  }
}
