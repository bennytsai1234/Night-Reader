import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/constant/book_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/local_book/local_book_fingerprint.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/engine/book/book_help.dart';
import 'package:night_reader/core/storage/book_cover_storage_service.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/storage/books_in_use.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:path/path.dart' as p;

import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/core/local_book/epub_parser.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/utils/encoding_detect.dart';

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
  ///
  /// 給了 [askUpdate]：書架上已經有同名、同格式、內容不同的本地書（多半是
  /// 連載下載的新版）時先問它；傳回 true 就更新那本（[_updateOriginal]），
  /// 不另加一本。夜讀照原檔指紋認書，分不出新檔是不是舊檔的新版，只能照
  /// 書名猜，所以由讀者決定。
  Future<Book?> addToShelf(
    String path, {
    required BookDao bookDao,
    required ChapterDao chapterDao,
    ReaderChapterContentDao? contentDao,
    String? fingerprint,
    String? name,
    String? author,
    String? charset,
    Future<bool> Function(Book existing)? askUpdate,
  }) async {
    await recoverOnce(bookDao);
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
    if (askUpdate != null) {
      final existing = await _sameNamedShelfBook(path, bookDao);
      // 開著的書不換檔：閱讀器還拿著舊的章節範圍，關掉時也會把舊位置寫回去。
      if (existing != null && BooksInUse.bookUrls.contains(existing.bookUrl)) {
        throw LocalBookContentException('《${existing.name}》正開著，關掉後再加入一次');
      }
      if (existing != null && await askUpdate(existing)) {
        return _updateOriginal(
          existing,
          path,
          print,
          bookDao: bookDao,
          chapterDao: chapterDao,
          contentDao: contentDao,
        );
      }
    }

    final (path: storedPath, :created) = await storeInLibrary(
      path,
      bookDao: bookDao,
    );
    final existing = await bookDao.getByUrl('local://$storedPath');
    if (existing != null && existing.isInBookshelf) return existing;
    try {
      final result = await importBook(
        storedPath,
        pickedName: p.basenameWithoutExtension(path),
        charset: charset,
      );
      if (result == null) {
        await _discardUnusedCopy(storedPath, created);
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
      await _discardUnusedCopy(storedPath, created);
      rethrow;
    }
  }

  /// 書架上和 [path] 同名、同格式的本地書：書名照匯入時的取法（TXT 從檔名
  /// 拆，EPUB 是書裡寫的書名）。不只一本時分不出是哪一本，當成沒有（照舊
  /// 另加一本）。
  Future<Book?> _sameNamedShelfBook(String path, BookDao bookDao) async {
    final extension = localBookExtensionFromPath(path);
    final fileName = p.basenameWithoutExtension(path);
    final name = extension == 'epub'
        ? await EpubParser.readTitle(path) ?? fileName
        : nameAndAuthorFromFileName(fileName).name;
    final same = [
      for (final book in await bookDao.getInBookshelf())
        if (book.isLocal &&
            book.name == name &&
            localBookExtensionFromPath(book.bookUrl) == extension)
          book,
    ];
    return same.length == 1 ? same.single : null;
  }

  /// 測試用：更新原檔做到 [step]（`prepared` 新檔與轉好的資料都準備好、
  /// `swapped` 檔案換好、`committed` 資料庫寫好）時呼叫，丟出
  /// [LocalBookUpdateInterrupted] 模擬 App 在那一步被關掉。
  @visibleForTesting
  static Future<void> Function(String step)? debugUpdateStep;

  /// 換原檔時跟著換的、EPUB 轉好的資料（在這本書的資料夾裡）。
  static const _epubAssets = [
    'epub-text.txt',
    'epub-chapters.json',
    BookIllustrationStorage.folderName,
  ];

  /// 讀者選了更新 [existing]：原檔換成 [path]，照新檔重新分章（同 Legado
  /// 再匯入同一個檔），書名、作者、分組與讀者改過的資訊不動。閱讀進度照
  /// 章名對到新目錄的同一章（序號會因為前面多了章而變），對不到時照比例
  /// 估、從章首讀；書籤與標註本來就照章名對。舊檔讀過的正文清掉。指紋換成
  /// 新檔的：「同步本地書」照它傳新檔、刪雲端的舊檔。
  ///
  /// 新檔（`原檔.new`）與 EPUB 轉好的資料（書的資料夾裡的 `.update/`）先在
  /// 旁邊準備齊全，記下這次換檔（`原檔.update.json`），再一次換上、寫資料庫。
  /// 中途失敗就退回舊檔；App 在中途被關掉的，下次照資料庫裡的指紋收尾或
  /// 退回（[recoverInterruptedUpdates]）。
  Future<Book?> _updateOriginal(
    Book existing,
    String path,
    String fingerprint, {
    required BookDao bookDao,
    required ChapterDao chapterDao,
    ReaderChapterContentDao? contentDao,
  }) async {
    final target = filePathOf(existing);
    final isEpub = localBookExtensionFromPath(target) == 'epub';
    final assets = isEpub ? p.dirname(await epubTextPath(existing)) : null;
    final journal = File(_journalPathOf(target));
    var committed = false;
    final ({List<BookChapter> chapters, String charset}) parsed;
    ({Uint8List bytes, String extension})? cover;
    try {
      await _removeQuietly('$target.new');
      if (assets != null) await _removeQuietly(p.join(assets, _stagingName));
      await File(path).copy('$target.new');
      if (isEpub) {
        final info = await EpubParser.convert(
          '$target.new',
          p.join(assets!, _stagingName, 'epub-text.txt'),
        );
        parsed = (
          chapters: _chapters(existing, info.chapters),
          charset: 'utf-8',
        );
        if (info.cover case final bytes?) {
          cover = (bytes: bytes, extension: info.coverExtension ?? '');
        }
      } else {
        final split = await _splitTxt(
          File('$target.new'),
          charset: await _keptCharset(existing, target),
        );
        parsed = (
          chapters: _chapters(existing, [
            for (final (i, chapter) in split.chapters.indexed)
              (
                title: chapter['title'] as String? ?? '第 $i 章',
                start: chapter['start'] as int,
                end: chapter['end'] as int,
              ),
          ]),
          charset: split.charset,
        );
        for (final (i, chapter) in split.chapters.indexed) {
          parsed.chapters[i].isVolume = chapter['isVolume'] == true;
        }
      }
      if (parsed.chapters.isEmpty) throw LocalBookContentException('分不出章節');
      await journal.writeAsString(
        jsonEncode({
          'bookUrl': existing.bookUrl,
          'fingerprint': fingerprint,
          'assets': ?assets,
        }),
        flush: true,
      );
      await debugUpdateStep?.call('prepared');
      // 讀章時開著的舊檔要先關掉，Windows 上才換得掉。
      await closeOpenFile();
      await _swapIn(target, assets);
      await debugUpdateStep?.call('swapped');

      final current = await bookDao.getByUrl(existing.bookUrl) ?? existing;
      final oldChapters = await chapterDao.getByBook(existing.bookUrl);
      final chapters = parsed.chapters;
      final oldTitle =
          current.durChapterTitle ??
          oldChapters
              .where((c) => c.index == current.chapterIndex)
              .firstOrNull
              ?.title;
      final found = alignChapter(
        oldIndex: current.chapterIndex,
        oldTitle: oldTitle,
        oldTotalCount: oldChapters.length,
        newChapters: chapters,
      );
      final index = found.index.clamp(0, chapters.length - 1);
      // 指紋和目錄在同一個交易裡寫：中途被關掉時，下次照資料庫裡的指紋
      // 判斷這次換檔算不算數（[recoverInterruptedUpdates]）。
      await bookDao.transaction(() async {
        await bookDao.writeFields(
          current,
          BooksCompanion(
            fileFingerprint: Value(fingerprint),
            charset: Value(parsed.charset),
            chapterIndex: Value(index),
            durChapterTitle: Value(chapters[index].title),
            charOffset: Value(found.matched ? current.charOffset : 0),
            visualOffsetPx: const Value(0.0),
            // 錨點綁的是舊檔的正文與章節序號，換了檔不再適用。
            readerAnchorJson: const Value(null),
            totalChapterNum: Value(chapters.length),
          ),
        );
        await chapterDao.replaceByBook(existing.bookUrl, chapters);
        await contentDao?.deleteByBook(existing.origin, existing.bookUrl);
      });
      committed = true;
      await debugUpdateStep?.call('committed');
    } on LocalBookUpdateInterrupted {
      rethrow;
    } catch (_) {
      if (!committed) {
        await closeOpenFile();
        await _rollBack(target, assets);
        await _removeQuietly(journal.path);
        rethrow;
      }
    }
    await _finish(target, assets);
    await _removeQuietly(journal.path);
    if (cover != null) {
      await BookCoverStorageService().storeEmbeddedCover(
        existing,
        cover.bytes,
        extension: cover.extension,
      );
    }
    return bookDao.getByUrl(existing.bookUrl);
  }

  /// 更新 TXT 時用的編碼：讀者手動改過（書上記的和舊檔自動偵測的不同）就
  /// 照讀者改的讀新檔；沒改過時照新檔自動偵測，新版換了編碼也讀得對。
  Future<String?> _keptCharset(Book book, String original) async {
    final stored = book.charset;
    if (stored == null || !await File(original).exists()) return null;
    final detected = await compute(
      (String path) => EncodingDetect.getEncode(File(path).readAsBytesSync()),
      original,
    );
    return detected.toLowerCase() == stored.toLowerCase() ? null : stored;
  }

  /// EPUB 轉好的新資料在書的資料夾裡的暫存處。
  static const _stagingName = '.update';

  static String _journalPathOf(String target) => '$target.update.json';

  /// 換上準備好的新檔與轉好的資料，舊的改名成 `.old` 留著。
  static Future<void> _swapIn(String target, String? assets) async {
    if (await _existsAnything(target)) await _renameAny(target, '$target.old');
    await File('$target.new').rename(target);
    if (assets == null) return;
    for (final name in _epubAssets) {
      final live = p.join(assets, name);
      final staged = p.join(assets, _stagingName, name);
      if (await _existsAnything(live)) await _renameAny(live, '$live.old');
      if (await _existsAnything(staged)) await _renameAny(staged, live);
    }
  }

  /// 這次換檔不算數：放回 `.old` 留著的舊檔與舊資料，丟掉準備好的新的。
  static Future<void> _rollBack(String target, String? assets) async {
    if (await _existsAnything('$target.old')) {
      await _removeQuietly(target);
      await _renameAny('$target.old', target);
    }
    await _removeQuietly('$target.new');
    if (assets == null) return;
    for (final name in _epubAssets) {
      final live = p.join(assets, name);
      if (!await _existsAnything('$live.old')) continue;
      await _removeQuietly(live);
      await _renameAny('$live.old', live);
    }
    await _removeQuietly(p.join(assets, _stagingName));
  }

  /// 這次換檔算數：刪掉留著的舊檔、舊資料與暫存處。
  static Future<void> _finish(String target, String? assets) async {
    await _removeQuietly('$target.old');
    await _removeQuietly('$target.new');
    if (assets == null) return;
    for (final name in _epubAssets) {
      await _removeQuietly(p.join(assets, '$name.old'));
    }
    await _removeQuietly(p.join(assets, _stagingName));
  }

  static Future<void> _renameAny(String from, String to) async {
    if (await FileSystemEntity.isDirectory(from)) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  static Future<void> _removeQuietly(String path) async {
    try {
      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).delete(recursive: true);
      } else if (await File(path).exists()) {
        await File(path).delete();
      }
    } on FileSystemException catch (error) {
      AppLog.w('刪除更新原檔留下的檔案失敗：$error');
    }
  }

  static Future<void>? _recovery;
  static bool _recovered = false;

  /// 這次開 App 第一次讀本地書之前跑一次 [recoverInterruptedUpdates]；還在
  /// 跑時再呼叫都等同一次，跑完之後直接回來。
  static Future<void> recoverOnce(BookDao bookDao) async {
    if (_recovered) return;
    await (_recovery ??= recoverInterruptedUpdates(bookDao));
    _recovered = true;
  }

  /// 測試用：當成這次已經收過（每項測試的資料夾都是新的，沒有沒做完的
  /// 更新）。收尾要讀真的檔案系統，元件測試（`testWidgets`）裡等不到它，
  /// 讀本地書、同步本地書就卡住；前一項測試留下的那一次也不能沿用。
  /// 只記一個旗標、不先做好一個 Future：元件測試在自己的假時鐘裡跑，等
  /// 測試開始前做好的 Future，後續會排到沒人推進的假時鐘，一樣卡住。
  @visibleForTesting
  static void markRecoveredForTesting() => _recovered = true;

  /// 更新原檔（[_updateOriginal]）做到一半 App 被關掉時留下的：照資料庫裡
  /// 這本書的指紋決定，已經是新檔的就收尾（刪掉舊檔），還不是就退回舊檔。
  static Future<void> recoverInterruptedUpdates(BookDao bookDao) async {
    final dir = await AppStoragePaths.localBooksDir();
    if (!await dir.exists()) return;
    final journals = [
      await for (final entity in dir.list())
        if (entity is File && entity.path.endsWith('.update.json')) entity,
    ];
    for (final journal in journals) {
      final target = journal.path.substring(
        0,
        journal.path.length - '.update.json'.length,
      );
      try {
        String? bookUrl;
        String? fingerprint;
        String? assets;
        try {
          final json = jsonDecode(await journal.readAsString());
          if (json is Map) {
            bookUrl = json['bookUrl'] as String?;
            fingerprint = json['fingerprint'] as String?;
            assets = json['assets'] as String?;
          }
        } on FormatException {
          // 紀錄沒寫完：資料庫一定還沒寫，退回。
        }
        final book = bookUrl == null ? null : await bookDao.getByUrl(bookUrl);
        if (fingerprint != null && book?.fileFingerprint == fingerprint) {
          await _finish(target, assets);
        } else {
          await _rollBack(target, assets);
        }
        await _removeQuietly(journal.path);
      } catch (error, stackTrace) {
        AppLog.e('復原沒做完的本地書更新失敗', error: error, stackTrace: stackTrace);
      }
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
    // 只刪這次複製出來的：同名同內容的檔已經在本地書資料夾時直接用那份，
    // 它可能是書架上另一本書的原檔。
    final (path: source, created: sourceCreated) = await storeInLibrary(
      path,
      bookDao: bookDao,
    );
    if (!await File(source).exists()) {
      throw FileSystemException('原檔不見了，無法放回書架', path);
    }
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
  static Future<void> _discardUnusedCopy(String path, bool created) async {
    if (!created) return;
    try {
      await File(path).delete();
    } on FileSystemException catch (e) {
      AppLog.e('刪除匯入失敗的本地書複本失敗: $e', error: e);
    }
  }

  /// 把 [path] 複製進 App 自己的本地書資料夾，回傳複製後的路徑，以及是不是
  /// 這次才複製出來的（[created]；失敗時只能刪這種）。
  ///
  /// 選檔器與分享給的檔案在暫存區，系統清暫存後書就打不開。同名同內容的
  /// 檔案視為同一本、不再複製；同名不同內容的另取「書名 (2)」。
  Future<({String path, bool created})> storeInLibrary(
    String path, {
    required BookDao bookDao,
  }) async {
    final dir = await AppStoragePaths.localBooksDir(ensureExists: true);
    if (p.equals(p.dirname(path), dir.path)) {
      return (path: path, created: false);
    }

    final source = File(path);
    final name = p.basenameWithoutExtension(path);
    final extension = p.extension(path);
    for (var copy = 1; ; copy++) {
      final target = File(p.join(dir.path, _copyName(name, extension, copy)));
      if (!await target.exists()) {
        if (await _shelfBookAt(target.path, bookDao)) continue;
        await source.copy(target.path);
        return (path: target.path, created: true);
      }
      if (await _sameContent(source, target)) {
        return (path: target.path, created: false);
      }
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
    await _recoverBeforeReading();
    final path = filePathOf(book);
    if (localBookExtensionFromPath(path) != 'epub') return null;
    final textPath = await epubTextPath(book);
    if (await File(textPath).exists()) {
      // 讀檔與解析整份範圍在背景做，開書時不佔主執行緒。
      final ranges = await Isolate.run(() => EpubParser.readChapters(textPath));
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

  /// 解析本地書籍並回傳 Book + chapters（不做持久化）。書名與作者從
  /// [pickedName]（使用者選的檔名，不含副檔名；沒給時用 [path] 的）拆，見
  /// [_localBook]。[charset] 是另一台同步來的編碼（只有 TXT 用得到），沒給時
  /// 照偵測。
  Future<LocalBookImportResult?> importBook(
    String path, {
    String? pickedName,
    String? charset,
  }) async {
    final file = File(path);
    if (!await file.exists()) return null;

    final ext = localBookExtensionFromPath(path);
    if (!isSupportedLocalBookExtension(ext)) {
      throw UnsupportedError('不支援的本地格式: $ext');
    }
    return ext == 'epub'
        ? _importEpub(path, pickedName)
        : _importTxt(file, pickedName, charset);
  }

  Future<LocalBookImportResult> _importTxt(
    File file,
    String? pickedName,
    String? charset,
  ) async {
    final result = await _splitTxt(file, charset: charset);
    final book = _localBook(file.path, pickedName)
      ..charset = result.charset
      ..totalChapterNum = result.chapters.length;
    final chapters = _chapters(book, [
      for (final (i, chapter) in result.chapters.indexed)
        (
          title: chapter['title'] as String? ?? '第 $i 章',
          start: chapter['start'] as int,
          end: chapter['end'] as int,
        ),
    ]);
    for (final (i, chapter) in result.chapters.indexed) {
      chapters[i].isVolume = chapter['isVolume'] == true;
    }
    return LocalBookImportResult(book: book, chapters: chapters);
  }

  /// 在背景 isolate 解碼 [file] 並分章；[charset] 是讀者手動指定、或另一台
  /// 同步來的編碼，沒給時照偵測。給了就照它解，只寫 UTF-16 時先照檔案 BOM
  /// 換成大端或小端（章節切片沒有 BOM）。
  Future<({List<Map<String, dynamic>> chapters, String charset})> _splitTxt(
    File file, {
    String? charset,
  }) {
    return compute((({File file, String? charset}) args) async {
      if (args.charset == null) {
        return await TxtParser(args.file).splitChapters();
      }
      final bytes = await args.file.readAsBytes();
      return TxtParser.splitBytes(
        bytes,
        charset: EncodingDetect.resolveCharset(bytes, args.charset!),
      );
    }, (file: file, charset: charset));
  }

  /// 讀者在「更多」手動把這本 TXT 的編碼換成 [charset]：照新編碼重新解碼、
  /// 重新分章，目錄整份換掉。閱讀進度、書籤與標註照原本在檔案裡的位元組位置
  /// 對到新的目錄與章內位置，留在同一章；正文換了，錨點（閱讀位置綁定的
  /// 舊原文）不再適用，一起清掉。
  ///
  /// 原檔不存在、不是 TXT、書不在資料庫裡或分不出章時回傳 null，資料庫與
  /// 原檔都不動。解不開時往外丟錯，呼叫端提示。
  Future<Book?> changeCharset(
    Book book,
    String charset, {
    required BookDao bookDao,
    required ChapterDao chapterDao,
    BookmarkDao? bookmarkDao,
    HighlightDao? highlightDao,
    ReaderChapterContentDao? contentDao,
  }) async {
    final path = filePathOf(book);
    if (localBookExtensionFromPath(path) != 'txt') return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final current = await bookDao.getByUrl(book.bookUrl);
    if (current == null) return null;

    final bytes = await file.readAsBytes();
    final charsetName = EncodingDetect.resolveCharset(bytes, charset);
    final parsed = await _splitTxt(file, charset: charsetName);
    if (parsed.chapters.isEmpty) return null;

    final chapters = _chapters(current, [
      for (final (i, chapter) in parsed.chapters.indexed)
        (
          title: chapter['title'] as String? ?? '第 $i 章',
          start: chapter['start'] as int,
          end: chapter['end'] as int,
        ),
    ]);
    for (final (i, chapter) in parsed.chapters.indexed) {
      chapters[i].isVolume = chapter['isVolume'] == true;
    }

    final oldChapters = await chapterDao.getByBook(current.bookUrl);
    final oldCharset = current.charset ?? EncodingDetect.getEncode(bytes);
    final oldLengths = <int, int>{};
    final oldBookmarks =
        await bookmarkDao?.watchByBook(current.name, current.author).first ??
        const <Bookmark>[];
    final oldHighlights =
        await highlightDao?.watchByBook(current.name, current.author).first ??
        const <Highlight>[];

    ({int index, int charOffset}) mapPosition(int oldIndex, int oldOffset) {
      if (oldChapters.isEmpty) {
        return (index: oldIndex.clamp(0, chapters.length - 1), charOffset: 0);
      }
      return _positionAfterDecode(
        bytes: bytes,
        oldCharset: oldCharset,
        newCharset: charsetName,
        oldChapters: oldChapters,
        newChapters: chapters,
        oldIndex: oldIndex,
        oldOffset: oldOffset,
        oldLengths: oldLengths,
      );
    }

    final progress = mapPosition(current.chapterIndex, current.charOffset);
    // 書籤與標註記的是顯示的章名（可能套過繁簡轉換與標題規則），用照章名
    // 找章的同一套對回舊目錄；對不到的（別的書留下的）不動。
    final movedBookmarks = <Bookmark>[];
    for (final item in oldBookmarks) {
      final found = alignChapter(
        oldIndex: item.chapterIndex,
        oldTitle: item.chapterTitle,
        oldTotalCount: 0,
        newChapters: oldChapters,
      );
      if (!found.matched) continue;
      final mapped = mapPosition(found.index, item.charOffset);
      movedBookmarks.add(
        Bookmark(
          id: item.id,
          bookName: item.bookName,
          bookAuthor: item.bookAuthor,
          chapterIndex: mapped.index,
          chapterTitle: chapters[mapped.index].title,
          charOffset: mapped.charOffset,
          excerpt: item.excerpt,
        ),
      );
    }
    final movedHighlights = <Highlight>[];
    for (final item in oldHighlights) {
      final found = alignChapter(
        oldIndex: item.chapterIndex,
        oldTitle: item.chapterTitle,
        oldTotalCount: 0,
        newChapters: oldChapters,
      );
      if (!found.matched) continue;
      final mapped = mapPosition(found.index, item.charOffset);
      movedHighlights.add(
        Highlight(
          id: item.id,
          bookName: item.bookName,
          bookAuthor: item.bookAuthor,
          chapterIndex: mapped.index,
          chapterTitle: chapters[mapped.index].title,
          charOffset: mapped.charOffset,
          quote: item.quote,
          color: item.color,
          style: item.style,
          note: item.note,
        ),
      );
    }

    await bookDao.transaction(() async {
      await bookDao.writeFields(
        current,
        BooksCompanion(
          charset: Value(charsetName),
          chapterIndex: Value(progress.index),
          durChapterTitle: Value(chapters[progress.index].title),
          charOffset: Value(progress.charOffset),
          visualOffsetPx: const Value(0.0),
          readerAnchorJson: const Value(null),
          durChapterTime: Value(DateTime.now().millisecondsSinceEpoch),
          totalChapterNum: Value(chapters.length),
        ),
      );
      await chapterDao.replaceByBook(current.bookUrl, chapters);
      // 章節網址是「書網址#序號」，換目錄後還是同一組鍵：舊編碼讀過的正文
      // 要一起清掉，不然閱讀器、匯出與備份都會拿到舊的亂碼。
      await contentDao?.deleteByBook(current.origin, current.bookUrl);
      if (movedBookmarks.isNotEmpty) {
        await bookmarkDao!.upsertAll(movedBookmarks);
      }
      if (movedHighlights.isNotEmpty) {
        await highlightDao!.upsertAll(movedHighlights);
      }
    });
    return bookDao.getByUrl(current.bookUrl);
  }

  /// 舊目錄第 [oldIndex] 章第 [oldOffset] 個字，換了編碼之後在新目錄的哪一章、
  /// 第幾個字。
  ///
  /// 兩個目錄的章節範圍都是同一個原檔的位元組位移，不隨編碼改變：先照舊章
  /// 的長度算出這個字在章內的比例，換成檔案裡的位元組位置，找新目錄裡蓋住
  /// 這個位置的那一章；再照這個位元組位置在**新章**裡的比例換成新章的章內
  /// 字數（新舊章的起訖不一樣，舊章的比例不能直接套）。編碼錯了時新舊章名
  /// 不一定一樣，所以不照章名對。
  static ({int index, int charOffset}) _positionAfterDecode({
    required Uint8List bytes,
    required String oldCharset,
    required String newCharset,
    required List<BookChapter> oldChapters,
    required List<BookChapter> newChapters,
    required int oldIndex,
    required int oldOffset,
    required Map<int, int> oldLengths,
  }) {
    if (newChapters.isEmpty) return (index: 0, charOffset: 0);
    final safeOldIndex = oldIndex.clamp(0, oldChapters.length - 1);
    final oldChapter = oldChapters[safeOldIndex];
    final oldStart = oldChapter.start;
    final oldEnd = oldChapter.end;
    if (oldStart == null || oldEnd == null || oldEnd <= oldStart) {
      return (index: oldIndex.clamp(0, newChapters.length - 1), charOffset: 0);
    }
    final oldLength = oldLengths.putIfAbsent(
      safeOldIndex,
      () => _chapterCharLength(bytes, oldChapter, oldCharset),
    );
    final fraction = oldLength <= 0
        ? 0.0
        : (oldOffset / oldLength).clamp(0.0, 1.0);
    final byte = oldStart + (fraction * (oldEnd - oldStart)).floor();

    var newIndex = 0;
    for (var i = 0; i < newChapters.length; i += 1) {
      final start = newChapters[i].start;
      if (start == null || start > byte) break;
      newIndex = i;
    }
    final newChapter = newChapters[newIndex];
    final newStart = newChapter.start;
    final newEnd = newChapter.end;
    final newFraction = newStart == null || newEnd == null || newEnd <= newStart
        ? 0.0
        : ((byte - newStart) / (newEnd - newStart)).clamp(0.0, 1.0);
    final newLength = _chapterCharLength(bytes, newChapter, newCharset);
    final newOffset = newLength <= 0
        ? 0
        : (newFraction * newLength).round().clamp(0, newLength - 1);
    return (index: newIndex, charOffset: newOffset);
  }

  /// [chapter] 的位元組範圍照 [charset] 解出來有幾個字；範圍不完整時是 0。
  static int _chapterCharLength(
    Uint8List bytes,
    BookChapter chapter,
    String charset,
  ) {
    final start = chapter.start;
    final end = chapter.end;
    if (start == null ||
        end == null ||
        start < 0 ||
        end > bytes.length ||
        end <= start) {
      return 0;
    }
    return EncodingDetect.decodeWithCharset(
      bytes.sublist(start, end),
      charset,
    ).length;
  }

  Future<LocalBookImportResult> _importEpub(
    String path,
    String? pickedName,
  ) async {
    final book = _localBook(path, pickedName)..charset = 'utf-8';
    final info = await EpubParser.convert(path, await epubTextPath(book));
    // 書名照 Legado：書裡沒寫時用檔名，不拆。
    book
      ..name = info.title ?? p.basenameWithoutExtension(path)
      ..author = info.author ?? book.author;
    return LocalBookImportResult(
      book: book,
      chapters: _chapters(book, info.chapters),
      cover: info.cover,
      coverExtension: info.coverExtension,
    );
  }

  /// 書名與作者照 [nameAndAuthorFromFileName] 從使用者選的檔名
  /// [pickedName] 拆。存進本地書資料夾時同名的檔另取了「名字 (2)」
  /// （[storeInLibrary]）：拆的是原本的檔名，「 (2)」接在書名後面，同名的
  /// 兩本書才分得開（書籤與標註照書名加作者認書）。
  Book _localBook(String path, String? pickedName) {
    final stored = p.basenameWithoutExtension(path);
    final picked = pickedName ?? stored;
    final copySuffix = stored != picked && stored.startsWith(picked)
        ? stored.substring(picked.length)
        : '';
    final (:name, :author) = nameAndAuthorFromFileName(picked);
    return Book(
      bookUrl: 'local://$path',
      name: '$name$copySuffix',
      author: author.isEmpty ? '本地' : author,
      origin: BookType.localOrigin,
      originName: '本地',
      isInBookshelf: true,
      type: 0,
    );
  }

  static final _nameAuthorPatterns = [
    RegExp(r'(.*?)《([^《》]+)》.*?作者：(.*)'),
    RegExp(r'(.*?)《([^《》]+)》(.*)'),
    RegExp(r'(^)(.+) 作者：(.+)$'),
    RegExp(r'(^)(.+) by (.+)$'),
  ];

  /// 從檔名（不含副檔名）拆出書名與作者，照 Legado
  /// `LocalBook.analyzeNameAuthor`：「《書名》作者：某某」「書名 作者：某某」
  /// 「書名 by 某某」；都不合時書名去掉「作者…」這類字樣。拆不出作者時
  /// 作者是空字串。
  static ({String name, String author}) nameAndAuthorFromFileName(
    String fileName,
  ) {
    for (final pattern in _nameAuthorPatterns) {
      final match = pattern.firstMatch(fileName);
      if (match == null) continue;
      return (
        name: match.group(2)!,
        author: BookHelp.formatBookAuthor(
          '${match.group(1) ?? ''}${match.group(3) ?? ''}',
        ),
      );
    }
    final name = BookHelp.formatBookName(fileName);
    final author = BookHelp.formatBookAuthor(fileName.replaceAll(name, ''));
    return (name: name, author: author.length == fileName.length ? '' : author);
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

  /// 讀本地書之前，先把上次 App 被關掉時沒做完的原檔更新收掉
  /// （[recoverOnce]）。
  static Future<void> _recoverBeforeReading() async {
    if (getIt.isRegistered<BookDao>()) await recoverOnce(getIt<BookDao>());
  }

  /// 獲取本地書籍章節內容
  Future<String> getContent(Book book, BookChapter chapter) async {
    await _recoverBeforeReading();
    final path = filePathOf(book);
    if (!await File(path).exists()) {
      throw LocalBookContentException('檔案不存在: $path');
    }

    final ext = localBookExtensionFromPath(path);
    if (!isSupportedLocalBookExtension(ext)) {
      throw LocalBookContentException('不支援的本地格式: $ext，請使用 TXT 或 EPUB 檔案');
    }
    final textPath = ext == 'epub' ? await epubTextPath(book) : path;
    final file = File(textPath);
    if (ext == 'epub' && !await file.exists()) {
      try {
        await EpubParser.convert(path, textPath);
      } on EpubFormatException catch (error) {
        throw LocalBookContentException('讀取本地書籍失敗: ${error.message}');
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
        throw LocalBookContentException('本地書索引無效，請重新匯入');
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
    throw LocalBookContentException('本地書索引缺失，請重新匯入');
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

/// 測試用：模擬更新原檔途中 App 被關掉（[LocalBookService.debugUpdateStep]），
/// 丟出時什麼都不收拾。
@visibleForTesting
class LocalBookUpdateInterrupted implements Exception {}

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
