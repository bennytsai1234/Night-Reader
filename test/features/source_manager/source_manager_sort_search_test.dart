import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
    GetIt.instance.registerLazySingleton<CheckSourceService>(
      CheckSourceService.new,
    );
    await dao.upsertAll([
      BookSource(
        bookSourceUrl: 'https://old.example',
        bookSourceName: '甲',
        bookSourceGroup: '武俠',
        lastUpdateTime: 100,
      ),
      BookSource(
        bookSourceUrl: 'https://new.example',
        bookSourceName: '乙',
        bookSourceGroup: '都市',
        lastUpdateTime: 300,
      ),
      BookSource(
        bookSourceUrl: 'https://middle.example',
        bookSourceName: '丙',
        lastUpdateTime: 200,
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<SourceManagerProvider> loaded() async {
    final provider = SourceManagerProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);
    while (provider.isLoading || provider.totalSourceCount == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return provider;
  }

  List<String> shown(SourceManagerProvider p) => [
    for (final s in p.sources) s.bookSourceName,
  ];

  test('按更新時間排序新的在前，倒序時舊的在前', () async {
    final provider = await loaded();

    provider.setSortMode(4);
    expect(shown(provider), ['乙', '丙', '甲']);

    provider.toggleSortDesc();
    expect(shown(provider), ['甲', '丙', '乙']);
  });

  test('搜尋框也比對分組名稱', () async {
    final provider = await loaded();

    provider.setSearchQuery('武俠');
    expect(shown(provider), ['甲']);

    provider.setSearchQuery('都市');
    expect(shown(provider), ['乙']);
  });
}
