import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';

class _FakeBookSourceDao extends Fake implements BookSourceDao {
  _FakeBookSourceDao(this.sources);

  final List<BookSource> sources;

  @override
  Future<List<BookSource>> getEnabled() async => sources;

  @override
  Future<BookSource?> getByUrl(String url) async {
    for (final source in sources) {
      if (source.bookSourceUrl == url) return source;
    }
    return null;
  }
}

class _FakeSearchBookDao extends Fake implements SearchBookDao {
  @override
  Future<List<SearchBook>> getSearchBooks(String name, String author) async {
    return const <SearchBook>[];
  }
}

class _TrackingBookSourceService extends BookSourceService {
  int preciseSearchCalls = 0;
  int nameOnlySearchCalls = 0;
  final List<String> requestedOrigins = <String>[];

  @override
  Future<List<SearchBook>> preciseSearch(
    BookSource source,
    String name,
    String author,
  ) async {
    preciseSearchCalls++;
    return const <SearchBook>[];
  }

  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    nameOnlySearchCalls++;
    requestedOrigins.add(source.bookSourceUrl);
    final candidate = SearchBook(
      bookUrl: '${source.bookSourceUrl}/book/1',
      name: key,
      author: '不同作者',
      origin: source.bookSourceUrl,
      originName: source.bookSourceName,
    );
    if (filter?.call(candidate.name, candidate.author ?? '') == false) {
      return const <SearchBook>[];
    }
    return <SearchBook>[candidate];
  }
}

class _ControlledBookSourceService extends BookSourceService {
  final List<CancelToken> tokens = <CancelToken>[];
  final List<Completer<List<SearchBook>>> slowCompleters =
      <Completer<List<SearchBook>>>[];

  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) {
    if (cancelToken != null) tokens.add(cancelToken);

    if (source.bookSourceUrl.contains('fast')) {
      final candidate = SearchBook(
        bookUrl: '${source.bookSourceUrl}/book/1',
        name: key,
        author: '原作者',
        origin: source.bookSourceUrl,
        originName: source.bookSourceName,
      );
      return Future<List<SearchBook>>.value(
        filter?.call(candidate.name, candidate.author ?? '') == false
            ? const <SearchBook>[]
            : <SearchBook>[candidate],
      );
    }

    final completer = Completer<List<SearchBook>>();
    slowCompleters.add(completer);
    return completer.future;
  }
}

Book _book() {
  return Book(
    bookUrl: 'https://old-source.example/book/1',
    name: '測試書',
    author: '原作者',
    origin: 'https://old-source.example',
    originName: '舊源',
  );
}

BookSource _source(String url, String name) {
  return BookSource(bookSourceUrl: url, bookSourceName: name);
}

Future<void> _drainMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('關閉作者校驗時只比對書名，不要求候選作者為空', () async {
    final source = _source('https://new-source.example', '新源');
    final service = _TrackingBookSourceService();
    final provider = BookDetailChangeSourceProvider(
      _book(),
      service: service,
      sourceDao: _FakeBookSourceDao(<BookSource>[source]),
      searchBookDao: _FakeSearchBookDao(),
      autoStart: false,
    );
    addTearDown(provider.dispose);

    provider.checkAuthor = false;
    await provider.startSearch();

    expect(service.preciseSearchCalls, 0);
    expect(service.nameOnlySearchCalls, 1);
    expect(provider.allResults, hasLength(1));
    expect(provider.allResults.single.author, '不同作者');
  });

  test('換源搜尋不會再次搜尋目前來源', () async {
    final service = _TrackingBookSourceService();
    final provider = BookDetailChangeSourceProvider(
      _book(),
      service: service,
      sourceDao: _FakeBookSourceDao(<BookSource>[
        _source('https://old-source.example', '舊源'),
        _source('https://new-source.example', '新源'),
      ]),
      searchBookDao: _FakeSearchBookDao(),
      autoStart: false,
    );
    addTearDown(provider.dispose);

    provider.checkAuthor = false;
    await provider.startSearch();

    expect(service.requestedOrigins, <String>['https://new-source.example']);
  });

  test('快速來源完成後立即顯示，不等待慢來源', () async {
    final service = _ControlledBookSourceService();
    final provider = BookDetailChangeSourceProvider(
      _book(),
      service: service,
      sourceDao: _FakeBookSourceDao(<BookSource>[
        _source('https://fast-source.example', '快速源'),
        _source('https://slow-source.example', '慢速源'),
      ]),
      searchBookDao: _FakeSearchBookDao(),
      sourceSearchTimeout: const Duration(seconds: 1),
      autoStart: false,
    );
    addTearDown(provider.dispose);

    final searchFuture = provider.startSearch();
    await _drainMicrotasks();

    expect(provider.isSearching, isTrue);
    expect(provider.allResults, hasLength(1));
    expect(provider.allResults.single.origin, 'https://fast-source.example');
    expect(service.slowCompleters, hasLength(1));

    service.slowCompleters.single.complete(const <SearchBook>[]);
    await searchFuture;
    expect(provider.isSearching, isFalse);
  });

  test('重新搜尋會取消上一批仍在執行的網路請求', () async {
    final service = _ControlledBookSourceService();
    final provider = BookDetailChangeSourceProvider(
      _book(),
      service: service,
      sourceDao: _FakeBookSourceDao(<BookSource>[
        _source('https://slow-source.example', '慢速源'),
      ]),
      searchBookDao: _FakeSearchBookDao(),
      sourceSearchTimeout: const Duration(seconds: 1),
      autoStart: false,
    );
    addTearDown(provider.dispose);

    final firstSearch = provider.startSearch();
    await _drainMicrotasks();
    expect(service.tokens, hasLength(1));
    final firstToken = service.tokens.first;

    final secondSearch = provider.startSearch();
    await _drainMicrotasks();

    expect(firstToken.isCancelled, isTrue);
    expect(service.slowCompleters, hasLength(2));

    for (final completer in service.slowCompleters) {
      if (!completer.isCompleted) {
        completer.complete(const <SearchBook>[]);
      }
    }
    await Future.wait(<Future<void>>[firstSearch, secondSearch]);
  });
}
