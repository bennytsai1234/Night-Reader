import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/storage/resource_service.dart';
import 'package:night_reader/core/storage/source_cover_loader.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

class BookCoverStorageService {
  static final BookCoverStorageService _instance =
      BookCoverStorageService._internal();
  factory BookCoverStorageService() => _instance;
  BookCoverStorageService._internal();

  /// 從別處收進來的書（還原備份、匯入書架檔）：封面的本機檔是存的那台
  /// 手機的，這台沒有時拿掉，顯示改回封面網址。同一台手機還原時檔案還在，
  /// 照留。從相簿選的自訂封面（`file://`）網址照留，顯示時只用存好的那份
  /// （`Book.getDisplayCover`）。
  static Future<void> dropMissingCoverFiles(Book book) async {
    if (await _missing(book.coverLocalPath)) book.coverLocalPath = null;
    if (await _missing(book.customCoverLocalPath)) {
      book.customCoverLocalPath = null;
    }
  }

  static Future<bool> _missing(String? path) async =>
      path != null && path.isNotEmpty && !await File(path).exists();

  Future<void> ensureBookCoverStored(Book book) async {
    final source = book.coverUrl?.trim();
    if (source == null || source.isEmpty) return;
    final path = await _storeCoverSource(
      book: book,
      source: source,
      prefix: 'cover',
    );
    if (path != null && path.isNotEmpty) {
      book.coverLocalPath = path;
    }
  }

  /// 書檔裡自帶的封面（EPUB）。存不下時照樣匯入，書架畫預設封面。
  Future<void> storeEmbeddedCover(
    Book book,
    Uint8List bytes, {
    required String extension,
  }) async {
    try {
      book.coverLocalPath = await _writeCover(
        book,
        'cover-embedded$extension',
        bytes,
      );
    } catch (e, stack) {
      AppLog.e('保存本地封面失敗: $e', error: e, stackTrace: stack);
    }
  }

  Future<void> ensureCustomCoverStored(Book book) async {
    final source = book.customCoverUrl?.trim();
    if (source == null || source.isEmpty) {
      book.customCoverLocalPath = null;
      return;
    }
    final path = await _storeCoverSource(
      book: book,
      source: source,
      prefix: 'custom-cover',
    );
    if (path != null && path.isNotEmpty) {
      book.customCoverLocalPath = path;
    }
  }

  Future<void> ensureDisplayCoverStored(Book book) async {
    if ((book.customCoverUrl ?? '').trim().isNotEmpty) {
      await ensureCustomCoverStored(book);
      return;
    }
    await ensureBookCoverStored(book);
  }

  Future<void> handoffSourceSwitchAssets(
    Book oldBook,
    Book migratedBook,
  ) async {
    if (bookStorageKey(oldBook) == bookStorageKey(migratedBook)) return;

    final oldDir = await AppStoragePaths.bookAssetDir(bookStorageKey(oldBook));
    var keepOldAssets = false;
    final oldCustomPath = oldBook.customCoverLocalPath?.trim();
    if ((migratedBook.customCoverUrl ?? '').trim().isNotEmpty &&
        oldCustomPath != null &&
        oldCustomPath.isNotEmpty) {
      final oldCustomFile = File(oldCustomPath);
      if (await oldCustomFile.exists()) {
        try {
          final newDir = await AppStoragePaths.bookAssetDir(
            bookStorageKey(migratedBook),
            ensureExists: true,
          );
          final source = migratedBook.customCoverUrl!.trim();
          final sourceHash = sha1.convert(utf8.encode(source)).toString();
          final extension = p.extension(oldCustomFile.path).toLowerCase();
          final safeExtension =
              const {
                '.jpg',
                '.jpeg',
                '.png',
                '.webp',
                '.gif',
              }.contains(extension)
              ? extension
              : '.jpg';
          final newCustomFile = File(
            p.join(newDir.path, 'custom-cover-$sourceHash$safeExtension'),
          );
          await oldCustomFile.copy(newCustomFile.path);
          migratedBook.customCoverLocalPath = newCustomFile.path;
        } catch (error, stack) {
          // A user-selected custom cover is logical-book data. If migration
          // fails, keep the old cached file referenced rather than deleting it.
          migratedBook.customCoverLocalPath = oldCustomPath;
          keepOldAssets = true;
          AppLog.e('遷移自訂封面快取失敗，保留舊檔: $error', error: error, stackTrace: stack);
        }
      }
    }

    if (!keepOldAssets && await oldDir.exists()) {
      try {
        await oldDir.delete(recursive: true);
      } catch (error, stack) {
        // Old source cover cache is derived data. Cleanup failure must not
        // prevent the migrated custom-cover path from becoming authoritative.
        AppLog.e('清理舊來源封面快取失敗: $error', error: error, stackTrace: stack);
      }
    }
  }

