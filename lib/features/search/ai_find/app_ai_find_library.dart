import 'package:dio/dio.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/core/ai_repair/ai_repair_secrets.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:night_reader/features/search/search_model.dart';

/// AI 找書的工具實際去拿東西的地方（ADR 0060）：搜尋照搜尋頁（同一個
/// [SearchModel]、同一份範圍、同一套合併），詳情、目錄、正文照書籍詳情與
/// 閱讀器（[BookSourceService]），發現頁照發現頁。讀到的正文不存進快取、
/// 不動進度與閱讀時間：這本書還不在書架上。
///
/// 書源要使用者操作（網頁驗證、驗證碼）時照 ADR 0038 立刻失敗，訊息照實回。
class AppAiFindLibrary implements AiFindLibrary {
  AppAiFindLibrary({
    required this._scope,
    BookSourceService? service,
    this._searchLoader,
  }) : _service = service ?? BookSourceService();

  /// 開始找書時搜尋頁的範圍；找書中途改範圍不影響這次。
  final SearchScope _scope;
  final BookSourceService _service;
  final SearchBookLoader? _searchLoader;

  final Map<String, BookSource?> _sources = {};

  @override
  final Set<String> secrets = {};

  /// 詳情抓過的書（照書的網址）：讀章節要它的目錄網址。
  final Map<String, Book> _infos = {};

  /// 抓過的目錄（照書的網址），不含分卷標題。
  final Map<String, List<BookChapter>> _tocs = {};

  /// 每個發現書源的分類（有網址的那幾個，照順序）。
  final Map<String, List<ExploreKind>> _kinds = {};

  @override
  Future<AiFindSearchResult> search(
    String keyword,
    BookSourceKind kind,
    CancelToken cancelToken,
  ) async {
    final collector = _SearchCollector();
    final model = SearchModel(
      callback: collector,
      loader: _searchLoader,
      persist: false,
    );
    cancelToken.whenCancel.then((_) => model.cancelSearch()).ignore();
    try {
      await model.search(
        key: keyword,
        scope: _scope,
        precisionSearch: false,
        kind: kind,
      );
    } finally {
      model.dispose();
    }
    _throwIfCancelled(cancelToken);
    return (
      // 聚合源每一類都搜（ADR 0056），它搜到的書照搜尋頁的篩法只留這一類。
      books: [
        for (final book in collector.books)
          if (book.bookKind == kind) book,
      ],
      sources: collector.total,
      failed: collector.failed,
    );
  }

  /// 詳情照卡片的來源抓；簡介是空的或抓不到時，到有這本的其他書源（最多
  /// 再兩個）照書名與作者精確搜一次再抓（換源的做法），第一個有簡介的為準。
  /// 只問主要來源時，同一本書在別的書源有簡介、AI 拿到空的就跳過它
  /// （2026-11-15 實跑：蠱真人）。
  @override
  Future<Book> detail(SearchBook book, CancelToken cancelToken) =>
      _describeFailure(cancelToken, () async {
        Object? failure;
        Book? first;
        try {
          first = await _info(book, cancelToken);
          if (_hasIntro(first)) return first;
        } on DioException catch (error) {
          if (CancelToken.isCancel(error)) rethrow;
          failure = error;
        } on AppException catch (error) {
          failure = error;
        }
        final others = [
          for (final origin in book.origins)
            if (origin != book.origin) origin,
        ].take(2);
        for (final origin in others) {
          try {
            final source = await _source(origin);
            final candidate = (await _service.preciseSearch(
              source,
              book.name,
              book.author ?? '',
            )).firstOrNull;
            if (candidate == null) continue;
            final info = await _service.getBookInfo(
              source,
              candidate.toBook(),
              cancelToken: cancelToken,
            );
            if (_hasIntro(info)) return info;
          } on DioException catch (error) {
            if (CancelToken.isCancel(error) || cancelToken.isCancelled) rethrow;
          } on AppException {
            // 這個書源也不行，換下一個。
          } on AiFindUnreadable {
            // 書源已經不在了。
          }
        }
        if (first != null) return first;
        throw failure!;
      });

