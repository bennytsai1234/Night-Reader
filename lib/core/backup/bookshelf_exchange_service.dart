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
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/storage/book_cover_storage_service.dart';
import 'package:pool/pool.dart';
import 'package:share_plus/share_plus.dart';

class BookshelfImportResult {
  final int books;
  final int chapters;
  final int sources;
  final int contents;

  /// 檔裡已經在這台書架上、照這台留著的書（不算進 [books]）。
  final int alreadyOnShelf;

  /// 只有書名、作者（Legado 匯出的書架）、在啟用的書源裡找不到的書名。
  final List<String> notFound;

  const BookshelfImportResult({
    required this.books,
    required this.chapters,
    required this.sources,
    this.contents = 0,
    this.alreadyOnShelf = 0,
    this.notFound = const [],
  });

  /// 給讀者看的一句結果；什麼都沒寫進來、也沒有已在書架上或找不到的書時是
  /// null。
  String? get summary {
    final added = [
      if (books > 0) '$books 本書',
      if (chapters > 0) '$chapters 個章節',
      if (sources > 0) '$sources 個書源',
      if (contents > 0) '$contents 份正文快取',
    ];
    final parts = [
      if (added.isNotEmpty) '已匯入 ${added.join('、')}',
      if (alreadyOnShelf > 0) '$alreadyOnShelf 本已經在書架上，照這台的留著',
      if (notFound.isNotEmpty) '${notFound.length} 本找不到：${notFound.join('、')}',
    ];
    return parts.isEmpty ? null : parts.join('，');
  }
}

/// 書架的匯出與匯入，格式和 Legado 互通。
///
/// 匯出是一個陣列、一本一筆（同 Legado `exportBookshelf`）：Legado 匯入時
/// 每一筆只讀 `name`、`author`，照書名與作者在它啟用的書源裡找；夜讀這一筆
/// 是整本書的欄位，另外帶著這本的目錄（`chapters`）、存好的正文
/// （`chapterContents`）與它用的書源（`source`），夜讀匯回來不用再找。
///
/// 匯入認得：這個陣列、2026-11 以前的物件格式（`{kind, books, chapters,
/// chapterContents, sources}`）、書籍或章節或書源的陣列，與 Legado 的
/// `[{name, author, intro}]`。後者沒有書的網址，照 Legado
/// `importBookshelfByJson`：書架上已有同名同作者的略過，其他的照書源排序在
/// 啟用的書源裡精確搜尋（書名、作者都一樣），加第一個找到的。
class BookshelfExchangeService {
  BookshelfExchangeService({BookSourceService? sourceService})
    : _givenSourceService = sourceService;

  final BookSourceService? _givenSourceService;
  late final BookSourceService _sourceService =
      _givenSourceService ?? BookSourceService();

  /// 一本書同時問幾個書源（同自動換源）。
  static const int _searchBatch = 6;

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
    final contentDao = _contentDao;
    final payload = <Map<String, dynamic>>[];
    for (final book in shelfBooks) {
      final source = book.origin.isNotEmpty && !book.isLocal
          ? await _sourceDao.getByUrl(book.origin)
          : null;
      payload.add({
        // Legado 照這兩欄找書；書名與作者是書的欄位，一定是字串。
        ...book.toJson(),
        'chapters': [
          for (final chapter in await _chapterDao.getByBook(book.bookUrl))
            chapter.toJson(),
        ],
        // 只帶存好的正文、而且是這本書現在用的書源的（同備份）。
        'chapterContents': [
          if (contentDao != null)
            for (final entry in await contentDao.getEntriesByBookUrls([
              book.bookUrl,
            ]))
              if (entry.isReady && entry.origin == book.origin) entry.toJson(),
        ],
        'source': ?source?.toJson(),
      });
    }

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

