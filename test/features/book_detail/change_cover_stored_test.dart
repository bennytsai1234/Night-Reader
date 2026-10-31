import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/book_detail/change_cover_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _source = 'https://cover.example';
const _disabled = 'https://disabled.example';

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
}
