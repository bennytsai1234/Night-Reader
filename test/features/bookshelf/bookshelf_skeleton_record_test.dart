import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/bookshelf/provider/bookshelf_logic_mixin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../../test_helper.dart';

/// 開 App 時書架骨架照著畫的紀錄：上次書架讀完時的本數與前面幾本的書名、
/// 作者。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookDao bookDao;

  Book shelfBook(int i) => Book(
    bookUrl: 'https://a.example/$i',
    origin: 'o',
    name: '書$i',
    author: i.isEven ? '作者$i' : '',
    isInBookshelf: true,
  );

  const key = 'flutter.bookshelf_skeleton';
  Map<String, dynamic>? saved(_CountingStore store) => store.saved[key] == null
      ? null
      : jsonDecode(store.saved[key]! as String) as Map<String, dynamic>;

  /// 依 [store] 準備偏好設定與記憶體資料庫，書架上放 [books] 本書。
  Future<void> setUpShelf(_CountingStore store, {required int books}) async {
    await GetIt.instance.reset();
    setupTestDI();
    SharedPreferencesStorePlatform.instance = store;
    // SharedPreferences 只讀一次平台的資料；每個測試換新的平台時要重讀。
    SharedPreferences.resetStatic();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    bookDao = BookDao(db);
    GetIt.instance
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(bookDao)
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ChapterDao>(ChapterDao(db));
    await bookDao.upsertAll([for (var i = 0; i < books; i++) shelfBook(i)]);
  }

  tearDown(() => GetIt.instance.reset());

  test('what was saved last time is there before the shelf loads', () async {
    final store = _CountingStore({
      key: jsonEncode({
        'count': 7,
        'books': [
          ['舊書', '舊作者'],
        ],
      }),
    });
    await setUpShelf(store, books: 2);

    final provider = BookshelfProvider();
    addTearDown(provider.dispose);
    expect(provider.lastBookCount, 7);
    expect(provider.lastShelfTitles, [(name: '舊書', author: '舊作者')]);

    await provider.loadBooks();
    await pumpEventQueue();
    expect(provider.lastBookCount, 2);
    expect(saved(store), {
      'count': 2,
      'books': [
        ['書0', '作者0'],
        ['書1', ''],
      ],
    });
  });

  test('only the first books that can fit on a screen are kept', () async {
    final store = _CountingStore({});
    await setUpShelf(store, books: 40);

    final provider = BookshelfProvider();
    addTearDown(provider.dispose);
    await provider.loadBooks();
    await pumpEventQueue();
    expect(saved(store)!['count'], 40);
    expect(
      (saved(store)!['books'] as List).length,
      BookshelfLogicMixin.skeletonTitleLimit,
    );
  });

  test('an unreadable record falls back to filling the screen', () async {
    final store = _CountingStore({key: 'not json'});
    await setUpShelf(store, books: 1);

    final provider = BookshelfProvider();
    addTearDown(provider.dispose);
    expect(provider.lastBookCount, isNull);
    expect(provider.lastShelfTitles, isEmpty);
  });

  test('a failed save is written again on the next load', () async {
    final store = _CountingStore({})..failNext = true;
    await setUpShelf(store, books: 3);

    // 建構時就會讀一次書架，這一次的寫入失敗。
    final provider = BookshelfProvider();
    addTearDown(provider.dispose);
    await pumpEventQueue();
    expect(store.saved, isNot(contains(key)));

    await provider.loadBooks();
    await pumpEventQueue();
    expect(saved(store)!['count'], 3);

    // 已經存好的紀錄不再重寫。
    final writes = store.writes;
    await provider.loadBooks();
    await pumpEventQueue();
    expect(store.writes, writes);
  });
}

/// 記下寫入次數；[failNext] 時下一次寫入回報失敗、不存。
class _CountingStore extends SharedPreferencesStorePlatform {
  _CountingStore(Map<String, Object> initial) : saved = {...initial};

  final Map<String, Object> saved;
  int writes = 0;
  bool failNext = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes++;
    if (failNext) {
      failNext = false;
      return false;
    }
    saved[key] = value;
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => {...saved};

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async => {
    for (final entry in saved.entries)
      if (entry.key.startsWith(parameters.filter.prefix))
        entry.key: entry.value,
  };

  @override
  Future<bool> remove(String key) async => saved.remove(key) != null;

  @override
  Future<bool> clear() async {
    saved.clear();
    return true;
  }
}
