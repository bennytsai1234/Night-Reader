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
import 'package:night_reader/core/models/source/source_site.dart';
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

    test('the site is the host: options after a comma, the user part before '
        '@ and the port do not count', () {
      expect(
        siteHost('https://www.site.example,{"webView":true}'),
        'www.site.example',
      );
      expect(siteHost('https://reader,one@alpha.example/x'), 'alpha.example');
      expect(siteHost('https://reader,two@beta.example/x'), 'beta.example');
      expect(siteHost('HTTPS://Site.Example:8080#a'), 'site.example');
      expect(siteHost('本地書源'), isNull);
    });

    test('an aggregate source and an ordinary one of the same site are not '
        'duplicates', () {
      final groups = duplicateSourceGroups([
        _s('https://site.example#a'),
        _s('https://site.example#b')..jsLib = 'function m(){ book.type = 64; }',
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

    test('nothing is merged while a batch job works on the sources', () async {
      await getIt<BookSourceDao>().upsertAll([
        _s('https://site.example#a'),
        _s('https://site.example#b'),
      ]);

      expect(await mergeDuplicateSources(idle: () => false), 0);
      expect(await getIt<BookSourceDao>().getAllPart(), hasLength(2));
    });

    test('only what was really merged is counted', () async {
      await getIt<BookSourceDao>().upsertAll([
        _s('https://site.example#a'),
        _s('https://site.example#b'),
      ]);

      expect(await mergeDuplicateSources(merge: (_, _) async => const []), 0);
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

    test('a merge from the other phone into a source new here keeps every '
        'merged source\'s books, the groups only this phone had, and the '
        'history of earlier merges', () async {
      final dao = getIt<BookSourceDao>();
      final prefs = getIt<SharedPreferences>();
      await dao.upsertAll([
        _s('https://site.example#b', group: '只在這台'),
        _s('https://site.example#c'),
      ]);
      await SourceMoves(prefs)
          .record(from: 'https://site.example#x', to: 'https://site.example#c');
      for (final (i, origin) in [
        'https://site.example#b',
        'https://site.example#c',
      ].indexed) {
        await getIt<BookDao>().upsert(
          Book(
            bookUrl: 'https://site.example/book/$i',
            name: '書$i',
            origin: origin,
          ),
        );
      }

      final applied = await SourceSync(prefs: prefs).apply({
        'https://site.example#a': SourceSync.recordOf(
          _s('https://site.example#a', group: '遠端'),
          movedFrom: ['https://site.example#b', 'https://site.example#c'],
        ),
        'https://site.example#b': const SyncRecord(
          time: 0,
          data: {},
          deleted: true,
        ),
        'https://site.example#c': const SyncRecord(
          time: 0,
          data: {},
          deleted: true,
        ),
      });

      expect(
        [for (final s in await dao.getAllPart()) s.bookSourceUrl],
        ['https://site.example#a'],
      );
      for (final i in [0, 1]) {
        final book = await getIt<BookDao>().getByUrl(
          'https://site.example/book/$i',
        );
        expect(book!.origin, 'https://site.example#a');
      }
      final kept = (await dao.getByUrl('https://site.example#a'))!;
      expect(kept.bookSourceGroup, contains('只在這台'));
      expect(
        SourceMoves(prefs).read()['https://site.example#a'],
        containsAll([
          'https://site.example#b',
          'https://site.example#c',
          'https://site.example#x',
        ]),
      );
      expect(
        applied['https://site.example#a']!.data['bookSourceGroup'],
        contains('只在這台'),
        reason: '送回同步的是合併後的樣子',
      );
    });
  });
}
