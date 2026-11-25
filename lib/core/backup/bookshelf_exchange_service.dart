import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

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

  /// 實際寫進來的書源；這台已有同網址且不比檔案裡的舊時不算。
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
/// 每一筆只讀 `name`、`author`，照書名與作者在它啟用的書源裡找。本地書照
/// Legado 只有書名、作者、簡介；網路書是可以分享的書的欄位
/// （[_sharedBookFields]，不帶本機的封面檔與書、章節的變數），另外帶著這本的
/// 目錄（`chapters`）、存好的正文（`chapterContents`）與它用的書源
/// （`source`，同一個書源只跟著第一本），夜讀匯回來不用再找。
///
/// 匯入認得：這個陣列、2026-11 以前的物件格式（`{kind, books, chapters,
/// chapterContents, sources}`）、一本書的物件、章節的陣列，與 Legado 的
/// `[{name, author, intro}]`。陣列的每一筆都要是書架的一筆或都是章節
/// （[BookshelfFile.fromDecoded]），不然整份不是書架檔、什麼都不匯入：替換
/// 規則、書源與其他 JSON 不會被當成書架。Legado 的書架沒有書的網址，照 Legado
/// `importBookshelfByJson`：書架上已有同名同作者的略過，其他的照書源排序在
/// 啟用的書源裡精確搜尋（書名、作者都一樣），加第一個找到的。檔案在背景
/// isolate 解析一次（[parse]），匯出也在那裡編碼、寫檔。
class BookshelfExchangeService {
  BookshelfExchangeService({BookSourceService? sourceService})
    : _givenSourceService = sourceService;

  final BookSourceService? _givenSourceService;
  late final BookSourceService _sourceService =
      _givenSourceService ?? BookSourceService();

  /// 一本書同時問幾個書源（同自動換源）。
  static const int _searchBatch = 6;

  /// 網路書匯出的欄位：書架上看得到的與閱讀進度。不帶只屬於這台的：本機
  /// 封面檔（`coverLocalPath`、`customCoverLocalPath`）、書的變數
  /// （`variable`）與本地書原檔指紋；從相簿選的封面網址另外濾掉
  /// （[_sharedCoverUrl]）。
  static const List<String> _sharedBookFields = [
    'bookUrl',
    'tocUrl',
    'origin',
    'originName',
    'name',
    'author',
    'kind',
    'customTag',
    'coverUrl',
    'intro',
    'customIntro',
    'charset',
    'type',
    'group',
    'latestChapterTitle',
    'latestChapterTime',
    'lastCheckTime',
    'lastCheckCount',
    'totalChapterNum',
    'durChapterTitle',
    'chapterIndex',
    'charOffset',
    'visualOffsetPx',
    'readerAnchorJson',
    'durChapterTime',
    'progressTime',
    'wordCount',
    'canUpdate',
    'order',
    'originOrder',
    'readConfig',
    'syncTime',
    'isInBookshelf',
  ];

