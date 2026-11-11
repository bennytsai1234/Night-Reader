import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
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
      BookSource(bookSourceUrl: 'https://a.test', bookSourceName: '甲'),
      BookSource(bookSourceUrl: 'https://b.test', bookSourceName: '乙'),
    ]);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<SourceManagerProvider> loadedProvider() async {
    final provider = SourceManagerProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);
    while (provider.isLoading || provider.totalSourceCount == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return provider;
  }

  test('沒有校驗過時「沒有異常」不能選', () async {
    final provider = await loadedProvider();
    expect(provider.anySourceChecked, isFalse);
  });

  test('校驗過、全部正常沒有標記時「沒有異常」也能選', () async {
    await dao.upsert(
      BookSource(
        bookSourceUrl: 'https://a.test',
        bookSourceName: '甲',
        lastCheckTime: 1,
      ),
    );
    final provider = await loadedProvider();
    expect(provider.checkResultTags, isEmpty);
    expect(provider.anySourceChecked, isTrue);
  });
}
