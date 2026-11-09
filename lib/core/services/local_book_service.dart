import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/book_type.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/local_book_fingerprint.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/local_book/epub_parser.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

/// 本地書籍匯入結果
class LocalBookImportResult {
  final Book book;
  final List<BookChapter> chapters;

  /// EPUB 的封面圖與副檔名（含點）；TXT 沒有。
  final Uint8List? cover;
  final String? coverExtension;

  const LocalBookImportResult({
    required this.book,
    required this.chapters,
    this.cover,
    this.coverExtension,
  });
}

/// LocalBookService - 本地書籍內容獲取服務
///
/// 章節記檔案裡的位元組區段（`start`／`end`）。TXT 直接讀原檔；EPUB 匯入時
/// 先轉成 UTF-8 純文字存在這本書的資料夾（[epubTextPath]），之後和 TXT 一樣
/// 讀。
class LocalBookService {
  static final LocalBookService _instance = LocalBookService._internal();
  factory LocalBookService() => _instance;
  LocalBookService._internal();

  RandomAccessFile? _txtAccessFile;
  String? _txtAccessFilePath;
  Future<void> _txtReadChain = Future<void>.value();

  /// 本地書原檔在這台手機上的路徑。
  static String filePathOf(Book book) =>
      book.bookUrl.replaceFirst('local://', '');

  /// 把 [path] 的本地書加進書架，傳回書架上的那本；解析不了傳回 null。
  ///
  /// 先算原檔指紋（[fingerprint] 給了就不再算）：書架上已經有同一個檔
  /// （指紋相同，檔名不同也算）就傳回那本，不再加一次。否則複製進本地書
  /// 資料夾、解析、連同章節寫進資料庫。[name]、[author] 給了就用它們（同步
  /// 本地書從雲端下載的照另一台的書名）。
  Future<Book?> addToShelf(
    String path, {
    required BookDao bookDao,
    required ChapterDao chapterDao,
    String? fingerprint,
    String? name,
    String? author,
  }) async {
    final print = fingerprint ?? await localBookFingerprint(path);
    // 這一版以前匯入的書先補上指紋，才認得出是不是同一本。
    await fillLocalBookFingerprints(bookDao);
    final same = await bookDao.getInBookshelfByFingerprint(print);
    if (same.isNotEmpty) {
      await _restoreMissingOriginal(same, path);
      final missing = <Book>[];
      for (final book in same) {
        if (!await File(filePathOf(book)).exists()) missing.add(book);
      }
      if (missing.isEmpty) return same.first;
      return await _moveMissingBooks(
            missing,
            path,
            bookDao: bookDao,
            chapterDao: chapterDao,
          ) ??
          same.first;
    }

    final storedPath = await storeInLibrary(path, bookDao: bookDao);
    final existing = await bookDao.getByUrl('local://$storedPath');
    if (existing != null && existing.isInBookshelf) return existing;
    try {
      final result = await importBook(storedPath);
      if (result == null) {
        await _discardUnusedCopy(storedPath, existing == null);
        return null;
      }
      final book = result.book
        ..fileFingerprint = print
        ..name = name ?? result.book.name
        ..author = author ?? result.book.author;
      if (book.syncTime == 0) {
        book.syncTime = DateTime.now().millisecondsSinceEpoch;
      }
      book.fillChapterTitle(result.chapters);
      final cover = result.cover;
      if (cover != null) {
        await BookCoverStorageService().storeEmbeddedCover(
          book,
          cover,
          extension: result.coverExtension ?? '',
        );
      }
      // 書與章節一起寫：章節寫不進去時書也不留，下面才能放心刪掉複本。
      await bookDao.transaction(() async {
        await bookDao.upsert(book);
        await chapterDao.insertChapters(result.chapters);
      });
      return book;
    } catch (e) {
      AppLog.e('匯入本地書籍失敗: $e', error: e);
      await _discardUnusedCopy(storedPath, existing == null);
      rethrow;
    }
  }

