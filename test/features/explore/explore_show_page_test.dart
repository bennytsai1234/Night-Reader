import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/bookshelf_state_tracker.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/features/explore/explore_book_details.dart';
import 'package:night_reader/features/explore/explore_show_page.dart';
import 'package:night_reader/features/explore/explore_show_provider.dart';
import 'package:night_reader/features/explore/widgets/explore_book_item.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';

const _origin = 'https://s.example';

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<BookSource?> getByUrl(String url) async =>
      BookSource(bookSourceUrl: _origin, bookSourceName: '書源');
}

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<List<Book>> getInBookshelf() async => const [];
}

void main() {
  setUp(() {
    if (getIt.isRegistered<BookSourceDao>()) getIt.unregister<BookSourceDao>();
    getIt.registerSingleton<BookSourceDao>(_FakeSourceDao());
  });
  tearDown(() => getIt.unregister<BookSourceDao>());

  SearchBook listed(int i) => SearchBook(
    bookUrl: '$_origin/book/$i',
    name: '書$i',
    // 第 2 本清單上沒有作者，也沒有分類與字數。
    author: i == 2 ? null : '作者$i',
    intro: '這是第$i本書的簡介。',
    latestChapterTitle: '第${100 + i}章',
    origin: _origin,
  );

  final calls = <String, Completer<ExploreBookExtras>>{};
  setUp(calls.clear);

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: ChangeNotifierProvider(
          create: (_) => ExploreShowProvider(
            sourceUrl: _origin,
            exploreUrl: '$_origin/category/1',
            exploreName: '玄幻',
            bookshelfTracker: BookshelfStateTracker(bookDao: _FakeBookDao()),
            exploreLoader: (source, url, {page, cancelToken}) async =>
                page == 1 ? [for (var i = 0; i < 30; i++) listed(i)] : [],
            extrasLoader: (source, book, {cancelToken}) =>
                (calls[book.bookUrl] = Completer()).future,
          ),
          child: const ExploreShowView(exploreName: '玄幻'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(int i) => find.ancestor(
    of: find.text('書$i'),
    matching: find.byType(ExploreBookItem),
  );

  testWidgets('rows show the cover and word count fetched from the detail '
      'page, without an intro', (tester) async {
    await pumpList(tester);
    expect(find.text('這是第0本書的簡介。'), findsNothing);
    expect(find.text('作者0'), findsOneWidget);

    // 只取畫出來的那幾本，同時最多四本。
    expect(calls, hasLength(ExploreBookDetails.maxConcurrent));
    expect(calls.keys, everyElement(startsWith('$_origin/book/')));

    final height = tester.getSize(row(0)).height;
    final otherRow = tester.widget(row(1));
    calls['$_origin/book/0']!.complete((
      coverUrl: '$_origin/cover/0.jpg',
      wordCount: '12.3萬字',
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('作者0 · 12.3萬字'), findsOneWidget);
    expect(
      tester
          .widget<BookCoverWidget>(
            find.descendant(of: row(0), matching: find.byType(BookCoverWidget)),
          )
          .coverUrl,
      '$_origin/cover/0.jpg',
    );
    // 補到的那一列版面不動，其他列沒有重建。
    expect(tester.getSize(row(0)).height, height);
    expect(tester.widget(row(1)), same(otherRow));
    await tester.pumpAndSettle();
  });

  testWidgets('a row with nothing for the meta line still keeps its place', (
    tester,
  ) async {
    await pumpList(tester);
    final before = tester.getSize(row(2)).height;
    calls['$_origin/book/2']!.complete((coverUrl: '', wordCount: '850字'));
    await tester.pumpAndSettle();
    expect(find.text('850字'), findsOneWidget);
    expect(tester.getSize(row(2)).height, before);
  });
}
