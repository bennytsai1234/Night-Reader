import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';

/// 繁體站與簡體站各只認得自己那種寫法，都只回這本書。
class _SingleScriptSites extends BookSourceService {
  final searchedKeys = <String>[];

  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    searchedKeys.add(key);
    final origin = source.bookSourceUrl;
    final (name, author) = origin == _twSite
        ? ('劍來', '烽火戲諸侯')
        : ('剑来', '烽火戏诸侯');
    if (key != name || filter != null && !filter(name, author)) return [];
    return [
      SearchBook(
        bookUrl: '$origin/book',
        name: name,
        author: author,
        origin: origin,
        originName: origin,
      ),
    ];
  }
}

const _twSite = 'https://tw.example';
const _cnSite = 'https://cn.example';

void main() {
  late AppDatabase db;
  late BookSourceDao sourceDao;
  late SearchBookDao searchBookDao;

  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sourceDao = BookSourceDao(db);
    searchBookDao = SearchBookDao(db);
    for (final url in [_twSite, _cnSite]) {
      await sourceDao.upsert(
        BookSource.fromJson({'bookSourceName': url, 'bookSourceUrl': url}),
      );
    }
  });

  tearDown(() => db.close());

  Future<BookDetailChangeSourceProvider> searchFor(
    Book book,
    BookSourceService service,
  ) async {
    final provider = BookDetailChangeSourceProvider(
      book,
      service: service,
      sourceDao: sourceDao,
      searchBookDao: searchBookDao,
      autoStart: false,
    );
    addTearDown(provider.dispose);
    await provider.startSearch();
    return provider;
  }

  test('a book opened from a traditional site finds the simplified-site '
      'source', () async {
    final service = _SingleScriptSites();
    final provider = await searchFor(
      Book(
        bookUrl: '$_twSite/book',
        origin: _twSite,
        name: '劍來',
        author: '烽火戲諸侯',
      ),
      service,
    );

    expect(provider.allResults.map((r) => r.origin), [_cnSite]);
    expect(service.searchedKeys, containsAll(['劍來', '剑来']));
  });

  test('a book opened from a simplified site finds the traditional-site '
      'source', () async {
    final provider = await searchFor(
      Book(
        bookUrl: '$_cnSite/book',
        origin: _cnSite,
        name: '剑来',
        author: '烽火戏诸侯',
      ),
      _SingleScriptSites(),
    );

    expect(provider.allResults.map((r) => r.origin), [_twSite]);
  });

  test('switching to the other script keeps the chapter being read', () {
    final toc = [
      for (final (i, title) in ['序章 少年', '第一章 惊蛰', '第二章 开门'].indexed)
        BookChapter(url: '$_cnSite/c/$i', title: title, index: i),
    ];

    expect(
      alignChapterIndex(
        oldIndex: 2,
        oldTitle: '第一章 驚蟄',
        oldTotalCount: 4,
        newChapters: toc,
      ),
      1,
    );
  });

  test('stored search results in the other script show up first', () async {
    await searchBookDao.insertList([
      SearchBook(
        bookUrl: '$_cnSite/book',
        name: '剑来',
        author: '烽火戏诸侯',
        origin: _cnSite,
        originName: _cnSite,
      ),
      SearchBook(
        bookUrl: '$_cnSite/other',
        name: '剑来',
        author: '别人',
        origin: _cnSite,
        originName: _cnSite,
      ),
    ]);
    final provider = BookDetailChangeSourceProvider(
      Book(
        bookUrl: '$_twSite/book',
        origin: _twSite,
        name: '劍來',
        author: '烽火戲諸侯',
      ),
      service: _SingleScriptSites(),
      sourceDao: sourceDao,
      searchBookDao: searchBookDao,
      autoStart: false,
    );
    addTearDown(provider.dispose);

    final search = provider.startSearch();
    await pumpEventQueue();
    expect(provider.allResults.map((r) => r.bookUrl), ['$_cnSite/book']);
    await search;
  });
}
