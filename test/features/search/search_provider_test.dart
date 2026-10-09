import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<SearchBookDao>(SearchBookDao(db))
      ..registerSingleton<SearchKeywordDao>(SearchKeywordDao(db));
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('a submitted search is in progress before the engine starts', () async {
    final provider = SearchProvider();
    addTearDown(provider.dispose);

    final searching = provider.search('斗羅');
    // 存歷史、讀書源清單的空檔裡不能被當成「沒有結果」。
    expect(provider.isSearching, isTrue);
    expect(provider.results, isEmpty);

    await searching;
    expect(provider.isSearching, isFalse);
  });

  test('the chosen search scope is remembered', () async {
    final provider = SearchProvider();
    addTearDown(provider.dispose);

    provider.updateSearchScope(SearchScope.fromGroups(['精選']));
    await Future<void>.delayed(Duration.zero);

    final restored = await SearchScope.load();
    expect(restored.displayNames, ['精選']);
  });
}