  /// 書架上已有同一個檔的書，但原檔不見了（例如還原備份帶回了書、沒帶回
  /// 原檔）：把這次給的檔放回它原本的位置，書、進度、目錄都不動。
  static Future<void> _restoreMissingOriginal(
    List<Book> books,
    String path,
  ) async {
    for (final book in books) {
      final target = File(filePathOf(book));
      if (await target.exists()) continue;
      try {
        await target.parent.create(recursive: true);
        await File(path).copy(target.path);
      } on FileSystemException catch (error) {
        // 原本的位置在別的手機或別的 App 資料夾，寫不進去。
        AppLog.e('放回本地書原檔失敗: $error', error: error);
      }
    }
  }

  /// 原檔放不回原本的位置（例如還原另一台手機的備份，App 資料夾的路徑
  /// 變了）：把這次拿到的原檔留在本地書資料夾，書改指新路徑。同一個指紋
  /// 有好幾本書時，各留一份原檔、各指自己的路徑，不互相蓋掉。章節、封面與
  /// EPUB 轉好的文字跟著搬；閱讀進度在書這一列，書籤與標註認書名與作者，
  /// 都不用改。
  ///
  /// 檔案與附件都先準備好，再用同一個交易改所有書列；任何一步失敗就清掉
  /// 這次準備的檔案，原本的書與附件不動。
  Future<Book?> _moveMissingBooks(
    List<Book> books,
    String path, {
    required BookDao bookDao,
    required ChapterDao chapterDao,
  }) async {
    final source = await storeInLibrary(path, bookDao: bookDao);
    if (!await File(source).exists()) {
      throw FileSystemException('原檔不見了，無法放回書架', path);
    }
    final sourceCreated = !p.equals(source, path);
    final prepared = <_PreparedMove>[];
    final createdFiles = <String>[];
    final createdDirs = <Directory>[];
    var sourceTaken = false;
    var sourceUsable =
        books.isNotEmpty &&
        await _destinationFree(source, books.first, bookDao, chapterDao);
    try {
      for (final oldBook in books) {
        final useSource = sourceUsable && !sourceTaken;
        final String target;
        if (useSource) {
          target = source;
          sourceTaken = true;
        } else {
          target = await _freeMovePath(oldBook, bookDao, chapterDao);
          await File(source).copy(target);
          createdFiles.add(target);
        }
        final newUrl = 'local://$target';
        final chapters = await chapterDao.getByBook(oldBook.bookUrl);
        var newBook = oldBook.copyWith(bookUrl: newUrl);
        final oldAssets = await AppStoragePaths.bookAssetDir(
          BookCoverStorageService.bookStorageKey(oldBook),
        );
        Directory? newAssets;
        if (await oldAssets.exists()) {
          newAssets = await AppStoragePaths.bookAssetDir(
            BookCoverStorageService.bookStorageKey(newBook),
          );
          createdDirs.add(newAssets);
          await _copyDirectory(oldAssets, newAssets);
          newBook = _repointAssets(oldBook, newBook, oldAssets, newAssets);
        }
        prepared.add(
          _PreparedMove(
            oldBook: oldBook,
            book: newBook,
            chapters: chapters,
            oldAssets: newAssets == null ? null : oldAssets,
          ),
        );
      }

      await bookDao.transaction(() async {
        for (final move in prepared) {
          final newUrl = move.book.bookUrl;
          // 書的身分是網址：先刪舊的一列再寫新的一列，不能只 upsert，不然會
          // 留下原本那一列指著不存在的原檔。
          await bookDao.deleteByUrl(move.oldBook.bookUrl);
          await bookDao.upsert(move.book);
          await chapterDao.deleteByBook(move.oldBook.bookUrl);
          await chapterDao.deleteByBook(newUrl);
          if (move.chapters.isNotEmpty) {
            await chapterDao.insertChapters([
              for (final chapter in move.chapters)
                chapter.copyWith(
                  bookUrl: newUrl,
                  url: chapter.url.startsWith(move.oldBook.bookUrl)
                      ? '$newUrl${chapter.url.substring(move.oldBook.bookUrl.length)}'
                      : '$newUrl#${chapter.index}',
                ),
            ]);
          }
        }
      });
    } catch (_) {
      for (final dir in createdDirs.reversed) {
        await _removeDirectoryQuietly(dir);
      }
      for (final file in createdFiles) {
        await _removeFileQuietly(file);
      }
      if (sourceCreated) await _removeFileQuietly(source);
      rethrow;
    }

    for (final move in prepared) {
      if (move.oldAssets case final dir?) await _removeDirectoryQuietly(dir);
    }
    if (sourceCreated && !sourceTaken) await _removeFileQuietly(source);
    return prepared.isEmpty ? null : prepared.first.book;
  }