  static bool _hasIntro(Book book) =>
      aiFindPlainText(book.customIntro ?? book.intro ?? '').isNotEmpty;

  @override
  Future<AiFindChapter> chapter(
    SearchBook book,
    int number,
    CancelToken cancelToken,
  ) => _describeFailure(cancelToken, () async {
    final source = await _source(book.origin);
    final info = await _info(book, cancelToken);
    final toc = _tocs[book.bookUrl] ??= [
      for (final chapter in await _service.getChapterList(
        source,
        info,
        cancelToken: cancelToken,
      ))
        if (!chapter.isVolume) chapter,
    ];
    if (toc.isEmpty) throw const AiFindUnreadable('目錄是空的');
    if (number > toc.length) {
      throw AiFindUnreadable('沒有第 $number 章，共 ${toc.length} 章');
    }
    final chapter = toc[number - 1];
    // 付費、還沒買的章節不抓（ADR 0057）。
    if (chapter.isLocked) throw const AiFindUnreadable(lockedChapterNotice);
    final raw = await _service.getContent(
      source,
      info,
      chapter,
      nextChapterUrl: number < toc.length ? toc[number].url : null,
      cancelToken: cancelToken,
    );
    final text = aiFindPlainText(raw);
    if (text.isEmpty) throw const AiFindUnreadable('正文是空的');
    return (title: chapter.title, text: text, total: toc.length);
  });

  @override
  Future<List<AiFindExploreSource>> exploreSources() async {
    final inScope = _scope.isAll
        ? null
        : {
            for (final source in await _scope.getBookSources())
              source.bookSourceUrl,
          };
    return [
      for (final source in await getIt<BookSourceDao>().getDiscoveryPart())
        if (source.canParticipateInDiscovery &&
            (inScope == null || inScope.contains(source.bookSourceUrl)))
          (
            url: source.bookSourceUrl,
            name: source.bookSourceName,
            kind: source.sourceKind,
          ),
    ];
  }

  @override
  Future<List<String>> exploreCategories(
    AiFindExploreSource source,
    CancelToken cancelToken,
  ) => _describeFailure(cancelToken, () async {
    final kinds = await _exploreKinds(source);
    return [for (final kind in kinds) kind.title];
  });

  @override
  Future<List<SearchBook>> exploreBooks(
    AiFindExploreSource source,
    int category,
    int page,
    CancelToken cancelToken,
  ) => _describeFailure(cancelToken, () async {
    final kinds = await _exploreKinds(source);
    final full = await _source(source.url);
    return _service.exploreBooks(
      full,
      kinds[category].url!,
      page: page,
      cancelToken: cancelToken,
    );
  });

  @override
  Future<List<AiFindShelfEntry>> shelf() async {
    final books = await getIt<BookDao>().getAll();
    final records = await getIt<ReadRecordDao>().getAll();
    // 閱讀紀錄照書名、各台加總（閱讀統計的算法）。
    final seconds = <String, int>{};
    for (final record in records) {
      seconds[record.bookName] =
          (seconds[record.bookName] ?? 0) + record.readTime;
    }
    final entries = <AiFindShelfEntry>[];
    final named = <String>{};
    for (final book in books) {
      if (!book.isInBookshelf) continue;
      named.add(book.name);
      entries.add(_entry(book, seconds[book.name] ?? 0, onShelf: true));
    }
    // 讀過、已經移出書架的：資料庫還留著這本書時帶上作者與類別。
    final byName = {for (final book in books) book.name: book};
    for (final MapEntry(key: name, value: read) in seconds.entries) {
      if (named.contains(name) || read <= 0) continue;
      final book = byName[name];
      entries.add(
        book != null
            ? _entry(book, read, onShelf: false)
            : (
                name: name,
                author: '',
                kind: null,
                onShelf: false,
                local: false,
                readSeconds: read,
                chapter: null,
                chapterIndex: null,
                chapterTotal: null,
              ),
      );
    }
    return entries;
  }