  /// 書的書源網址換成 [toOrigin]（書源改網址、重複書源合併）：書本資料夾
  /// 的名字照書源網址算（[bookStorageKey]），下載好的漫畫、有聲書、插圖與
  /// 存好的封面整個搬到新的位置，封面路徑改指過去。新位置已經有資料夾時
  /// 把缺的檔併進去。傳回封面路徑改過的書（已換成新的書源網址），由呼叫端
  /// 寫回資料庫。搬不動的那本留在原處、記下錯誤，不擋其他本。
  Future<List<Book>> moveBookAssets(List<Book> books, String toOrigin) async {
    final repointed = <Book>[];
    for (final book in books) {
      final moved = book.copyWith(origin: toOrigin);
      final from = await AppStoragePaths.bookAssetDir(bookStorageKey(book));
      final to = await AppStoragePaths.bookAssetDir(bookStorageKey(moved));
      if (from.path == to.path || !await from.exists()) continue;
      try {
        if (await to.exists()) {
          await _mergeDirectory(from, to);
        } else {
          await to.parent.create(recursive: true);
          await from.rename(to.path);
        }
      } catch (error, stack) {
        AppLog.e('書源換網址時搬書本資料夾失敗: $error', error: error, stackTrace: stack);
        continue;
      }
      String? repoint(String? path) =>
          path != null && p.isWithin(from.path, path)
          ? p.join(to.path, p.relative(path, from: from.path))
          : path;
      final cover = repoint(book.coverLocalPath);
      final custom = repoint(book.customCoverLocalPath);
      if (cover == book.coverLocalPath && custom == book.customCoverLocalPath) {
        continue;
      }
      repointed.add(
        moved
          ..coverLocalPath = cover
          ..customCoverLocalPath = custom,
      );
    }
    return repointed;
  }

  /// [from] 裡 [to] 還沒有的檔搬進 [to]，[from] 刪掉。
  static Future<void> _mergeDirectory(Directory from, Directory to) async {
    await for (final entity in from.list(followLinks: false)) {
      final target = p.join(to.path, p.basename(entity.path));
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
        await _mergeDirectory(entity, Directory(target));
      } else if (await FileSystemEntity.type(target) ==
          FileSystemEntityType.notFound) {
        await entity.rename(target);
      }
    }
    await from.delete(recursive: true);
  }

  Future<void> deleteBookAssets(Book book) async {
    final dir = await AppStoragePaths.bookAssetDir(bookStorageKey(book));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    book.coverLocalPath = null;
    book.customCoverLocalPath = null;
  }

  static String bookStorageKey(Book book) {
    final material = '${book.origin}\n${book.bookUrl}';
    return sha1.convert(utf8.encode(material)).toString();
  }

  Future<String?> _storeCoverSource({
    required Book book,
    required String source,
    required String prefix,
  }) async {
    try {
      final bytes = await _readCoverBytes(source, book);
      if (bytes == null || bytes.isEmpty) return null;

      final sourceHash = sha1.convert(utf8.encode(source)).toString();
      return await _writeCover(
        book,
        '$prefix-$sourceHash${_extensionForSource(source)}',
        bytes,
      );
    } catch (e, stack) {
      AppLog.e('保存本地封面失敗: $e', error: e, stackTrace: stack);
      return null;
    }
  }

  Future<String> _writeCover(
    Book book,
    String fileName,
    List<int> bytes,
  ) async {
    final dir = await AppStoragePaths.bookAssetDir(
      bookStorageKey(book),
      ensureExists: true,
    );
    final file = File(p.join(dir.path, fileName));
    if (await file.exists() && await file.length() == bytes.length) {
      return file.path;
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List?> _readCoverBytes(String source, Book book) async {
    if (source.startsWith('memory://')) {
      return ResourceService().getMemoryResource(source);
    }
    if (source.startsWith('local://')) {
      final file = File(source.replaceFirst('local://', ''));
      if (!await file.exists()) return null;
      return file.readAsBytes();
    }
    if (source.startsWith('file://')) {
      final file = File(Uri.parse(source).toFilePath());
      if (!await file.exists()) return null;
      return file.readAsBytes();
    }
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      // 照這本書的書源抓（標頭、Cookie、封面解密），和畫面上的封面同一份
      // 快取。
      return SourceCoverLoader.load(source, book.origin, book: book);
    }
    final file = File(source);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  String _extensionForSource(String source) {
    final uri = Uri.tryParse(source);
    final rawPath = uri?.path.isNotEmpty == true ? uri!.path : source;
    final ext = p.extension(rawPath).toLowerCase();
    if (const {'.jpg', '.jpeg', '.png', '.webp', '.gif'}.contains(ext)) {
      return ext;
    }
    return '.jpg';
  }
}
