import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:reader/core/constant/app_pattern.dart';
import 'package:reader/core/models/book.dart';

/// BookHelp - 輔助書籍處理工具 (對標 Android help/book/BookHelp.kt)
class BookHelp {
  BookHelp._();

  static const String cacheFolderName = 'book_cache';

  /// 獲取下載/快取根目錄
  static Future<String> getCachePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final path = '${appDir.path}/$cacheFolderName';
    final dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  /// 獲取指定書籍的快取目錄
  static Future<String> getBookCachePath(Book book) async {
    final root = await getCachePath();
    final folderName = book.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '$root/$folderName';
    final dir = Directory(path);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  /// 格式化書名 (對標 Android BookHelp.formatBookName)
  static String formatBookName(String name) {
    return name.replaceAll(AppPattern.nameRegex, '').trim();
  }

  /// 格式化作者 (對標 Android BookHelp.formatBookAuthor)
  static String formatBookAuthor(String author) {
    return author.replaceAll(AppPattern.authorRegex, '').trim();
  }
}
