import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/explore/explore_provider.dart';

class _FakeSourceDao extends Fake implements BookSourceDao {
  final List<BookSource> sources;
  final StreamController<List<BookSource>> _controller =
      StreamController<List<BookSource>>.broadcast();

  _FakeSourceDao(this.sources);

  @override
  Future<List<BookSource>> getAllPart() async => List<BookSource>.from(sources);

  @override
  Stream<List<BookSource>> watchAllPart() => _controller.stream;

  @override
  Future<List<BookSource>> getDiscoveryPart() async =>
      List<BookSource>.from(sources);

  @override
  Stream<List<BookSource>> watchDiscoveryPart() async* {
    yield List<BookSource>.from(sources);
    yield* _controller.stream;
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('ExplorePage can be constructed', () {
    expect(() => const ExplorePage(), returnsNormally);
  });

  testWidgets('group menu all option clears selected group', (tester) async {
    final fakeDao = _FakeSourceDao([
      BookSource(
        bookSourceUrl: 'source://one',
        bookSourceName: '第一個書源',
        enabled: true,
        enabledExplore: true,
        exploreUrl: '最新::https://example.com/one',
        bookSourceGroup: '玄幻',
      ),
      BookSource(
        bookSourceUrl: 'source://two',
        bookSourceName: '第二個書源',
        enabled: true,
        enabledExplore: true,
        exploreUrl: '最新::https://example.com/two',
        bookSourceGroup: '都市',
      ),
    ]);
    addTearDown(fakeDao.dispose);
    getIt.registerLazySingleton<BookSourceDao>(() => fakeDao);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ExploreProvider(),
        child: const MaterialApp(home: ExplorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一個書源'), findsOneWidget);
    expect(find.text('第二個書源'), findsOneWidget);

    await tester.tap(find.byTooltip('按分組篩選'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('玄幻'));
    await tester.pumpAndSettle();

    expect(find.text('第一個書源'), findsOneWidget);
    expect(find.text('第二個書源'), findsNothing);

    await tester.tap(find.byTooltip('按分組篩選'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(find.text('第一個書源'), findsOneWidget);
    expect(find.text('第二個書源'), findsOneWidget);
  });
}