  /// 章節匯出的欄位：不帶章節的變數（`variable`）與正文（正文另外放在
  /// `chapterContents`）。
  static const List<String> _sharedChapterFields = [
    'url',
    'title',
    'isVolume',
    'baseUrl',
    'bookUrl',
    'index',
    'isVip',
    'isPay',
    'resourceUrl',
    'tag',
    'wordCount',
    'start',
    'end',
    'startFragmentId',
    'endFragmentId',
  ];

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
    final exportedSources = <String>{};
    for (final book in shelfBooks) {
      if (book.isLocal) {
        // 同 Legado：本地書只有書名、作者與顯示的簡介，原檔在這台。
        final intro = book.getDisplayIntro();
        payload.add({
          'name': book.name,
          'author': book.author,
          'intro': ?intro,
        });
        continue;
      }
      final source = book.origin.isNotEmpty && exportedSources.add(book.origin)
          ? await _sourceDao.getByUrl(book.origin)
          : null;
      payload.add({
        // Legado 照 name、author 找書；書名與作者是書的欄位，一定是字串。
        ..._pick(book.toJson(), _sharedBookFields),
        'customCoverUrl': _sharedCoverUrl(book.customCoverUrl),
        'chapters': [
          for (final chapter in await _chapterDao.getByBook(book.bookUrl))
            _pick(chapter.toJson(), _sharedChapterFields),
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
    await _writeJson(file.path, payload);
    return file;
  }

  static Map<String, dynamic> _pick(
    Map<String, dynamic> json,
    List<String> keys,
  ) => {for (final key in keys) key: json[key]};

  /// 從相簿選的封面網址是這台的檔（`file://`，見 `Book.getDisplayCover`），
  /// 不帶出去。
  static String? _sharedCoverUrl(String? url) =>
      url == null || url.startsWith('file://') || url.startsWith('/')
      ? null
      : url;

  /// 在背景 isolate 編碼、寫檔（只帶路徑與內容過去，不帶這個物件的 DAO）。
  static Future<void> _writeJson(
    String path,
    List<Map<String, dynamic>> payload,
  ) => Isolate.run(
    () => File(path)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload)),
  );

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

  /// 在背景 isolate 解析書架檔 [text]（只帶字串過去，不帶這個物件的
  /// DAO）；不是書架檔時是 null。
  static Future<BookshelfFile?> parse(String text) =>
      Isolate.run(() => BookshelfFile.parse(text));

  /// 解析（[parse]）並匯入書架檔 [text]，見 [importFile]。
  Future<BookshelfImportResult> importFromText(
    String text, {
    void Function(int done, int total)? onSearchProgress,
    CancelToken? cancelToken,
  }) async => importFile(
    await parse(text),
    onSearchProgress: onSearchProgress,
    cancelToken: cancelToken,
  );

  /// 匯入解析好的書架檔（格式見 [BookshelfExchangeService]）；不是書架檔
  /// （[file] 是 null）時什麼都不寫，結果的 [BookshelfImportResult.summary]
  /// 是 null。Legado 的書架要
  /// 一本一本在書源裡搜：開始找之前以（0, 實際要找的本數）呼叫一次
  /// [onSearchProgress]（書架上已有的不算），之後每找完一本（找到、找不到
  /// 都算）呼叫一次；沒有要找的就不呼叫。[cancelToken] 取消時停在兩本之間，
  /// 找到的留著。
  Future<BookshelfImportResult> importFile(
    BookshelfFile? file, {
    void Function(int done, int total)? onSearchProgress,
    CancelToken? cancelToken,
  }) async {
    if (file == null) {
      return const BookshelfImportResult(books: 0, chapters: 0, sources: 0);
    }
    final books = file.books;
    final chapters = file.chapters;
    final sources = file.sources;

    // 匯入書架檔是「加入這些書」：這台書架上已經有的書（同一個網址）照這台
    // 的，閱讀進度、分組、封面、目錄與已下載的正文都不拿檔裡的舊資料蓋掉。
    final kept = <String>{
      for (final book in books)
        if ((await _bookDao.getByUrl(book.bookUrl))?.isInBookshelf ?? false)
          book.bookUrl,
    };
    for (final book in books) {
      if (kept.contains(book.bookUrl)) continue;
      final normalized = book.copyWith(
        isInBookshelf: true,
        syncTime: book.syncTime == 0
            ? DateTime.now().millisecondsSinceEpoch
            : book.syncTime,
      )..fillChapterTitle(file.chaptersByBook[book.bookUrl] ?? const []);
      // 書架檔多半是別台匯出的：那台存好的封面檔這台沒有，改用網址。
      await BookCoverStorageService.dropMissingCoverFiles(normalized);
      await _bookDao.upsert(normalized);
    }
    // 書源在書之後存：存書源時書跟著它的類型（ADR 0053），書已經在才跟得到。
    // 這台已經有同一個網址的書源時，只有檔案裡的比較新才換（同書源匯入預覽
    // 比 lastUpdateTime）；較舊或一樣的不動，新加的書照這台的類型。
    var writtenSources = 0;
    for (final source in sources) {
      final existing = await _sourceDao.getByUrl(source.bookSourceUrl);
      if (existing == null || source.isNewerThan(existing)) {
        await _sourceDao.upsert(source);
        writtenSources += 1;
      } else {
        await _bookDao.followSourceKinds(
          BookSourceDao.kindsToFollow([existing]),
        );
      }
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
      for (final content in file.contents) {
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
          // 書架檔可能是別人做的：插圖網址的主機和書源不同時不帶登入資料
          // （ADR 0086）。
          await BookIllustrationStorage.markUnfetchedIfIllustrated(
            content,
            fromSource: false,
          );
        }
      }
    }
    final found = await _addFromSources(
      file.legado,
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
      sources: writtenSources,
      contents: contents,
      notFound: found.notFound,
    );
  }

  /// Legado 的書架（[BookshelfFile.legado]）一本一本照書名、作者在啟用的書源裡找，
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
}

/// 解析好的書架檔（[BookshelfExchangeService.parse]）。書架匯入與外部匯入
/// 判斷類型（`detectImportContent`）都用 [fromDecoded] 判斷是不是書架檔。
class BookshelfFile {
  BookshelfFile({
    required this.books,
    required this.chapters,
    required this.sources,
    required this.contents,
    required this.legado,
  }) : chaptersByBook = _groupByBook(chapters);

  final List<Book> books;
  final List<BookChapter> chapters;

  /// 不重複的書源（同一個書源網址只留第一份）：舊版匯出的檔每本書都帶一份。
  final List<BookSource> sources;
  final List<ReaderChapterContentEntry> contents;

  /// Legado 匯出的書架裡要在書源裡找的書（書名空的略過，同 Legado）。
  final List<({String name, String author})> legado;

  final Map<String, List<BookChapter>> chaptersByBook;

