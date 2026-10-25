import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/exception/app_exception.dart';
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

  /// 把 [path] 複製進 App 自己的本地書資料夾，回傳複製後的路徑。
  ///
  /// 選檔器與分享給的檔案在暫存區，系統清暫存後書就打不開。同名同內容的
  /// 檔案視為同一本、不再複製；同名不同內容的另取「書名 (2)」。
  Future<String> storeInLibrary(String path) async {
    final dir = await AppStoragePaths.localBooksDir(ensureExists: true);
    if (p.equals(p.dirname(path), dir.path)) return path;

    final source = File(path);
    final name = p.basenameWithoutExtension(path);
    final extension = p.extension(path);
    for (var copy = 1; ; copy++) {
      final fileName = copy == 1
          ? '$name$extension'
          : '$name ($copy)$extension';
      final target = File(p.join(dir.path, fileName));
      if (!await target.exists()) {
        await source.copy(target.path);
        return target.path;
      }
      if (await _sameContent(source, target)) return target.path;
    }
  }

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
      origin: 'local',
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
    final path = book.bookUrl.replaceFirst('local://', '');
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
