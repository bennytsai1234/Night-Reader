import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:night_reader/core/constant/app_pattern.dart';
import 'package:night_reader/core/models/book.dart';

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

  /// 手機上已經存著的作者（書、書籤、標註）拿掉開頭的「作者：」；比
  /// [formatBookAuthor] 保守，只動那一種一定是網站字樣的寫法。開頭不是
  /// 「作者：」的原樣傳回，前後空白也不動。
  static String stripAuthorLabel(String author) =>
      AppPattern.authorLabelRegex.hasMatch(author)
      ? author.replaceFirst(AppPattern.authorLabelRegex, '').trim()
      : author;
}
