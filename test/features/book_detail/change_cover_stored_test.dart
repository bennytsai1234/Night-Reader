import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/book_detail/change_cover_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _source = 'https://cover.example';
const _disabled = 'https://disabled.example';
const _searchable = 'https://search.example';

/// 有封面規則的書源搜尋時回 [results]，記下被搜了幾次。
class _CoverSite extends BookSourceService {
  _CoverSite(this.results);

  final List<SearchBook> results;
  int searches = 0;

  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    searches++;
    return results;
  }
}

SearchBook _found(String name, String? author, String cover) => SearchBook(
  bookUrl: '$_searchable/$cover',
  name: name,
  author: author,
  coverUrl: cover,
  origin: _searchable,
  originName: '搜尋站',
);

void main() {
  late AppDatabase db;

  setUpAll(() {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final sourceDao = BookSourceDao(db);
    GetIt.instance
      ..registerSingleton<BookSourceDao>(sourceDao)
      ..registerSingleton<SearchBookDao>(SearchBookDao(db));
    await sourceDao.upsert(
      BookSource(bookSourceUrl: _source, bookSourceName: '封面站'),
    );
    await sourceDao.upsert(
      BookSource(
        bookSourceUrl: _disabled,
        bookSourceName: '停用的站',
        enabled: false,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<void> store(
    String name,
    String? author,
    String cover, {
    String origin = _source,
  }) => SearchBookDao(db).upsert(
    SearchBook(
      bookUrl: '$origin/$cover',
      name: name,
      author: author,
      coverUrl: cover,
      origin: origin,
      originName: origin,
    ),
  );

  Future<List<String?>> storedCovers(String name, String author) async {
    final provider = ChangeCoverProvider();
    addTearDown(provider.dispose);
    await provider.init(name, author);
    return [for (final item in provider.covers.skip(1)) item.book.coverUrl];
  }

  test('covers found before come back the next time the panel opens', () async {
    await store('甲書', null, 'no-author.jpg');
    await store('甲書', '乙作者', 'same-author.jpg');
    await store('甲書', ' 乙作者 ', 'spaced-author.jpg');
    await store('甲書', '別人', 'other-author.jpg');
    await store('甲書', '乙作者', 'disabled.jpg', origin: _disabled);
    await store('甲書', '乙作者', '');

    expect(
      await storedCovers('甲書', '乙作者'),
      unorderedEquals([
        'no-author.jpg',
        'same-author.jpg',
        'spaced-author.jpg',
      ]),
    );
    expect(
      await storedCovers('甲書', ''),
      unorderedEquals([
        'no-author.jpg',
        'same-author.jpg',
        'spaced-author.jpg',
        'other-author.jpg',
      ]),
      reason: '這本書沒寫作者時只比書名',
    );
  });

  test('a cover stored under the other script of the name is found', () async {
    await store('劍來', '烽火戲諸侯', 'traditional.jpg');

    expect(await storedCovers('剑来', '烽火戏诸侯'), ['traditional.jpg']);
  });

  group('covers found by searching', () {
    setUp(
      () => BookSourceDao(db).upsert(
        BookSource(
          bookSourceUrl: _searchable,
          bookSourceName: '搜尋站',
          ruleSearch: SearchRule(coverUrl: 'img@src'),
        ),
      ),
    );

    test('are read back the next time without searching again', () async {
      final site = _CoverSite([
        _found('甲書', '乙作者', 'same.jpg'),
        _found('甲書', null, 'no-author.jpg'),
        _found('甲書', '乙作者', 'same.jpg'),
        _found('甲書', '別人', 'other.jpg'),
        _found('甲 書', '乙作者', 'spaced-name.jpg'),
      ]);
      final first = ChangeCoverProvider(service: site);
      addTearDown(first.dispose);
      await first.init('甲書', '乙作者');
      final found = [for (final c in first.covers.skip(1)) c.book.coverUrl];
      expect(found, unorderedEquals(['same.jpg', 'no-author.jpg']));
      expect(site.searches, 1);

      final again = _CoverSite(const []);
      final second = ChangeCoverProvider(service: again);
      addTearDown(second.dispose);
      await second.init('甲書', '乙作者');
      expect(
        [for (final c in second.covers.skip(1)) c.book.coverUrl],
        unorderedEquals(found),
        reason: '搜到時收下的，下次都讀得回來',
      );
      expect(again.searches, 0, reason: '有本地紀錄就不再搜尋');
    });

    test('closing the panel while it loads starts no search', () async {
      final site = _CoverSite([_found('甲書', '乙作者', 'same.jpg')]);
      final provider = ChangeCoverProvider(service: site);
      final loading = provider.init('甲書', '乙作者');
      provider.dispose();
      await loading;

      expect(site.searches, 0);
      expect(await storedCovers('甲書', '乙作者'), isEmpty);
    });
  });
}
