import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/core/services/source_dedupe.dart';
import 'package:night_reader/core/sync/source_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

BookSource _s(
  String url, {
  int type = SourceType.book,
  bool enabled = true,
  int order = 0,
  String? group,
}) => BookSource(
  bookSourceUrl: url,
  bookSourceName: url,
  bookSourceType: type,
  enabled: enabled,
  customOrder: order,
  bookSourceGroup: group,
);

List<List<String>> _urls(List<List<BookSource>> groups) => [
  for (final group in groups) [for (final s in group) s.bookSourceUrl],
];

void main() {
  group('which sources are duplicates', () {
    test('the same site and the same kind; the rules do not matter', () {
      final groups = duplicateSourceGroups([
        _s('https://www.site.example#b')..searchUrl = '/s?q={{key}}',
        _s('https://www.site.example#a')..searchUrl = '/api/search',
        _s('https://www.other.example'),
      ]);

      expect(_urls(groups), [
        ['https://www.site.example#a', 'https://www.site.example#b'],
      ]);
    });

    test('a different kind, the mobile site, or a URL that is not a web '
        'address is not a duplicate', () {
      final groups = duplicateSourceGroups([
        _s('https://www.site.example'),
        _s('https://www.site.example#聽', type: SourceType.audio),
        _s('https://m.site.example'),
        _s('本地書源'),
        _s('本地書源#2'),
      ]);

      expect(groups, isEmpty);
    });

    test('the one kept is the healthy one, then the enabled one, then the '
        'one sorted first', () {
      final groups = duplicateSourceGroups([
        _s('https://site.example#broken', group: abnormalSourceGroupTag),
        _s('https://site.example#off', enabled: false),
        _s('https://site.example#late', order: 5),
        _s('https://site.example#early', order: 1),
      ]);

      expect(_urls(groups), [
        [
          'https://site.example#early',
          'https://site.example#late',
          'https://site.example#off',
          'https://site.example#broken',
        ],
      ]);
    });
  });

  group('with a database', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await GetIt.instance.reset();
      GetIt.instance.registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      );
      db = AppDatabase.forTesting(NativeDatabase.memory());
      registerDatabase(db);
      GetIt.instance.registerLazySingleton<CheckSourceService>(
        CheckSourceService.new,
      );
    });

    tearDown(() async {
      await db.close();
      await GetIt.instance.reset();
    });

    test('merging moves the books of the duplicates to the one kept', () async {
      await getIt<BookSourceDao>().upsertAll([
        _s('https://site.example#a'),
        _s('https://site.example#b', group: abnormalSourceGroupTag),
      ]);
      await getIt<BookDao>().upsert(
        Book(
          bookUrl: 'https://site.example/book/1',
          name: '甲書',
          origin: 'https://site.example#b',
        ),
      );

      expect(await mergeDuplicateSources(), 1);

      final left = await getIt<BookSourceDao>().getAllPart();
      expect(
        [for (final s in left) s.bookSourceUrl],
        ['https://site.example#a'],
      );
      final book = await getIt<BookDao>().getByUrl(
        'https://site.example/book/1',
      );
      expect(book!.origin, 'https://site.example#a');
    });

    test('opening the source manager merges duplicates and says so', () async {
      await getIt<BookSourceDao>().upsertAll([
        _s('https://site.example#a'),
        _s('https://site.example#b'),
        _s('https://other.example'),
      ]);

      final provider = SourceManagerProvider(entrance: Future<void>.value());
      addTearDown(provider.dispose);
      while (provider.isLoading || provider.totalSourceCount == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(provider.totalSourceCount, 2);
      expect(provider.lastMergedDuplicates, 1);
      expect(provider.duplicatesMerged.value, 1);
    });

    test('importing merges a new copy of a site already there', () async {
      await getIt<BookSourceDao>().upsert(_s('https://site.example'));

      final count = await SourceImportService().importSources([
        _s('https://site.example#新'),
      ]);

      expect(count, (imported: 1, merged: 1));
      expect(await getIt<BookSourceDao>().getAllPart(), hasLength(1));
      expect(sourceImportMessage(count), '成功匯入 1 個書源，合併了 1 個同網站重複的書源');
    });

    test('a merge made on the other phone is merged here too, books '
        'included, when this phone already has the one kept', () async {
      final dao = getIt<BookSourceDao>();
      await dao.upsertAll([
        _s('https://site.example#a'),
        _s('https://site.example#b'),
      ]);
      await getIt<BookDao>().upsert(
        Book(
          bookUrl: 'https://site.example/book/1',
          name: '甲書',
          origin: 'https://site.example#b',
        ),
      );
      final sync = SourceSync(prefs: getIt<SharedPreferences>());

      await sync.apply({
        'https://site.example#a': SourceSync.recordOf(
          _s('https://site.example#a'),
          movedFrom: ['https://site.example#b'],
        ),
        'https://site.example#b': const SyncRecord(
          time: 0,
          data: {},
          deleted: true,
        ),
      });

      expect(
        [for (final s in await dao.getAllPart()) s.bookSourceUrl],
        ['https://site.example#a'],
      );
      final book = await getIt<BookDao>().getByUrl(
        'https://site.example/book/1',
      );
      expect(book!.origin, 'https://site.example#a');
    });
  });
}
