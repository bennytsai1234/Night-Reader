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
      // 使用者自己的分組，名字和篩選選單固定的項目一樣。
      BookSource(
        bookSourceUrl: 'https://a.example',
        bookSourceName: '甲',
        bookSourceGroup: '已停用,全部',
      ),
      BookSource(
        bookSourceUrl: 'https://b.example',
        bookSourceName: '乙',
        enabled: false,
      ),
      BookSource(bookSourceUrl: 'https://c.example', bookSourceName: '丙'),
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

  test('分組和固定篩選同名：選分組只列這一組，固定篩選照舊', () async {
    final provider = await loaded();

    provider.setFilterGroup(SourceManagerProvider.groupFilter('已停用'));
    expect(shown(provider), ['甲']);
    provider.setFilterGroup('已停用');
    expect(shown(provider), ['乙']);

    provider.setFilterGroup(SourceManagerProvider.groupFilter('全部'));
    expect(shown(provider), ['甲']);
    expect(provider.showsManualOrder, isFalse);
    provider.setFilterGroup('全部');
    expect(shown(provider), unorderedEquals(['甲', '乙', '丙']));
  });

  test('改名、刪掉篩著的分組時篩選跟著換', () async {
    final provider = await loaded();
    provider.setFilterGroup(SourceManagerProvider.groupFilter('已停用'));
    await provider.renameGroup('已停用', '收藏');
    expect(provider.filterGroup, SourceManagerProvider.groupFilter('收藏'));
    expect(shown(provider), ['甲']);

    await provider.deleteGroup('收藏');
    expect(provider.filterGroup, '全部');
  });
}
