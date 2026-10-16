import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../../test_helper.dart';

/// 開 App 時書架骨架畫的本數：上次書架讀完時記下的本數。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BookDao bookDao;

  Book shelfBook(String url) =>
      Book(bookUrl: url, origin: 'o', name: url, isInBookshelf: true);

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
    await bookDao.upsertAll([
      for (var i = 0; i < books; i++) shelfBook('https://a.example/$i'),
    ]);
  }

  tearDown(() => GetIt.instance.reset());

  test('the count saved last time is there before the shelf loads', () async {
    final store = _CountingStore({'flutter.bookshelf_book_count': 7});
    await setUpShelf(store, books: 2);

    final provider = BookshelfProvider();
    addTearDown(provider.dispose);
    expect(provider.lastBookCount, 7);

    await provider.loadBooks();
    await pumpEventQueue();
    expect(provider.lastBookCount, 2);
    expect(store.saved['flutter.bookshelf_book_count'], 2);
  });

  test('a failed save is written again on the next load', () async {
    final store = _CountingStore({})..failNext = true;
    await setUpShelf(store, books: 3);

    // 建構時就會讀一次書架，這一次的寫入失敗。
    final provider = BookshelfProvider();
    addTearDown(provider.dispose);
    await pumpEventQueue();
    expect(store.saved, isNot(contains('flutter.bookshelf_book_count')));

    await provider.loadBooks();
    await pumpEventQueue();
    expect(store.saved['flutter.bookshelf_book_count'], 3);

    // 已經存好的本數不再重寫。
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
