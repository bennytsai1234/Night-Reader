import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:path/path.dart' as p;

import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/local_book/local_book_formats.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

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

  /// 解析本地書籍並回傳 Book + chapters（不做持久化）
  Future<LocalBookImportResult?> importBook(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;

    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    final bookUrl = 'local://$path';

    if (!isSupportedLocalBookExtension(ext)) {
      throw UnsupportedError('不支援的本地格式: $ext');
    }

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

  /// 獲取本地書籍章節內容
  Future<String> getContent(Book book, BookChapter chapter) async {
    final path = book.bookUrl.replaceFirst('local://', '');
    final file = File(path);
    if (!await file.exists()) return '檔案不存在: $path';

    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!isSupportedLocalBookExtension(ext)) {
      return '不支援的本地格式: $ext，請使用 TXT 檔案';
    }
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
        return EncodingDetect.decodeWithCharset(bytes, book.charset ?? 'utf-8');
      });
    }
    AppLog.d('LocalBookService: Missing offsets for chapter ${chapter.title}');
    return '本地 TXT 索引缺失，請重新匯入';
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
}
