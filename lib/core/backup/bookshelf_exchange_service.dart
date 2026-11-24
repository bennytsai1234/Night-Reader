import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/book/reader_chapter_content.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/storage/book_cover_storage_service.dart';
import 'package:share_plus/share_plus.dart';

class BookshelfImportResult {
  final int books;
  final int chapters;
  final int sources;
  final int contents;

  /// 檔裡已經在這台書架上、照這台留著的書（不算進 [books]）。
  final int alreadyOnShelf;

  const BookshelfImportResult({
    required this.books,
    required this.chapters,
    required this.sources,
    this.contents = 0,
    this.alreadyOnShelf = 0,
  });

  /// 給讀者看的一句結果；什麼都沒寫進來、也沒有已在書架上的書時是 null。
  String? get summary {
    final added = [
      if (books > 0) '$books 本書',
      if (chapters > 0) '$chapters 個章節',
      if (sources > 0) '$sources 個書源',
      if (contents > 0) '$contents 份正文快取',
    ];
    final kept = alreadyOnShelf > 0 ? '$alreadyOnShelf 本已經在書架上，照這台的留著' : null;
    if (added.isEmpty) return kept;
    return ['已匯入 ${added.join('、')}', ?kept].join('，');
  }
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
      if (book.origin.isNotEmpty && !book.isLocal) {
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
      'chapterContents': contentDao == null
          ? const <Map<String, dynamic>>[]
          : [
              // 只帶存好的正文、而且是這本書現在用的書源的（同備份）。
              for (final entry in await contentDao.getEntriesByBookUrls(
                shelfBooks.map((book) => book.bookUrl),
              ))
                if (entry.isReady &&
                    shelfBooks.any(
                      (book) =>
                          book.bookUrl == entry.bookUrl &&
                          book.origin == entry.origin,
                    ))
                  entry.toJson(),
            ],
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
      Map<String, dynamic>? first;
      for (final item in decoded) {
        if (item is Map<String, dynamic> &&
            (_looksLikeBook(item) ||
                _looksLikeChapter(item) ||
                _looksLikeSource(item))) {
          first = item;
          break;
        }
      }
      if (first != null) {
        if (_looksLikeBook(first)) {
          books.addAll(
            _parseBooks(
              decoded
                  .whereType<Map<String, dynamic>>()
                  .where(_looksLikeBook)
                  .toList(growable: false),
            ),
          );
        } else if (_looksLikeChapter(first)) {
          chapters.addAll(
            _parseChapters(
              decoded
                  .whereType<Map<String, dynamic>>()
                  .where(_looksLikeChapter)
                  .toList(growable: false),
            ),
          );
        } else if (_looksLikeSource(first)) {
          sources.addAll(
            _parseSources(
              decoded
                  .whereType<Map<String, dynamic>>()
                  .where(_looksLikeSource)
                  .toList(growable: false),
            ),
          );
        }
      }
    }

    // 匯入書架檔是「加入這些書」：這台書架上已經有的書（同一個網址）照這台
    // 的，閱讀進度、分組、封面、目錄與已下載的正文都不拿檔裡的舊資料蓋掉。
    final kept = <String>{
      for (final book in books)
        if ((await _bookDao.getByUrl(book.bookUrl))?.isInBookshelf ?? false)
          book.bookUrl,
    };
    for (final book in books) {
      if (kept.contains(book.bookUrl)) continue;
      final normalized =
          book.copyWith(
            isInBookshelf: true,
            syncTime: book.syncTime == 0
                ? DateTime.now().millisecondsSinceEpoch
                : book.syncTime,
          )..fillChapterTitle([
            for (final chapter in chapters)
              if (chapter.bookUrl == book.bookUrl) chapter,
          ]);
      // 書架檔多半是別台匯出的：那台存好的封面檔這台沒有，改用網址。
      await BookCoverStorageService.dropMissingCoverFiles(normalized);
      await _bookDao.upsert(normalized);
    }
    // 書源在書之後存：存書源時書跟著它的類型（ADR 0053），書已經在才跟得到。
    for (final source in sources) {
      await _sourceDao.upsert(source);
    }
    // 書架上已有的書，目錄只在這台還沒有時寫；其他的書照檔裡寫（書與目錄
    // 一起換成檔裡的，閱讀進度才對得上目錄）。
    final noToc = <String, bool>{};
    final newChapters = <BookChapter>[
      for (final chapter in chapters)
        if (!kept.contains(chapter.bookUrl) ||
            (noToc[chapter.bookUrl] ??= (await _chapterDao.getByBook(
              chapter.bookUrl,
            )).isEmpty))
          chapter,
    ];
    if (newChapters.isNotEmpty) {
      await _chapterDao.insertChapters(newChapters);
    }
    // 正文只寫存好的，而且這台那一章還沒有存好的正文時才寫：舊版匯出的檔
    // 帶著抓失敗的紀錄，不拿它換掉這台已經下載好的。
    var contents = 0;
    final contentDao = _contentDao;
    if (contentDao != null) {
      for (final content in chapterContents) {
        if (!content.isReady) continue;
        if (await contentDao.fillContent(
          contentKey: content.contentKey,
          origin: content.origin,
          bookUrl: content.bookUrl,
          chapterUrl: content.chapterUrl,
          chapterIndex: content.chapterIndex,
          content: content.content ?? '',
          updatedAt: content.updatedAt,
        )) {
          contents++;
        }
      }
    }
    // 匯入的書就是加入書架的書：整本下載（ADR 0008）。
    if (getIt.isRegistered<DownloadDao>()) {
      final downloads = DownloadService();
      for (final book in books) {
        if (book.isLocal) continue;
        unawaited(downloads.keepShelfBookDownloaded(book.bookUrl));
      }
    }

    // 照實際寫進來的算；書架上已有、照這台留著的另外算。
    return BookshelfImportResult(
      books: books.length - kept.length,
      alreadyOnShelf: kept.length,
      chapters: newChapters.length,
      sources: sources.length,
      contents: contents,
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
        .map((json) => BookSource.fromJson(json)..prepareIncoming())
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
