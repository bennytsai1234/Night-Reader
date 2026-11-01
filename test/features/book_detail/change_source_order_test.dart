import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';

/// 每個書源回應要多久、回的字數照 [_sites] 定。
class _Sites extends BookSourceService {
  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    final (delay, words) = _sites[source.bookSourceUrl]!;
    await Future<void>.delayed(Duration(milliseconds: delay));
    return [
      SearchBook(
        bookUrl: '${source.bookSourceUrl}/book',
        name: '夜雨聽書',
        author: '沈知秋',
        origin: source.bookSourceUrl,
        originName: source.bookSourceUrl,
        wordCount: words,
      ),
    ];
  }
}

/// 書源順序是 slow、fast、partial、unknown；回應時間與字數各不相同。
const _sites = <String, (int, String?)>{
  'https://slow.example': (120, '120萬字'),
  'https://fast.example': (10, '118萬字'),
  'https://partial.example': (40, '30萬字'),
  'https://unknown.example': (60, null),
};

void main() {
  late AppDatabase db;
  late BookSourceDao sourceDao;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sourceDao = BookSourceDao(db);
    for (final (i, url) in [..._sites.keys, 'https://mine.example'].indexed) {
      await sourceDao.upsert(
        BookSource(bookSourceUrl: url, bookSourceName: url, customOrder: i),
      );
    }
  });
  tearDown(() => db.close());

  Future<BookDetailChangeSourceProvider> search() async {
    final provider = BookDetailChangeSourceProvider(
      Book(
        bookUrl: 'https://mine.example/book',
        origin: 'https://mine.example',
        name: '夜雨聽書',
        author: '沈知秋',
        wordCount: '121.5萬字',
      ),
      service: _Sites(),
      sourceDao: sourceDao,
      searchBookDao: SearchBookDao(db),
      autoStart: false,
    );
    addTearDown(provider.dispose);
    await provider.startSearch();
    return provider;
  }

  test('換源清單照這次回應的快慢排，不照書源順序', () async {
    final provider = await search();
    expect(provider.filteredResults.map((r) => r.origin), [
      'https://fast.example',
      'https://partial.example',
      'https://unknown.example',
      'https://slow.example',
    ]);
  });

  test('打開「不列字數差太多的」：差到一半以下或兩倍以上的不列，讀不出字數的照列', () async {
    final provider = await search();
    provider.toggleExcludeFarWordCount();
    expect(provider.filteredResults.map((r) => r.origin), [
      'https://fast.example',
      'https://unknown.example',
      'https://slow.example',
    ]);
    provider.toggleExcludeFarWordCount();
    expect(provider.filteredResults, hasLength(4));
  });
}
