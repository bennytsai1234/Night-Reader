import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/explore/explore_provider.dart';
import 'package:night_reader/features/explore/explore_show_provider.dart';

void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookSourceDao(db);
    getIt
      ..registerSingleton<BookSourceDao>(dao)
      ..registerSingleton<BookDao>(BookDao(db));
    await dao.upsert(
      BookSource(
        bookSourceUrl: 'https://s.example',
        bookSourceName: '書源',
        exploreUrl: 'https://s.example/explore',
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('a failed kinds load is retried on the next expand', () async {
    var calls = 0;
    final provider = ExploreProvider(
      sourceDao: dao,
      kindsLoader: (_, {source}) async {
        calls++;
        return calls == 1
            ? [const ExploreKind(title: 'ERROR:timeout', url: 'timeout')]
            : [const ExploreKind(title: '玄幻', url: 'https://k.example')];
      },
    );
    addTearDown(provider.dispose);
    await idle();

    await provider.toggleExpand(0);
    expect(provider.expandedKinds.single.title, startsWith('ERROR:'));

    await provider.toggleExpand(0);
    await provider.toggleExpand(0);
    expect(calls, 2);
    expect(provider.expandedKinds.single.title, '玄幻');
  });

  test('a category without paging stops after the first repeat', () async {
    var requests = 0;
    final provider = ExploreShowProvider(
      sourceUrl: 'https://s.example',
      exploreUrl: 'https://s.example/explore',
      exploreName: '玄幻',
      exploreLoader: (source, url, {page = 1, cancelToken}) async {
        requests++;
        return [
          for (var i = 0; i < 3; i++)
            SearchBook(
              bookUrl: 'https://s.example/book/$i',
              name: '書$i',
              origin: source.bookSourceUrl,
            ),
        ];
      },
    );
    addTearDown(provider.dispose);
    await idle();
    expect(provider.books, hasLength(3));

    await provider.loadMore();
    expect(provider.books, hasLength(3));
    expect(provider.hasMore, isFalse);

    await provider.loadMore();
    expect(requests, 2);
  });
}
