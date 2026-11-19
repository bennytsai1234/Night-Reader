import 'dart:async';

import 'package:dio/dio.dart';
import 'package:night_reader/core/ai_find/ai_find_library.dart';
import 'package:night_reader/core/ai_find/ai_find_prompt.dart';
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
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/source/source_interaction.dart';
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
    this.searchLimit = aiFindSearchLimit,
    Dio? wikipedia,
  }) : _service = service ?? BookSourceService(),
       _wikipedia = wikipedia ?? NetworkService().appDio;

  /// 查作品別名用的連線：夜讀自己對外的那一條（照常驗憑證、不帶書源的 Cookie）。
  final Dio _wikipedia;

  /// 一次搜尋最多等多久：時間到就用已經回來的結果（同搜尋頁按「停止」）。
  final Duration searchLimit;

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
    final searching = model.search(
      key: keyword,
      scope: _scope,
      precisionSearch: false,
      kind: kind,
    );
    var finished = false;
    final ended = searching.whenComplete(() => finished = true);
    // 時限到就照搜尋頁的「停止」拿已經回來的結果回去，不等還在跑的書源：
    // 停止只發出取消，規則 JS 這類收不到取消的工作會拖到書源自己的逾時
    // （Codex 審查）。搜尋真的結束才放掉 model。
    final limit = Completer<void>();
    final timer = Timer(searchLimit, limit.complete);
    try {
      await Future.any<Object?>([ended, limit.future, cancelToken.whenCancel]);
    } finally {
      timer.cancel();
    }
    var pending = 0;
    if (!finished) {
      pending = collector.total - collector.completed;
      model.stopSearch();
    }
    ended
        .then((_) => model.dispose(), onError: (_) => model.dispose())
        .ignore();
    _throwIfCancelled(cancelToken);
    // 聚合源每一類都搜（ADR 0056），它搜到的書照搜尋頁的篩法只留這一類。
    final books = [
      for (final book in collector.books)
        if (book.bookKind == kind) book,
    ];
    // 搜尋結果的欄位可能帶著書源的登入資料或 Cookie（書源把它們回顯在書名、
    // 簡介裡）：送給 AI 之前，結果裡每個書源的秘密都要先收進遮蔽清單
    // （Codex 審查：原本只有看詳情、讀章節的書源才收）。
    await Future.wait([
      for (final origin in {for (final book in books) ...book.origins})
        _source(origin).then<void>((_) {}, onError: (Object _) {}),
    ]);
    return (
      books: books,
      tiers: [for (final book in books) searchRelevanceRank(book, keyword)],
      sources: collector.total,
      failed: collector.failed,
      pending: pending,
    );
  }

  /// 詳情照卡片的來源抓；簡介或字數是空的、或抓不到時，到有這本的其他書源
  /// （最多再兩個）照書名與作者精確搜一次再抓（換源的做法），缺的那幾欄照
  /// 先抓到的補上，都齊了就停。只問主要來源時，同一本書在別的書源有簡介、
  /// AI 拿到空的就跳過它（2026-11-15 實跑：蠱真人）；小說的字數同樣，推薦的
  /// 書才不會缺字數。漫畫、有聲書的書源多半沒寫字數，不為它多搜。
  @override
  Future<Book> detail(SearchBook book, CancelToken cancelToken) =>
      _describeFailure(cancelToken, () async {
        Object? failure;
        Book? best;
        try {
          best = await _info(book, cancelToken);
          if (_complete(best, book)) return best;
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
            if (cancelToken.isCancelled) break;
            final candidate = (await _service.preciseSearch(
              source,
              book.name,
              book.author ?? '',
              cancelToken: cancelToken,
            )).firstOrNull;
            if (cancelToken.isCancelled) break;
            if (candidate == null) continue;
            final info = await _service.getBookInfo(
              source,
              candidate.toBook(),
              cancelToken: cancelToken,
            );
            best = best == null ? info : _fill(best, info);
            if (_complete(best, book)) return best;
          } on DioException catch (error) {
            if (CancelToken.isCancel(error) || cancelToken.isCancelled) rethrow;
          } on AppException {
            // 這個書源也不行，換下一個。
          } on AiFindUnreadable {
            // 書源已經不在了。
          }
        }
        _throwIfCancelled(cancelToken);
        if (best != null) return best;
        throw failure!;
      });

  static bool _hasIntro(Book book) =>
      aiFindPlainText(book.customIntro ?? book.intro ?? '').isNotEmpty;

  static bool _hasWordCount(Book book) =>
      (book.wordCount ?? '').trim().isNotEmpty;

  static bool _complete(Book book, SearchBook card) =>
      _hasIntro(book) &&
      (card.bookKind != BookSourceKind.novel || _hasWordCount(book));

  /// [base] 缺的簡介與字數照 [other] 補，其他照 [base]。
  static Book _fill(Book base, Book other) {
    final intro = _hasIntro(base) || !_hasIntro(other)
        ? null
        : other.customIntro ?? other.intro;
    return base.copyWith(
      intro: intro,
      customIntro: base.customIntro == null ? null : intro,
      wordCount: _hasWordCount(base) ? null : other.wordCount,
    );
  }

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
    final index = number == aiFindLastChapter ? toc.length : number;
    if (index > toc.length) {
      throw AiFindUnreadable('沒有第 $index 章，共 ${toc.length} 章');
    }
    final chapter = toc[index - 1];
    // 付費、還沒買的章節不抓（ADR 0057）。
    if (chapter.isLocked) throw const AiFindUnreadable(lockedChapterNotice);
    final raw = await _service.getContent(
      source,
      info,
      chapter,
      nextChapterUrl: index < toc.length ? toc[index].url : null,
      cancelToken: cancelToken,
    );
    final text = aiFindPlainText(raw);
    if (text.isEmpty) throw const AiFindUnreadable('正文是空的');
    return (title: chapter.title, text: text, number: index, total: toc.length);
  });

  /// 查中文維基百科：先照名稱拿條目（轉址的別名會轉到正式條目），沒有就用
  /// 全文搜尋拿第一個條目；再照台灣、中國大陸、香港各拿一次條目名，維基百科
  /// 照地區轉換譯名（鏈鋸人／电锯人）。只送作品名，不送使用者的任何資料。
  @override
  Future<AiFindWorkNames?> workNames(
    String name,
    CancelToken cancelToken,
  ) async {
    try {
      // 同名詞搜到的前幾個條目：名稱有歧義時（「巨人」是神話的巨人，不是
      // 進擊的巨人）讓 AI 自己選，再用條目名查一次。
      final hits = await _wikiSearch(name, cancelToken);
      var summary = await _wikiSummary(name, 'zh-tw', cancelToken);
      if (summary == null) {
        if (hits.isEmpty) return null;
        summary = await _wikiSummary(hits.first, 'zh-tw', cancelToken);
        if (summary == null) return null;
      }
      final title = summary.title;
      final names = <String, String>{'台灣': summary.display};
      for (final (label, variant) in [('中國大陸', 'zh-cn'), ('香港', 'zh-hk')]) {
        final other = await _wikiSummary(title, variant, cancelToken);
        if (other != null) names[label] = other.display;
      }
      return (
        title: title,
        names: names,
        aliases: await _wikiRedirects(title, cancelToken),
        intro: summary.extract,
        others: [
          for (final hit in hits)
            if (hit != title) hit,
        ],
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || cancelToken.isCancelled) rethrow;
      throw AiFindUnreadable('連不上中文維基百科：${aiFindNetworkFailure(error)}');
    }
  }

  static const String _wikiBase = 'https://zh.wikipedia.org';

  /// 維基百科要求自動程式帶可辨識的 User-Agent。
  static const Map<String, String> _wikiHeaders = {
    'User-Agent': 'NightReader/1.0 (AI book finder; work name lookup)',
  };

  Future<({String title, String display, String extract})?> _wikiSummary(
    String title,
    String variant,
    CancelToken cancelToken,
  ) async {
    final response = await _wikipedia.get<Map<String, dynamic>>(
      '$_wikiBase/api/rest_v1/page/summary/'
      '${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
      options: Options(
        headers: {..._wikiHeaders, 'Accept-Language': variant},
        validateStatus: (status) => status == 200 || status == 404,
      ),
      cancelToken: cancelToken,
    );
    final data = response.data;
    if (response.statusCode != 200 || data == null) return null;
    final pageTitle = '${data['title'] ?? ''}'.trim();
    if (pageTitle.isEmpty) return null;
    final display = aiFindPlainText('${data['displaytitle'] ?? pageTitle}');
    return (
      title: pageTitle,
      display: display.isEmpty ? pageTitle : display,
      extract: '${data['extract'] ?? ''}'.trim(),
    );
  }

  /// 全文搜尋的前 [_wikiSearchLimit] 個條目名。
  Future<List<String>> _wikiSearch(String name, CancelToken cancelToken) async {
    final response = await _wikipedia.get<Map<String, dynamic>>(
      '$_wikiBase/w/api.php',
      queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': name,
        'srlimit': '$_wikiSearchLimit',
        'format': 'json',
      },
      options: Options(headers: _wikiHeaders),
      cancelToken: cancelToken,
    );
    final hits = (response.data?['query'] as Map?)?['search'];
    if (hits is! List) return const [];
    return [
      for (final hit in hits)
        if ('${(hit as Map)['title'] ?? ''}'.trim() case final title
            when title.isNotEmpty)
          title,
    ];
  }

  static const int _wikiSearchLimit = 5;

  /// 轉到這個條目的名稱（轉址頁）：各地譯名、簡稱、原文名多半都在這裡
  /// （ONE PIECE 有航海王、海賊王、海贼王、俠盜路飛）。
  Future<List<String>> _wikiRedirects(
    String title,
    CancelToken cancelToken,
  ) async {
    final response = await _wikipedia.get<Map<String, dynamic>>(
      '$_wikiBase/w/api.php',
      queryParameters: {
        'action': 'query',
        'prop': 'redirects',
        'titles': title,
        'rdlimit': '50',
        'rdnamespace': '0',
        'format': 'json',
      },
      options: Options(headers: _wikiHeaders),
      cancelToken: cancelToken,
    );
    final pages = (response.data?['query'] as Map?)?['pages'];
    if (pages is! Map) return const [];
    return [
      for (final page in pages.values)
        for (final redirect
            in ((page as Map)['redirects'] as List?) ?? const [])
          if ('${(redirect as Map)['title'] ?? ''}'.trim() case final name
              when name.isNotEmpty)
            name,
    ];
  }

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
    final kinds = await _exploreKinds(source, cancelToken);
    return [for (final kind in kinds) kind.title];
  });

  @override
  Future<List<SearchBook>> exploreBooks(
    AiFindExploreSource source,
    int category,
    int page,
    CancelToken cancelToken,
  ) => _describeFailure(cancelToken, () async {
    final kinds = await _exploreKinds(source, cancelToken);
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
    // 閱讀紀錄照紀錄名稱（漫畫、有聲書帶類別前綴，`Book.recordName`）各台
    // 加總，同閱讀統計（Codex 審查：照書名對，漫畫與有聲書的時間對不上）。
    final seconds = <String, int>{};
    for (final record in records) {
      seconds[record.bookName] =
          (seconds[record.bookName] ?? 0) + record.readTime;
    }
    final byRecord = {for (final book in books) book.recordName: book};
    // 送出前先載入這些書的書源：分類與簡介是書源給的，可能帶著它的登入資料
    // 或 Cookie，秘密要先收進遮蔽清單（Codex 審查）。書源已經刪掉的書不給
    // 編號，只當口味看：點開推薦會落在不在了的書源上（ADR 0069）。
    final alive = <String>{};
    await Future.wait([
      for (final origin in {
        for (final book in books)
          if (!book.isLocal &&
              book.origin.isNotEmpty &&
              (book.isInBookshelf || (seconds[book.recordName] ?? 0) > 0))
            book.origin,
      })
        _source(origin)
            .then<void>((_) => alive.add(origin), onError: (Object _) {}),
    ]);
    AiFindShelfEntry entry(Book book, int read, {required bool onShelf}) =>
        _entry(
          book,
          read,
          onShelf: onShelf,
          hasSource: alive.contains(book.origin),
        );
    final entries = <AiFindShelfEntry>[];
    final named = <String>{};
    for (final book in books) {
      if (!book.isInBookshelf) continue;
      named.add(book.recordName);
      entries.add(entry(book, seconds[book.recordName] ?? 0, onShelf: true));
    }
    // 讀過、已經移出書架的：資料庫還留著這本書時帶上作者與類別，沒有時照
    // 紀錄名稱還原書名與類別。
    for (final MapEntry(key: record, value: read) in seconds.entries) {
      if (named.contains(record) || read <= 0) continue;
      final book = byRecord[record];
      final split = BookSourceKind.splitRecordName(record);
      entries.add(
        book != null
            ? entry(book, read, onShelf: false)
            : (
                name: split.name,
                author: '',
                kind: split.kind,
                onShelf: false,
                local: false,
                readSeconds: read,
                chapter: null,
                chapterIndex: null,
                chapterTotal: null,
                category: null,
                intro: null,
                book: null,
              ),
      );
    }
    return entries;
  }

  static AiFindShelfEntry _entry(
    Book book,
    int readSeconds, {
    required bool onShelf,
    required bool hasSource,
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
      category: book.kind,
      // 書源給的簡介，不送使用者自己改寫的（customIntro）。
      intro: book.intro,
      // 網路書照它的書源看詳情、讀章節（同搜尋到的書）；本地書與書源已經
      // 刪掉的沒有。
      book: book.isLocal || !hasSource
          ? null
          : SearchBook(
              bookUrl: book.bookUrl,
              name: book.name,
              author: book.author,
              kind: book.kind,
              coverUrl: book.coverUrl,
              intro: book.intro,
              wordCount: book.wordCount,
              latestChapterTitle: book.latestChapterTitle,
              origin: book.origin,
              originName: book.originName,
              type: book.type,
              variable: book.variable,
              tocUrl: book.tocUrl,
            ),
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

  Future<List<ExploreKind>> _exploreKinds(
    AiFindExploreSource source,
    CancelToken cancelToken,
  ) async {
    final cached = _kinds[source.url];
    if (cached != null) return cached;
    final full = await _source(source.url);
    final kinds = await _service.exploreKinds(
      full.exploreUrl,
      source: full,
      cancelToken: cancelToken,
    );
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

/// 找書的一次搜尋最多等多久（使用者 2026-11-15：一次搜尋盡量在 60 秒內）。
/// 全部書源要等 80 到 150 秒，多出來的是少數拖到逾時的書源。
const Duration aiFindSearchLimit = Duration(seconds: 50);

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
  int completed = 0;

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
    this.completed = completed;
  }
}
