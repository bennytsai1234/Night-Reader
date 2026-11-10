import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBookDao extends Fake implements BookDao {
  _FakeBookDao(this.shelf);

  final List<Book> shelf;

  @override
  Future<List<Book>> getInBookshelf() async => List.of(shelf);
}

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

Book _book(String name, int type) =>
    Book(bookUrl: 'u-$name', origin: 'o', name: name, type: type)
      ..isInBookshelf = true;

void main() {
  late BookshelfProvider provider;

  Future<void> pumpShelf(WidgetTester tester, List<Book> shelf) async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    GetIt.instance
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(_FakeBookDao(shelf))
      ..registerSingleton<BookSourceDao>(_FakeBookSourceDao())
      ..registerSingleton<ChapterDao>(_FakeChapterDao());
    provider = BookshelfProvider(
      keepBookDownloaded: (url, {hasNewChapters = false}) async {},
    );
    addTearDown(() async {
      provider.dispose();
      await GetIt.instance.reset();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: ChangeNotifierProvider<BookshelfProvider>.value(
          value: provider,
          child: const BookshelfPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('整理書架'));
    await tester.pumpAndSettle();
  }

  testWidgets('書架上只有一種書時整理選單沒有篩選', (tester) async {
    await pumpShelf(tester, [_book('甲', 0), _book('乙', 0)]);
    await openMenu(tester);
    expect(find.text('漫畫'), findsNothing);
    expect(find.text('全部'), findsNothing);
  });

  testWidgets('選漫畫只畫漫畫，選全部畫回全部', (tester) async {
    await pumpShelf(tester, [_book('小說甲', 0), _book('漫畫乙', 2)]);
    expect(find.text('小說甲'), findsOneWidget);

    await openMenu(tester);
    expect(find.text('有聲書'), findsOneWidget);
    await tester.tap(find.text('漫畫'));
    await tester.pumpAndSettle();
    expect(provider.activeKindFilter, BookSourceKind.comic);
    expect(find.text('漫畫乙'), findsOneWidget);
    expect(find.text('小說甲'), findsNothing);

    await openMenu(tester);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('小說甲'), findsOneWidget);
    expect(find.text('漫畫乙'), findsOneWidget);
  });

  testWidgets('選的那一類沒書了就回到全部', (tester) async {
    await pumpShelf(tester, [
      _book('小說甲', 0),
      _book('漫畫乙', 2),
      _book('有聲丙', 1),
    ]);
    provider.setKindFilter(BookSourceKind.comic);
    provider.books = [
      for (final b in provider.books)
        if (b.name != '漫畫乙') b,
    ];
    expect(provider.activeKindFilter, isNull);
    expect(provider.shownBooks, hasLength(2));
  });
}
