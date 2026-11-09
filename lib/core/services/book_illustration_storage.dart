import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../storage/app_storage_paths.dart';
import 'book_cover_storage_service.dart';

/// 一本書的插圖放在這本書的資料夾裡（`book_assets/<書>/images/`，ADR 0050）：
/// 網路書下載章節時抓進來，EPUB 轉文字時抽出來；移出書架時跟著整個書本
/// 資料夾刪掉。
abstract final class BookIllustrationStorage {
  static const String folderName = 'images';

  /// [src]（網路書的網址、EPUB 裡的路徑）這張圖的檔名：一律雜湊成檔名，
  /// 同一張圖只存一份。
  static String fileNameFor(String src) =>
      sha1.convert(utf8.encode(src)).toString();

  static String pathFor(String illustrationsDir, String src) =>
      p.join(illustrationsDir, fileNameFor(src));

  static Future<String> dirFor(Book book) async {
    final dir = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(book),
    );
    return p.join(dir.path, folderName);
  }
}