  static Map<String, List<BookChapter>> _groupByBook(
    List<BookChapter> chapters,
  ) {
    final byBook = <String, List<BookChapter>>{};
    for (final chapter in chapters) {
      (byBook[chapter.bookUrl] ??= []).add(chapter);
    }
    return byBook;
  }

  /// 解析 [text]；不是 JSON 或不是書架檔時是 null。在呼叫端的 isolate 跑，
  /// 主 isolate 用 [BookshelfExchangeService.parse]。
  static BookshelfFile? parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    return fromDecoded(decoded);
  }

  /// 已經解開的 JSON [decoded] 是書架檔時解析它，不是時是 null（規則見
  /// [BookshelfExchangeService]）。
  static BookshelfFile? fromDecoded(Object? decoded) {
    final books = <Book>[];
    final chapters = <BookChapter>[];
    final sources = <String, BookSource>{};
    final contents = <ReaderChapterContentEntry>[];
    final legado = <({String name, String author})>[];

    void addSource(Object? json) {
      if (json is! Map<String, dynamic> || !_looksLikeSource(json)) return;
      final source = BookSource.fromJson(json)..prepareIncoming();
      sources.putIfAbsent(source.bookSourceUrl, () => source);
    }

    void addChapters(Object? list) {
      if (list is! List) return;
      for (final json in list.whereType<Map<String, dynamic>>()) {
        chapters.add(BookChapter.fromJson(json)..content = null);
      }
    }

    void addContents(Object? list) {
      if (list is! List) return;
      for (final json in list.whereType<Map<String, dynamic>>()) {
        final entry = ReaderChapterContentEntry.fromJson(json);
        if (entry.contentKey.isNotEmpty) contents.add(entry);
      }
    }

    if (decoded is Map<String, dynamic>) {
      if (decoded['books'] case final List<dynamic> list) {
        // 2026-11 以前的物件格式：每一本都要是書。
        final rows = list.whereType<Map<String, dynamic>>().toList();
        if (rows.length != list.length || !rows.every(_isBookRow)) return null;
        books.addAll(rows.map(Book.fromJson));
        addChapters(decoded['chapters']);
        if (decoded['sources'] case final List<dynamic> list) {
          list.forEach(addSource);
        }
        addContents(decoded['chapterContents']);
      } else if (_isBookRow(decoded)) {
        books.add(Book.fromJson(decoded));
      } else {
        return null;
      }
    } else if (decoded is List) {
      // 和其他匯入一樣略過空項目；其他不是物件的不是書架檔。
      final rows = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item == null) continue;
        if (item is! Map<String, dynamic>) return null;
        rows.add(item);
      }
      if (rows.isEmpty) return null;
      if (rows.every((row) => _isBookRow(row) || _isLegadoRow(row))) {
        for (final row in rows) {
          if (_isBookRow(row)) {
            // 夜讀匯出的網路書：帶著自己的目錄、正文與書源。
            books.add(Book.fromJson(row));
            addChapters(row['chapters']);
            addContents(row['chapterContents']);
            addSource(row['source']);
          } else {
            final name = (row['name'] as String).trim();
            if (name.isEmpty) continue;
            legado.add((name: name, author: (row['author'] as String).trim()));
          }
        }
      } else if (rows.every(_looksLikeChapter)) {
        addChapters(rows);
      } else {
        return null;
      }
    } else {
      return null;
    }
    return BookshelfFile(
      books: books,
      chapters: chapters,
      sources: sources.values.toList(),
      contents: contents,
      legado: legado,
    );
  }

  /// 書架的一筆：夜讀匯出的一本書，或 Legado `exportBookshelf` 的
  /// `{name, author, intro}`。一定有書名與作者，而且不是替換規則
  /// （`pattern`、`regex`）、書源（`bookSourceUrl`）或章節（`title`）。
  static bool _isShelfRow(Map<String, dynamic> json) =>
      json['name'] is String &&
      json['author'] is String &&
      !json.containsKey('pattern') &&
      !json.containsKey('regex') &&
      !json.containsKey('bookSourceUrl') &&
      !json.containsKey('title');

  /// 夜讀匯出的一本書：書架的一筆，帶著書的網址。
  static bool _isBookRow(Map<String, dynamic> json) =>
      _isShelfRow(json) &&
      json['bookUrl'] is String &&
      (json['bookUrl'] as String).isNotEmpty;

  /// Legado 匯出的一本書：書架的一筆，沒有書的網址。
  static bool _isLegadoRow(Map<String, dynamic> json) =>
      _isShelfRow(json) && !json.containsKey('bookUrl');

  static bool _looksLikeChapter(Map<String, dynamic> json) =>
      json.containsKey('bookUrl') &&
      json.containsKey('title') &&
      json.containsKey('index');

  static bool _looksLikeSource(Map<String, dynamic> json) =>
      json.containsKey('bookSourceUrl') && json.containsKey('bookSourceName');
}
