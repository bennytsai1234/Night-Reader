import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/search_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 記下每個書源送出的順序。
class _RecordingCallback implements SearchModelCallback {
  final List<String> started = [];

  @override
  void onSearchProgress({
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  }) {
    for (final name in waitingSources) {
      if (!started.contains(name)) started.add(name);
    }
  }

  @override
  void onSearchStart() {}
  @override
  void onSearchSuccess(List<SearchBook> searchBooks) {}
  @override
  void onSearchFailure(SearchFailure failure) {}
  @override
  void onSearchFinish({required bool isEmpty}) {}
}

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<SearchBookDao>(SearchBookDao(db));
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('sources that answered fast last time are searched first; unmeasured '
      'ones follow in the user order', () async {
    // 沒有搜尋網址的書源會立刻失敗，不連網就能看送出順序。
    BookSource source(String name, int order, int respondTime) => BookSource(
      bookSourceUrl: 'https://$name.example',
      bookSourceName: name,
      customOrder: order,
    )..respondTime = respondTime;

    final callback = _RecordingCallback();
    await SearchModel(callback: callback).searchSources(
      key: '夜讀',
      sources: [
        source('未量甲', 0, 180000),
        source('慢', 1, 5000),
        source('舊校驗', 2, 0),
        source('快', 3, 200),
      ],
      precisionSearch: false,
    );

    expect(callback.started, ['快', '慢', '未量甲', '舊校驗']);
  });
}
