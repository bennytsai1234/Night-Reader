import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:path/path.dart' as p;

import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/local_book/local_book_formats.dart';
import 'package:reader/core/local_book/txt_parser.dart';
import 'package:reader/core/local_book/umd_parser.dart';
import 'package:reader/core/services/epub_service.dart';
import 'package:reader/core/services/resource_service.dart';
import 'package:fast_gbk/fast_gbk.dart';

/// 本地書籍匯入結果
class LocalBookImportResult {
  final Book book;
  final List<BookChapter> chapters;
  const LocalBookImportResult({required this.book, required this.chapters});
}

/// LocalBookService - 本地書籍內容獲取服務
class LocalBookService {
  static final LocalBookService _instance = LocalBookService._internal();
  factory LocalBookService() => _instance;
  LocalBookService._internal();

  RandomAccessFile? _txtAccessFile;
  String? _txtAccessFilePath;
  Future<void> _txtReadChain = Future<void>.value();
  static const int _maxParsedUmdCache = 2;
  final LinkedHashMap<String, Future<UmdBookData>> _umdParseCache =
      LinkedHashMap<String, Future<UmdBookData>>();

  /// 解析本地書籍並回傳 Book + chapters（不做持久化）
  Future<LocalBookImportResult?> importBook(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;

    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final bookUrl = 'local://$path';

    if (!isSupportedLocalBookExtension(ext)) {
      throw UnsupportedError('不支援的本地格式: $ext');
    }

    if (ext == 'txt') {
      final result = await compute((File f) async {
        final parser = TxtParser(f);
        return await parser.splitChapters();
      }, file);

      final book = Book(
        bookUrl: bookUrl,
        name: p.basenameWithoutExtension(path),
        author: '本地',
        origin: 'local',
        originName: '本地',
        isInBookshelf: true,
        type: 0,
        charset: result.charset,
      );
      final chapters = <BookChapter>[
        for (var i = 0; i < result.chapters.length; i++)
          BookChapter(
            url: '$bookUrl#$i',
            title: result.chapters[i]['title'] ?? '第 $i 章',
            bookUrl: bookUrl,
            index: i,
            start: result.chapters[i]['start'],
            end: result.chapters[i]['end'],
          ),
      ];
      return LocalBookImportResult(book: book, chapters: chapters);
    }

    if (ext == 'epub') {
      final meta = await EpubService().parseMetadata(file);
      if (meta.coverBytes != null) {
        await ResourceService().persistMemoryResource(
          'memory://$bookUrl',
          meta.coverBytes!,
        );
      }
      final book = Book(
        bookUrl: bookUrl,
        name: meta.title,
        author: meta.author,
        origin: 'local',
        originName: '本地',
        isInBookshelf: true,
        type: 1,
        coverUrl: meta.coverBytes != null ? 'memory://$bookUrl' : null,
      );
      final chapters = <BookChapter>[
        for (var i = 0; i < meta.chapters.length; i++)
          BookChapter(
            url: meta.chapters[i]['href'] ?? '',
            title: meta.chapters[i]['title'] ?? '第 $i 章',
            bookUrl: bookUrl,
            index: i,
          ),
      ];
      return LocalBookImportResult(book: book, chapters: chapters);
    }

    if (ext == 'umd') {
      final parsed = await _loadUmdParsed(file);
      if (parsed.coverBytes != null && parsed.coverBytes!.isNotEmpty) {
        await ResourceService().persistMemoryResource(
          'memory://$bookUrl',
          parsed.coverBytes!,
        );
      }
      final book = Book(
        bookUrl: bookUrl,
        name: parsed.title,
        author: parsed.author,
        origin: 'local',
        originName: '本地',
        isInBookshelf: true,
        type: 0,
        coverUrl: parsed.coverBytes != null ? 'memory://$bookUrl' : null,
        totalChapterNum: parsed.chapters.length,
      );
      final chapters = <BookChapter>[
        for (var i = 0; i < parsed.chapters.length; i++)
          BookChapter(
            url: '$bookUrl#$i',
            title: parsed.chapters[i].title,
            bookUrl: bookUrl,
            index: i,
          ),
      ];
      return LocalBookImportResult(book: book, chapters: chapters);
    }

    throw UnsupportedError('目前尚未支援 $ext 本地解析');
  }

  /// 獲取本地書籍章節內容
  Future<String> getContent(Book book, BookChapter chapter) async {
    final path = book.bookUrl.replaceFirst('local://', '');
    final file = File(path);
    if (!await file.exists()) return '檔案不存在: $path';

    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (ext == 'txt') {
      // 根據章節索引 (start, end) 指標讀取 TXT 部分內容 (對標 Android ReadLocalBook.kt)
      if (chapter.start != null && chapter.end != null) {
        return _queueTxtRead(() async {
          final accessFile = await _getTxtAccessFile(file, path);
          final start = chapter.start!;
          final end = chapter.end!;
          AppLog.d(
            'LocalBookService: Reading bytes from $start to $end (length: ${end - start})',
          );
          await accessFile.setPosition(start);
          final bytes = await accessFile.read(end - start);
          return _decodeBytes(bytes, book.charset ?? 'utf-8');
        });
      }
      AppLog.d(
        'LocalBookService: Missing offsets for chapter ${chapter.title}',
      );
      return '本地 TXT 索引缺失，請重新匯入';
    } else if (ext == 'epub') {
      return await EpubService().getChapterContent(file, chapter.url);
    } else if (ext == 'umd') {
      final parsed = await _loadUmdParsed(file);
      if (chapter.index < 0 || chapter.index >= parsed.chapters.length) {
        return '本地 UMD 章節索引缺失，請重新匯入';
      }
      return parsed.chapters[chapter.index].content;
    }
    return '不支援的本地格式: $ext';
  }

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

  String _decodeBytes(List<int> bytes, String charset) {
    try {
      final name = charset.toLowerCase();
      if (name == 'gbk' || name == 'gb2312' || name == 'gb18030') {
        return gbk.decode(bytes);
      }
      return utf8.decode(bytes);
    } catch (e) {
      // 降級處理：如果 UTF-8 失敗嘗試 GBK，反之亦然
      try {
        return gbk.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
  }

  Future<UmdBookData> _loadUmdParsed(File file) async {
    final stat = await file.stat();
    final key =
        '${file.path}|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
    final cached = _umdParseCache.remove(key);
    if (cached != null) {
      _umdParseCache[key] = cached;
      return cached;
    }
    final task = UmdParser(file).parse();
    _umdParseCache[key] = task;
    _trimUmdCache();
    try {
      return await task;
    } catch (_) {
      if (identical(_umdParseCache[key], task)) {
        _umdParseCache.remove(key);
      }
      rethrow;
    }
  }

  void _trimUmdCache() {
    while (_umdParseCache.length > _maxParsedUmdCache) {
      _umdParseCache.remove(_umdParseCache.keys.first);
    }
  }
}
