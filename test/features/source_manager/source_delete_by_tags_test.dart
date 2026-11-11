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
      BookSource(bookSourceUrl: 'https://novel.test', bookSourceName: '小說甲'),
      BookSource(
        bookSourceUrl: 'https://novel-broken.test',
        bookSourceName: '小說乙',
        bookSourceGroup: '常用,$abnormalSourceGroupTag',
      ),
      BookSource(
        bookSourceUrl: 'https://comic.test',
        bookSourceName: '漫畫甲',
        bookSourceType: 2,
        bookSourceGroup: '常用',
      ),
      BookSource(
        bookSourceUrl: 'https://audio.test',
        bookSourceName: '有聲甲',
        bookSourceType: 1,
      ),
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

  String label(SourceTag tag) => tag.kind?.sourceLabel ?? tag.group!;

  test('列出類別、校驗標記、分組三種標籤與各有幾個', () async {
    final provider = await loadedProvider();
    expect(
      {for (final t in provider.sourceTagCounts) label(t.tag): t.count},
      {'小說源': 2, '漫畫源': 1, '有聲源': 1, abnormalSourceGroupTag: 1, '常用': 2},
    );
  });

  test('刪掉帶任一個勾選標籤的書源，其他留下', () async {
    final provider = await loadedProvider();
    final tags = {
      (kind: BookSourceKind.audio, group: null),
      (kind: null, group: abnormalSourceGroupTag),
    };
    expect(provider.countSourcesWithTags(tags), 2);

    expect(await provider.deleteSourcesWithTags(tags), 2);
    expect((await dao.getAllPart()).map((s) => s.bookSourceName).toSet(), {
      '小說甲',
      '漫畫甲',
    });
  });
}
