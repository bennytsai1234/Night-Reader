import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/reader_chapter_content.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:share_plus/share_plus.dart';

class BookshelfImportResult {
  final int books;
  final int chapters;
  final int sources;
  final int contents;

  const BookshelfImportResult({
    required this.books,
    required this.chapters,
    required this.sources,
    this.contents = 0,
  });
}

class BookshelfExchangeService {
  final BookDao _bookDao = getIt<BookDao>();
  final ChapterDao _chapterDao = getIt<ChapterDao>();
  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final Dio _dio = getIt<NetworkService>().dio;
  ReaderChapterContentDao? get _contentDao =>
      getIt.isRegistered<ReaderChapterContentDao>()
          ? getIt<ReaderChapterContentDao>()
          : null;

  Future<File> exportBookshelf({
    List<Book>? books,
    String fileName = 'bookshelf-export.night_reader.json',
  }) async {
    final shelfBooks = books ?? await _bookDao.getInBookshelf();
    final chapters = <BookChapter>[];
    final contentDao = _contentDao;
    final sourcesByUrl = <String, BookSource>{};

    for (final book in shelfBooks) {
      chapters.addAll(await _chapterDao.getByBook(book.bookUrl));
      if (book.origin.isNotEmpty && book.origin != 'local') {
        final source = await _sourceDao.getByUrl(book.origin);
        if (source != null) {
          sourcesByUrl[source.bookSourceUrl] = source;
        }
      }
    }

    final payload = {
      'kind': 'night_reader.bookshelf',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'books': shelfBooks.map((e) => e.toJson()).toList(),
      'chapters': chapters.map((e) => e.toJson()).toList(),
      'chapterContents':
          contentDao == null
              ? const <Map<String, dynamic>>[]
              : (await contentDao.getEntriesByBookUrls(
                shelfBooks.map((book) => book.bookUrl),
              )).map((e) => e.toJson()).toList(),
      'sources': sourcesByUrl.values.map((e) => e.toJson()).toList(),
    };

    final file = await AppStoragePaths.shareExportFile(fileName);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return file;
  }

  Future<void> shareBookshelf({List<Book>? books, String? fileName}) async {
    final file = await exportBookshelf(
      books: books,
      fileName: fileName ?? 'bookshelf-export.night_reader.json',
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: '夜讀書架匯出'),
    );
  }

  Future<BookshelfImportResult> importFromFile(File file) async {
    final content = await file.readAsString();
    return importFromText(content);
  }

  Future<BookshelfImportResult> importFromUrl(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final content = response.data;
    if (content == null || content.isEmpty) {
      return const BookshelfImportResult(books: 0, chapters: 0, sources: 0);
    }
    return importFromText(content);
  }

  Future<BookshelfImportResult> importFromText(String text) async {
    final decoded = jsonDecode(text);

    final books = <Book>[];
    final chapters = <BookChapter>[];
    final sources = <BookSource>[];
    final chapterContents = <ReaderChapterContentEntry>[];

    if (decoded is Map<String, dynamic>) {
      if (decoded['books'] is List) {
        books.addAll(_parseBooks(decoded['books'] as List<dynamic>));
      } else if (_looksLikeBook(decoded)) {
        books.add(Book.fromJson(decoded));
      }
      if (decoded['chapters'] is List) {
        chapters.addAll(_parseChapters(decoded['chapters'] as List<dynamic>));
      }
      if (decoded['sources'] is List) {
        sources.addAll(_parseSources(decoded['sources'] as List<dynamic>));
      }
      if (decoded['chapterContents'] is List) {
        chapterContents.addAll(
          _parseChapterContents(decoded['chapterContents'] as List<dynamic>),
        );
      }
    } else if (decoded is List) {
      if (decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
        final first = decoded.first as Map<String, dynamic>;
        if (_looksLikeBook(first)) {
          books.addAll(_parseBooks(decoded));
        } else if (_looksLikeChapter(first)) {
          chapters.addAll(_parseChapters(decoded));
        } else if (_looksLikeSource(first)) {
          sources.addAll(_parseSources(decoded));
        }
      }
    }

    for (final source in sources) {
      await _sourceDao.upsert(source);
    }
    for (final book in books) {
      final normalized = book.copyWith(
        isInBookshelf: true,
        syncTime:
            book.syncTime == 0
                ? DateTime.now().millisecondsSinceEpoch
                : book.syncTime,
      );
      await _bookDao.upsert(normalized);
    }
    if (chapters.isNotEmpty) {
      await _chapterDao.insertChapters(chapters);
    }
    final contentDao = _contentDao;
    if (contentDao != null) {
      for (final content in chapterContents) {
        await contentDao.upsertEntry(content);
      }
    }

    return BookshelfImportResult(
      books: books.length,
      chapters: chapters.length,
      sources: sources.length,
      contents: chapterContents.length,
    );
  }

  List<Book> _parseBooks(List<dynamic> raw) {
    return raw.whereType<Map<String, dynamic>>().map(Book.fromJson).toList();
  }

  List<BookChapter> _parseChapters(List<dynamic> raw) {
    return raw
        .whereType<Map<String, dynamic>>()
        .map((json) => BookChapter.fromJson(json)..content = null)
        .toList();
  }

  List<BookSource> _parseSources(List<dynamic> raw) {
    return raw
        .whereType<Map<String, dynamic>>()
        .map(BookSource.fromJson)
        .toList();
  }

  List<ReaderChapterContentEntry> _parseChapterContents(List<dynamic> raw) {
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ReaderChapterContentEntry.fromJson)
        .where((entry) => entry.contentKey.isNotEmpty)
        .toList();
  }

  bool _looksLikeBook(Map<String, dynamic> json) =>
      json.containsKey('bookUrl') && json.containsKey('name');

  bool _looksLikeChapter(Map<String, dynamic> json) =>
      json.containsKey('bookUrl') &&
      json.containsKey('title') &&
      json.containsKey('index');

  bool _looksLikeSource(Map<String, dynamic> json) =>
      json.containsKey('bookSourceUrl') && json.containsKey('bookSourceName');
}
