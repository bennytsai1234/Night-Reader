import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

BookSource _source(
  String url, {
  int order = 0,
  String searchUrl = '/s?q={{key}}',
}) => BookSource(
  bookSourceUrl: url,
  bookSourceName: url,
  searchUrl: searchUrl,
  customOrder: order,
);

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: '等不到');
}

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
    registerDatabase(db);
    dao = getIt<BookSourceDao>();
    GetIt.instance.registerLazySingleton<CheckSourceService>(
      CheckSourceService.new,
    );
    await dao.upsert(_source('https://a.example#a'));
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('closing the editor after a save keeps the source that was just '
      'edited, and its rules, when duplicates merge', () async {
    final provider = SourceManagerProvider(entrance: Future<void>.value());
    addTearDown(provider.dispose);
    await _until(() => !provider.isLoading && provider.totalSourceCount == 1);

    // 編輯頁開著時，同步或匯入帶進同網站的重複書源：照原本的規則會留下
    // 網址在前面的 #a。
    await dao.upsert(_source('https://a.example#b', order: 1));
    expect(
      (await provider.beginEditing('https://a.example#b'))?.bookSourceUrl,
      'https://a.example#b',
    );

    // 使用者改了搜尋規則、存檔，關掉編輯頁。
    await dao.upsert(
      _source('https://a.example#b', order: 1, searchUrl: '/new?q={{key}}'),
    );
    await provider.endEditing('https://a.example#b', changed: true);

    expect(provider.allSources.map((s) => s.bookSourceUrl), [
      'https://a.example#b',
    ]);
    expect(
      (await dao.getByUrl('https://a.example#b'))!.searchUrl,
      '/new?q={{key}}',
    );
    expect(await dao.getByUrl('https://a.example#a'), isNull);
  });
}
