import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../storage/app_storage_paths.dart';
import 'book_cover_storage_service.dart';

/// 一本書的插圖放在這本書的資料夾裡（`book_assets/<書>/images/`，ADR 0050）：
/// 網路書下載章節時抓進來，EPUB 轉文字時抽出來；移出書架時跟著整個書本
/// 資料夾刪掉。檔名是 [ReaderV2IllustrationMarkers.fileNameFor]。
abstract final class BookIllustrationStorage {
  static const String folderName = 'images';

  static Future<String> dirFor(Book book) async {
    final dir = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(book),
    );
    return p.join(dir.path, folderName);
  }
}