  static AiFindShelfEntry _entry(
    Book book,
    int readSeconds, {
    required bool onShelf,
  }) {
    final total = book.totalChapterNum;
    return (
      name: book.name,
      author: book.author,
      kind: book.bookKind,
      onShelf: onShelf,
      local: book.isLocal,
      readSeconds: readSeconds,
      chapter: (book.durChapterTitle ?? '').trim().isEmpty
          ? null
          : book.durChapterTitle!.trim(),
      chapterIndex: total > 0 ? book.chapterIndex + 1 : null,
      chapterTotal: total > 0 ? total : null,
    );
  }

  Future<Book> _info(SearchBook book, CancelToken cancelToken) async {
    final cached = _infos[book.bookUrl];
    if (cached != null) return cached;
    final source = await _source(book.origin);
    final info = await _service.getBookInfo(
      source,
      book.toBook(),
      cancelToken: cancelToken,
    );
    return _infos[book.bookUrl] = info;
  }

  Future<List<ExploreKind>> _exploreKinds(AiFindExploreSource source) async {
    final cached = _kinds[source.url];
    if (cached != null) return cached;
    final full = await _source(source.url);
    final kinds = await _service.exploreKinds(full.exploreUrl, source: full);
    // 沒有網址的是分組標題；ERROR: 開頭的是解析器把失敗寫成的分類。
    final error = kinds
        .where((kind) => kind.title.startsWith('ERROR:'))
        .firstOrNull;
    if (error != null) {
      throw AiFindUnreadable('發現頁的分類讀不出來：${error.title.substring(6).trim()}');
    }
    return _kinds[source.url] = [
      for (final kind in kinds)
        if ((kind.url ?? '').trim().isNotEmpty) kind,
    ];
  }

  Future<BookSource> _source(String url) async {
    if (!_sources.containsKey(url)) {
      final loaded = _sources[url] = await getIt<BookSourceDao>().getByUrl(url);
      if (loaded != null) secrets.addAll(await aiRepairSecretsOf(loaded));
    }
    final source = _sources[url];
    if (source == null) throw const AiFindUnreadable('書源已經不在了');
    return source;
  }

  /// 抓取的錯誤換成一句照實回給 AI 的話（[AiFindUnreadable]）；按了停止的
  /// 照樣丟出取消。
  static Future<T> _describeFailure<T>(
    CancelToken cancelToken,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on AiFindUnreadable {
      rethrow;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || cancelToken.isCancelled) rethrow;
      throw AiFindUnreadable(aiFindNetworkFailure(error));
    } on SourceInteractionBlockedException {
      throw const AiFindUnreadable('書源要使用者操作（網頁驗證或驗證碼），找書不開網頁');
    } on AppException catch (error) {
      // 付費章節、要登入、真人驗證、正文或目錄是空的：例外本身的話就是原因。
      throw AiFindUnreadable(error.message);
    }
  }

  static void _throwIfCancelled(CancelToken cancelToken) {
    if (!cancelToken.isCancelled) return;
    throw DioException.requestCancelled(
      requestOptions: RequestOptions(),
      reason: cancelToken.cancelError?.message ?? '已停止',
    );
  }
}

/// 網路錯誤回給 AI 的話：網站回了幾號，或連線怎麼斷的。
String aiFindNetworkFailure(DioException error) {
  final code = error.response?.statusCode;
  if (code != null) return '網站回應 $code';
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout => '連線逾時',
    DioExceptionType.connectionError => '連不上網站',
    DioExceptionType.badCertificate => '網站的憑證有問題',
    _ => '網路錯誤：${error.message ?? error.type.name}',
  };
}

/// 收一次搜尋的結果：最後一份合併卡、送了幾個書源、幾個失敗。
class _SearchCollector implements SearchModelCallback {
  List<SearchBook> books = const [];
  int total = 0;
  int failed = 0;

  @override
  void onSearchStart() {}

  @override
  void onSearchSuccess(List<SearchBook> searchBooks) => books = searchBooks;

  @override
  void onSearchFailure(SearchFailure failure) {}

  @override
  void onSearchFinish({required bool isEmpty}) {}

  @override
  void onSearchProgress({
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  }) {
    this.total = total;
    this.failed = failed;
  }
}