  /// 下載 [url] 的書架檔，拿不到內容時是空字串。
  Future<String> fetchText(String url) async {
    final response = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  /// [text] 裡要在書源裡搜尋的書（Legado 的書架，只有書名、作者）有幾本；
  /// 有的話匯入會花一段時間，呼叫端先開進度框。不是書架檔時是 0。
  static int searchCountOf(String text) {
    try {
      return _legadoEntries(jsonDecode(text)).length;
    } on FormatException {
      return 0;
    }
  }

  /// 匯入書架檔（格式見 [BookshelfExchangeService]）。Legado 的書架要一本
  /// 一本在書源裡搜：每找完一本（找到、找不到都算）呼叫 [onSearchProgress]；
  /// [cancelToken] 取消時停在兩本之間，找到的留著。
  Future<BookshelfImportResult> importFromText(
    String text, {
    void Function(int done, int total)? onSearchProgress,
    CancelToken? cancelToken,
  }) async {
    final decoded = jsonDecode(text);

    final books = <Book>[];
    final chapters = <BookChapter>[];
    final sources = <BookSource>[];
    final chapterContents = <ReaderChapterContentEntry>[];
    final legado = _legadoEntries(decoded);

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
          // 夜讀的匯出：每一本帶著自己的目錄、正文與書源。
          for (final item in decoded.whereType<Map<String, dynamic>>()) {
            if (!_looksLikeBook(item)) continue;
            books.add(Book.fromJson(item));
            if (item['chapters'] case final List<dynamic> list) {
              chapters.addAll(_parseChapters(list));
            }
            if (item['chapterContents'] case final List<dynamic> list) {
              chapterContents.addAll(_parseChapterContents(list));
            }
            if (item['source'] case final Map<String, dynamic> source) {
              sources.addAll(_parseSources([source]));
            }
          }
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
          await BookIllustrationStorage.markUnfetchedIfIllustrated(content);
        }
      }
    }
    final found = await _addFromSources(
      legado,
      onProgress: onSearchProgress,
      cancelToken: cancelToken,
    );
    // 匯入的書就是加入書架的書：整本下載（ADR 0008）。
    if (getIt.isRegistered<DownloadDao>()) {
      final downloads = DownloadService();
      for (final book in [...books, ...found.added]) {
        if (book.isLocal) continue;
        unawaited(downloads.keepShelfBookDownloaded(book.bookUrl));
      }
    }

    // 照實際寫進來的算；書架上已有、照這台留著的另外算。
    return BookshelfImportResult(
      books: books.length - kept.length + found.added.length,
      alreadyOnShelf: kept.length + found.alreadyOnShelf,
      chapters: newChapters.length,
      sources: sources.length,
      contents: contents,
      notFound: found.notFound,
    );
  }

  /// Legado 的書架（[_legadoEntries]）一本一本照書名、作者在啟用的書源裡找，
  /// 找到的加進書架；書架上已有同名同作者的略過（同 Legado）。
  Future<({List<Book> added, int alreadyOnShelf, List<String> notFound})>
  _addFromSources(
    List<({String name, String author})> entries, {
    void Function(int done, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final added = <Book>[];
    final notFound = <String>[];
    var alreadyOnShelf = 0;
    if (entries.isEmpty) {
      return (added: added, alreadyOnShelf: 0, notFound: notFound);
    }
    final shelf = {
      for (final book in await _bookDao.getInBookshelf())
        '${book.name}\u0000${book.author}',
    };
    final todo = <({String name, String author})>[];
    for (final entry in entries) {
      if (shelf.add('${entry.name}\u0000${entry.author}')) {
        todo.add(entry);
      } else {
        alreadyOnShelf += 1;
      }
    }
    if (todo.isEmpty) {
      return (added: added, alreadyOnShelf: alreadyOnShelf, notFound: notFound);
    }
    final sources = (await _sourceDao.getEnabled()).where(_searchable).toList()
      ..sort((a, b) {
        final byOrder = a.customOrder.compareTo(b.customOrder);
        if (byOrder != 0) return byOrder;
        return a.bookSourceUrl.compareTo(b.bookSourceUrl);
      });
    onProgress?.call(0, todo.length);
    for (final (i, entry) in todo.indexed) {
      if (cancelToken?.isCancelled ?? false) break;
      final book = await _findOnSources(sources, entry, cancelToken);
      if (cancelToken?.isCancelled ?? false) break;
      if (book == null) {
        notFound.add(entry.name);
      } else {
        final joined = book.copyWith(
          isInBookshelf: true,
          syncTime: DateTime.now().millisecondsSinceEpoch,
        );
        await _bookDao.upsert(joined);
        added.add(joined);
      }
      onProgress?.call(i + 1, todo.length);
    }
    return (added: added, alreadyOnShelf: alreadyOnShelf, notFound: notFound);
  }

  /// 照書源排序找第一個有這本書（書名、作者都一樣）的書源，抓它的詳情。
  /// 一次問 [_searchBatch] 個書源，前一批有就不問後面的；搜不到、抓不到的
  /// 書源跳過。
  Future<Book?> _findOnSources(
    List<BookSource> sources,
    ({String name, String author}) entry,
    CancelToken? cancelToken,
  ) async {
    final pool = Pool(_searchBatch);
    try {
      for (var start = 0; start < sources.length; start += _searchBatch) {
        final batch = sources.skip(start).take(_searchBatch).toList();
        final hits = await Future.wait([
          for (final source in batch)
            pool.withResource(() async {
              if (cancelToken?.isCancelled ?? false) return null;
              try {
                return (await _sourceService.preciseSearch(
                  source,
                  entry.name,
                  entry.author,
                  cancelToken: cancelToken,
                )).firstOrNull;
              } catch (_) {
                return null;
              }
            }),
        ]);
        for (final (i, hit) in hits.indexed) {
          if (hit == null) continue;
          if (cancelToken?.isCancelled ?? false) return null;
          try {
            return await _sourceService.getBookInfo(
              batch[i],
              hit.toBook(),
              cancelToken: cancelToken,
            );
          } catch (_) {
            // 這個書源抓不到詳情，換下一個有這本書的。
          }
        }
      }
      return null;
    } finally {
      await pool.close();
    }
  }

  /// 搜得了的書源：啟用、沒有校驗標的狀態與「AI 修不好」（同自動換源），
  /// 聚合源也算（Legado 搜所有啟用的書源）。
  static bool _searchable(BookSource source) =>
      source.isSearchableFor(source.sourceKind, includeAggregates: true) &&
      !source.groupTags.any(
        (tag) =>
            sourceRuntimeStatusTags.contains(tag) ||
            tag == aiUnfixableSourceGroupTag,
      );

  /// Legado 匯出的書架裡的書：沒有書的網址、有書名的每一筆（書名空的略過，
  /// 同 Legado）。夜讀的書架檔與其他內容是空的。
  static List<({String name, String author})> _legadoEntries(Object? decoded) {
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map<String, dynamic> &&
            _looksLikeLegadoBook(item) &&
            (item['name'] as String).trim().isNotEmpty)
          (
            name: (item['name'] as String).trim(),
            author: item['author'] is String
                ? (item['author'] as String).trim()
                : '',
          ),
    ];
  }

  /// Legado `exportBookshelf` 的一筆：`{name, author, intro}`。
  static bool _looksLikeLegadoBook(Map<String, dynamic> json) =>
      json['name'] is String &&
      !json.containsKey('bookUrl') &&
      !json.containsKey('bookSourceUrl') &&
      !json.containsKey('title');

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
