import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/chapter.dart';
import '../storage/app_storage_paths.dart';
import '../storage/storage_metrics.dart';
import 'book_cover_storage_service.dart';

/// 檔案型章節：正文不是文字、不進 SQLite 的章節（有聲書的音訊，ADR 0050；
/// 漫畫一章一個 CBZ，ADR 0052）存成這本書資料夾裡的檔案：
/// `book_assets/<書>/chapters/<章節網址的雜湊>.<副檔名>`。
///
/// - **已下載**：最後的檔案在就是下載好了。下載中寫在 `.part`（或另一個
///   名稱的暫存檔、資料夾），寫完才改名成最後的檔名，所以 App 中途被關掉也
///   不會把半個檔當成下載好。
/// - **移出書架就刪**：整個書本資料夾由 `BookStorageService.discardBook` 刪掉；
///   換源時舊書源的資料夾也刪（章節網址不同，檔案用不到）。
/// - **清除下載**：[deleteFor] 只刪這本書的章節檔，封面與插圖不動。
/// - **不進備份**：備份只帶資料庫的內容，書本資料夾不在裡面；還原後由使用者
///   （有聲書）或書架自動下載（漫畫）再抓。
abstract final class BookChapterFiles {
  static const String folderName = 'chapters';

  /// 還沒寫完的檔案加上的副檔名。
  static const String partialSuffix = '.part';

  /// 這本書的章節檔資料夾（不保證存在）。
  static Future<String> dirFor(Book book) async {
    final dir = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(book),
    );
    return p.join(dir.path, folderName);
  }

  /// [chapter] 的檔名（不含副檔名）：章節網址的雜湊。目錄中間插入章節時
  /// 序號會變，網址不會。
  static String baseNameFor(BookChapter chapter) =>
      sha1.convert(utf8.encode(chapter.url)).toString();

  /// [chapter] 存成 [extension]（例如 `.mp3`、`.cbz`）時的路徑。
  static String pathFor(String dir, BookChapter chapter, String extension) =>
      p.join(dir, '${baseNameFor(chapter)}$extension');

  /// 已下載好的章節：檔名（[baseNameFor]）對到檔案。讀一次資料夾，給整份
  /// 目錄標「已下載」用。
  static Future<Map<String, File>> downloaded(Book book) async {
    final dir = Directory(await dirFor(book));
    final files = <String, File>{};
    if (!await dir.exists()) return files;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith(partialSuffix)) continue;
      files[p.basenameWithoutExtension(name)] = entity;
    }
    return files;
  }

  /// [chapter] 下載好的檔案；還沒下載時是 null。
  static Future<File?> fileFor(Book book, BookChapter chapter) async =>
      (await downloaded(book))[baseNameFor(chapter)];

  /// 把 [chapter] 寫成 [extension] 的檔案：[write] 寫進交給它的暫存檔，
  /// 寫完才改名成最後的檔名。[write] 丟出錯誤時刪掉暫存檔、照樣丟出。
  static Future<File> save(
    Book book,
    BookChapter chapter,
    String extension,
    Future<void> Function(File partial) write,
  ) async {
    final dir = Directory(await dirFor(book));
    await dir.create(recursive: true);
    final target = File(pathFor(dir.path, chapter, extension));
    final partial = File('${target.path}$partialSuffix');
    try {
      await write(partial);
      if (await target.exists()) await target.delete();
      return await partial.rename(target.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  /// 刪掉這本書所有的章節檔（含沒寫完的）。
  static Future<void> deleteFor(Book book) async {
    final dir = Directory(await dirFor(book));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 這本書的章節檔共多少位元組（含沒寫完的）。
  static Future<int> sizeOf(Book book) async =>
      StorageMetrics.directorySize(Directory(await dirFor(book)));
}
