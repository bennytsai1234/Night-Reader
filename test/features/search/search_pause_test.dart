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

/// 記下送出的書源與搜尋是否結束。
class _RecordingCallback implements SearchModelCallback {
  final List<String> started = [];
  bool finished = false;

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
  void onSearchFinish({required bool isEmpty}) => finished = true;
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

  // 沒有搜尋網址的書源會立刻失敗，不連網就能看送出了哪些。
  final sources = [
    for (final name in ['甲', '乙', '丙'])
      BookSource(bookSourceUrl: 'https://$name.example', bookSourceName: name),
  ];

  /// 讓搜尋往前跑到停下來（等暫停或全部結束）。
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('a paused search sends no source until it resumes', () async {
    final callback = _RecordingCallback();
    final model = SearchModel(callback: callback)..pause();

    final search = model.searchSources(
      key: '夜讀',
      sources: sources,
      precisionSearch: false,
    );
    await settle();
    expect(callback.started, isEmpty);
    expect(callback.finished, isFalse);

    model.resume();
    await search;
    expect(callback.started, ['甲', '乙', '丙']);
    expect(callback.finished, isTrue);
  });

  test('leaving search while paused ends the waiting search', () async {
    final callback = _RecordingCallback();
    final model = SearchModel(callback: callback)..pause();

    final search = model.searchSources(
      key: '夜讀',
      sources: sources,
      precisionSearch: false,
    );
    await settle();
    model.dispose();

    await search.timeout(const Duration(seconds: 1));
    expect(callback.started, isEmpty);
  });
}