  /// [path] 可以當一本書的新家：沒有書列、沒有章節、附件資料夾也沒有人用。
  static Future<bool> _destinationFree(
    String path,
    Book book,
    BookDao bookDao,
    ChapterDao chapterDao,
  ) async {
    final url = 'local://$path';
    if (await bookDao.getByUrl(url) != null) return false;
    if ((await chapterDao.getByBook(url)).isNotEmpty) return false;
    final assets = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(book.copyWith(bookUrl: url)),
    );
    return !await _existsAnything(assets.path);
  }

  /// 同一個指紋的其他書要各自一份原檔：在本地書資料夾找一個沒有書、章節
  /// 與附件佔用的名字。
  static Future<String> _freeMovePath(
    Book book,
    BookDao bookDao,
    ChapterDao chapterDao,
  ) async {
    final dir = await AppStoragePaths.localBooksDir(ensureExists: true);
    final extension = p.extension(filePathOf(book));
    final safe = book.name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .trim();
    final base = safe.isEmpty ? '本地書' : safe;
    for (var copy = 1; ; copy++) {
      final target = p.join(dir.path, _copyName(base, extension, copy));
      if (await _existsAnything(target)) continue;
      if (await _destinationFree(target, book, bookDao, chapterDao)) {
        return target;
      }
    }
  }

  /// 書換了網址時，把封面與 EPUB 轉好的文字複製到新網址的資料夾；原本的
  /// 資料夾等交易成功後才清掉，失敗時回復原狀。
  static Book _repointAssets(
    Book oldBook,
    Book newBook,
    Directory oldDir,
    Directory newDir,
  ) {
    String? moved(String? path) => path != null && p.isWithin(oldDir.path, path)
        ? p.join(newDir.path, p.relative(path, from: oldDir.path))
        : path;
    return newBook.copyWith(
      coverLocalPath: moved(oldBook.coverLocalPath),
      customCoverLocalPath: moved(oldBook.customCoverLocalPath),
    );
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = p.relative(entity.path, from: source.path);
      final destination = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(destination).create(recursive: true);
      } else if (entity is File) {
        await entity.copy(destination);
      }
    }
  }

  static Future<bool> _existsAnything(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  static Future<void> _removeDirectoryQuietly(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (error) {
      AppLog.e('清除本地書搬移準備的資料夾失敗: $error', error: error);
    }
  }

  static Future<void> _removeFileQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      AppLog.e('清除本地書搬移準備的檔案失敗: $error', error: error);
    }
  }

  /// 匯入失敗時，沒有任何書指著的那份複本刪掉，不留在本地書資料夾。
  static Future<void> _discardUnusedCopy(String path, bool unused) async {
    if (!unused) return;
    try {
      await File(path).delete();
    } on FileSystemException catch (e) {
      AppLog.e('刪除匯入失敗的本地書複本失敗: $e', error: e);
    }
  }

  /// 把 [path] 複製進 App 自己的本地書資料夾，回傳複製後的路徑。
  ///
  /// 選檔器與分享給的檔案在暫存區，系統清暫存後書就打不開。同名同內容的
  /// 檔案視為同一本、不再複製；同名不同內容的另取「書名 (2)」。
  Future<String> storeInLibrary(String path, {required BookDao bookDao}) async {
    final dir = await AppStoragePaths.localBooksDir(ensureExists: true);
    if (p.equals(p.dirname(path), dir.path)) return path;

    final source = File(path);
    final name = p.basenameWithoutExtension(path);
    final extension = p.extension(path);
    for (var copy = 1; ; copy++) {
      final target = File(p.join(dir.path, _copyName(name, extension, copy)));
      if (!await target.exists()) {
        if (await _shelfBookAt(target.path, bookDao)) continue;
        await source.copy(target.path);
        return target.path;
      }
      if (await _sameContent(source, target)) return target.path;
    }
  }

  /// 本地書資料夾裡還沒被用掉的檔名：「書名.txt」，有了就「書名 (2).txt」。
  /// 同步本地書從雲端下載的原檔照另一台的書名存在這裡。
  static Future<String> freeLibraryPath(
    String name,
    String extension, {
    required BookDao bookDao,
  }) async {
    final dir = await AppStoragePaths.localBooksDir(ensureExists: true);
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    final base = safe.isEmpty ? '本地書' : safe;
    for (var copy = 1; ; copy++) {
      final target = p.join(dir.path, _copyName(base, extension, copy));
      if (await File(target).exists()) continue;
      if (await _shelfBookAt(target, bookDao)) continue;
      return target;
    }
  }

  /// 書架上有書指著 [path]：原檔不見了（例如還原備份沒帶回原檔）也還是
  /// 那本書的位置，別的檔不能放進來，不然那本書會讀到另一本的內容。
  static Future<bool> _shelfBookAt(String path, BookDao bookDao) async =>
      (await bookDao.getByUrl('local://$path'))?.isInBookshelf ?? false;

  static String _copyName(String name, String extension, int copy) =>
      copy == 1 ? '$name$extension' : '$name ($copy)$extension';

  static Future<bool> _sameContent(File a, File b) async {
    if (await a.length() != await b.length()) return false;
    final left = await a.open();
    final right = await b.open();
    try {
      const chunk = 1 << 16;
      while (true) {
        final x = await left.read(chunk);
        final y = await right.read(chunk);
        if (!listEquals(x, y)) return false;
        if (x.isEmpty) return true;
      }
    } finally {
      await left.close();
      await right.close();
    }
  }

  /// EPUB 轉好的純文字放在這本書的資料夾，移出書架時跟著封面一起刪掉。
  static Future<String> epubTextPath(Book book) async {
    final dir = await AppStoragePaths.bookAssetDir(
      BookCoverStorageService.bookStorageKey(book),
    );
    return p.join(dir.path, 'epub-text.txt');
  }

  /// [book]（EPUB）現在轉好的文字的章節範圍。轉法改過（[EpubParser.textVersion]
  /// 不同）或轉好的文字不見了就先重轉；不是 EPUB、原檔不在或重轉失敗時
  /// 回傳 null。閱讀器開書時拿它對資料庫裡的章節（ADR 0050）。
  Future<List<({String title, int start, int end})>?> currentEpubChapters(
    Book book,
  ) async {
    final path = filePathOf(book);
    if (localBookExtensionFromPath(path) != 'epub') return null;
    final textPath = await epubTextPath(book);
    if (await File(textPath).exists()) {
      final ranges = EpubParser.readChapters(textPath);
      if (ranges != null) return ranges;
    }
    if (!await File(path).exists()) return null;
    try {
      // 讀章時開著的舊文字檔要先關掉，Windows 上才換得掉。
      await closeOpenFile();
      return (await EpubParser.convert(path, textPath)).chapters;
    } on EpubFormatException {
      return null;
    }
  }

  /// [book] 的章節（資料庫裡的）對上 [ranges]：章名與位元組範圍都一樣。
  static bool chaptersMatch(
    List<BookChapter> chapters,
    List<({String title, int start, int end})> ranges,
  ) {
    if (chapters.length != ranges.length) return false;
    for (var i = 0; i < ranges.length; i += 1) {
      if (chapters[i].title != ranges[i].title ||
          chapters[i].start != ranges[i].start ||
          chapters[i].end != ranges[i].end) {
        return false;
      }
    }
    return true;
  }

  /// [ranges] 換成存進資料庫的章節。
  List<BookChapter> chaptersOf(
    Book book,
    List<({String title, int start, int end})> ranges,
  ) => _chapters(book, ranges);

  /// 解析本地書籍並回傳 Book + chapters（不做持久化）
  Future<LocalBookImportResult?> importBook(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;

    final ext = localBookExtensionFromPath(path);
    if (!isSupportedLocalBookExtension(ext)) {
      throw UnsupportedError('不支援的本地格式: $ext');
    }
    return ext == 'epub' ? _importEpub(path) : _importTxt(file);
  }

  Future<LocalBookImportResult> _importTxt(File file) async {
    final result = await compute((File f) async {
      final parser = TxtParser(f);
      return await parser.splitChapters();
    }, file);
    final book = _localBook(file.path)..charset = result.charset;
    return LocalBookImportResult(
      book: book,
      chapters: _chapters(book, [
        for (final (i, chapter) in result.chapters.indexed)
          (
            title: chapter['title'] as String? ?? '第 $i 章',
            start: chapter['start'] as int,
            end: chapter['end'] as int,
          ),
      ]),
    );
  }

  Future<LocalBookImportResult> _importEpub(String path) async {
    final book = _localBook(path)..charset = 'utf-8';
    final info = await EpubParser.convert(path, await epubTextPath(book));
    book
      ..name = info.title ?? book.name
      ..author = info.author ?? book.author;
    return LocalBookImportResult(
      book: book,
      chapters: _chapters(book, info.chapters),
      cover: info.cover,
      coverExtension: info.coverExtension,
    );
  }

  Book _localBook(String path) {
    return Book(
      bookUrl: 'local://$path',
      name: p.basenameWithoutExtension(path),
      author: '本地',
      origin: BookType.localOrigin,
      originName: '本地',
      isInBookshelf: true,
      type: 0,
    );
  }

  List<BookChapter> _chapters(
    Book book,
    List<({String title, int start, int end})> ranges,
  ) {
    return [
      for (final (i, range) in ranges.indexed)
        BookChapter(
          url: '${book.bookUrl}#$i',
          title: range.title,
          bookUrl: book.bookUrl,
          index: i,
          start: range.start,
          end: range.end,
        ),
    ];
  }

  /// 獲取本地書籍章節內容
  Future<String> getContent(Book book, BookChapter chapter) async {
    final path = filePathOf(book);
    if (!await File(path).exists()) return '檔案不存在: $path';

    final ext = localBookExtensionFromPath(path);
    if (!isSupportedLocalBookExtension(ext)) {
      return '不支援的本地格式: $ext，請使用 TXT 或 EPUB 檔案';
    }
    final textPath = ext == 'epub' ? await epubTextPath(book) : path;
    final file = File(textPath);
    if (ext == 'epub' && !await file.exists()) {
      try {
        await EpubParser.convert(path, textPath);
      } on EpubFormatException catch (error) {
        return '讀取本地書籍失敗: ${error.message}';
      }
    }
    // 根據章節索引 (start, end) 指標讀取部分內容 (對標 Android ReadLocalBook.kt)
    if (chapter.start != null && chapter.end != null) {
      final start = chapter.start!;
      final end = chapter.end!;
      final fileLength = await file.length();
      if (start < 0 ||
          end <= start ||
          start >= fileLength ||
          end > fileLength) {
        return '本地書索引無效，請重新匯入';
      }
      return _queueTxtRead(() async {
        final accessFile = await _getTxtAccessFile(file, textPath);
        AppLog.d(
          'LocalBookService: Reading bytes from $start to $end (length: ${end - start})',
        );
        await accessFile.setPosition(start);
        final bytes = await accessFile.read(end - start);
        return EncodingDetect.decodeWithCharset(bytes, book.charset ?? 'utf-8');
      });
    }
    AppLog.d('LocalBookService: Missing offsets for chapter ${chapter.title}');
    return '本地書索引缺失，請重新匯入';
  }

  /// 關掉讀章時留著的檔案；Windows 上開著的檔案刪不掉。
  @visibleForTesting
  Future<void> closeOpenFile() => _queueTxtRead(() async {
    await _txtAccessFile?.close();
    _txtAccessFile = null;
    _txtAccessFilePath = null;
  });

  Future<T> _queueTxtRead<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _txtReadChain = _txtReadChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<RandomAccessFile> _getTxtAccessFile(File file, String path) async {
    if (_txtAccessFile != null && _txtAccessFilePath == path) {
      return _txtAccessFile!;
    }
    if (_txtAccessFile != null) {
      await _txtAccessFile!.close();
      _txtAccessFile = null;
      _txtAccessFilePath = null;
    }
    _txtAccessFile = await file.open(mode: FileMode.read);
    _txtAccessFilePath = path;
    return _txtAccessFile!;
  }
}

/// 搬一本本地書到新路徑時先準備好的內容；交易還沒提交前都還不算數。
class _PreparedMove {
  const _PreparedMove({
    required this.oldBook,
    required this.book,
    required this.chapters,
    this.oldAssets,
  });

  final Book oldBook;
  final Book book;
  final List<BookChapter> chapters;
  final Directory? oldAssets;
}
