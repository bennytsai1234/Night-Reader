import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「在此書源中搜尋」的範圍：照 Legado `SearchScope.getBookSourceParts`，有這
/// 個書源就用它，不看啟用與校驗標記；書源不在了退回全部啟用的書源。
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
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<List<String>> urlsIn(SearchScope scope) async => [
    for (final source in await scope.getBookSources()) source.bookSourceUrl,
  ];

  test(
    'a disabled source is still searched when it is the only one picked',
    () async {
      final off = BookSource(
        bookSourceUrl: 'https://off.example',
        bookSourceName: '停用的',
        enabled: false,
      );
      await dao.upsert(off);

      expect(await urlsIn(SearchScope.fromSource(off)), [off.bookSourceUrl]);
    },
  );

  test(
    'a source marked search-broken by the check is still searched',
    () async {
      final broken = BookSource(
        bookSourceUrl: 'https://broken.example',
        bookSourceName: '搜尋失效的',
      )..addGroup('$abnormalSourceGroupTag,$searchBrokenSourceGroupTag');
      await dao.upsert(broken);
      expect(broken.isSearchEnabledByRuntime, isFalse);

      expect(await urlsIn(SearchScope.fromSource(broken)), [
        broken.bookSourceUrl,
      ]);
    },
  );

  test('a source that is gone falls back to every enabled source', () async {
    final other = BookSource(
      bookSourceUrl: 'https://other.example',
      bookSourceName: '別的',
    );
    await dao.upsert(other);
    final gone = BookSource(
      bookSourceUrl: 'https://gone.example',
      bookSourceName: '刪掉的',
    );
    final scope = SearchScope.fromSource(gone);

    expect(await urlsIn(scope), [other.bookSourceUrl]);
    expect(scope.isAll, isTrue);
  });
}
