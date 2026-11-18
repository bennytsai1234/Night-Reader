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

import 'change_source_sites.dart';

/// 每個書源回應要多久、回的字數照 [_sites] 定；目錄章數照 [chapters]。
class _Sites extends BookSourceService with ChapterListSites {
  _Sites([this.chapters = const {}]);

  final Map<String, int> chapters;

  @override
  int chapterCountFor(String origin) => chapters[origin] ?? 10;

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

  late _Sites sites;

  Future<BookDetailChangeSourceProvider> search([
    Map<String, int> chapters = const {},
  ]) async {
    sites = _Sites(chapters);
    final provider = BookDetailChangeSourceProvider(
      Book(
        bookUrl: 'https://mine.example/book',
        origin: 'https://mine.example',
        name: '夜雨聽書',
        author: '沈知秋',
        wordCount: '121.5萬字',
      ),
      service: sites,
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

  test('目錄抓到了才列，右邊寫共幾章；抓不到目錄的不列（換不過去）', () async {
    final provider = await search({
      'https://fast.example': 1648,
      'https://partial.example': 0,
    });

    expect(provider.filteredResults.map((r) => r.origin), [
      'https://fast.example',
      'https://unknown.example',
      'https://slow.example',
    ]);
    final fast = provider.filteredResults.first;
    expect(provider.chapterCountOf(fast), 1648);
    // 抓好的目錄留給換源用，選它時不用再抓一次。
    expect(provider.tocOf(fast)?.chapters, hasLength(1648));
    expect(provider.tocOf(fast)?.book.bookUrl, 'https://fast.example/book');
  });

  test('按「重新搜尋」重抓目錄：網站多了章節，章數與換源用的目錄跟著更新', () async {
    final chapters = {'https://fast.example': 10};
    final provider = await search(chapters);
    SearchBook fast() => provider.filteredResults.firstWhere(
      (r) => r.origin == 'https://fast.example',
    );
    expect(provider.chapterCountOf(fast()), 10);

    chapters['https://fast.example'] = 12;
    final refreshing = provider.refreshSearch();
    // 按下當下就清空、標成搜尋中，上一輪的列不能再點。
    expect(provider.filteredResults, isEmpty);
    expect(provider.isSearching, isTrue);
    await refreshing;

    expect(provider.chapterCountOf(fast()), 12);
    expect(provider.tocOf(fast())?.chapters, hasLength(12));
  });

  test('換分組、切換校驗作者沿用這次面板抓過的目錄，不重抓', () async {
    final chapters = {'https://fast.example': 10};
    final provider = await search(chapters);
    chapters['https://fast.example'] = 12;

    // 切換校驗作者、換分組做的事：改條件後重新搜尋。
    provider.checkAuthor = !provider.checkAuthor;
    await provider.startSearch();

    final fast = provider.filteredResults.firstWhere(
      (r) => r.origin == 'https://fast.example',
    );
    expect(provider.chapterCountOf(fast), 10);
  });

  test('抓整份目錄：哪一頁抓不到就不列，章數不會少算', () async {
    await search();
    expect(sites.completeRequests, isNotEmpty);
    expect(sites.completeRequests, everyElement(isTrue));
  });

  test('留著的目錄總共超過三萬章時只記章數，換源時再抓', () async {
    final provider = await search({
      'https://fast.example': 20000,
      'https://slow.example': 20000,
    });
    final big = [
      for (final r in provider.filteredResults)
        if (provider.chapterCountOf(r) == 20000) r,
    ];

    expect(big, hasLength(2));
    expect(big.where((r) => provider.tocOf(r) == null), hasLength(1));
  });
}
