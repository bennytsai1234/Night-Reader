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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('關閉作者校驗時只比對書名，不要求候選作者為空', () async {
    final source = BookSource(
      bookSourceUrl: 'https://new-source.example',
      bookSourceName: '新源',
    );
    final service = _TrackingBookSourceService();
    final provider = BookDetailChangeSourceProvider(
      Book(
        bookUrl: 'https://old-source.example/book/1',
        name: '測試書',
        author: '原作者',
        origin: 'https://old-source.example',
        originName: '舊源',
      ),
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
}
