import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/sync/settings_sync.dart';
import 'package:night_reader/shared/widgets/book/book_cover_widget.dart';
import 'package:night_reader/shared/widgets/book/default_book_cover.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/shared/shelf_look.dart';
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

void main() {
  const cover = 'https://s.example/cover.jpg';
  final books = [Book(bookUrl: 'u1', origin: 'o', name: '甲', coverUrl: cover)]
    ..forEach((book) => book.isInBookshelf = true);

  late BookshelfProvider provider;

  Future<void> setUpShelf(
    Map<String, Object> prefs, {
    List<Book>? shelf,
  }) async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues(prefs);
    GetIt.instance
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(_FakeBookDao(shelf ?? books))
      ..registerSingleton<BookSourceDao>(_FakeBookSourceDao())
      ..registerSingleton<ChapterDao>(_FakeChapterDao());
    provider = BookshelfProvider(
      keepBookDownloaded: (url, {hasNewChapters = false}) async {},
    );
  }

  tearDown(() async {
    provider.dispose();
    UnifiedCovers.enabled.value = UnifiedCovers.defaultEnabled;
    ShelfLook.mergedList.value = false;
    await GetIt.instance.reset();
  });

  Future<void> pumpShelf(WidgetTester tester) async {
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

  String? tileCover(WidgetTester tester) =>
      tester.widget<BookCoverWidget>(find.byType(BookCoverWidget)).coverUrl;

  testWidgets('沒設定過時統一封面開著', (tester) async {
    await setUpShelf({});
    await pumpShelf(tester);

    expect(provider.unifiedCovers, isTrue);
    expect(tileCover(tester), isNull);
  });

  testWidgets('統一封面打勾後書架改畫預設封面，取消後換回書的封面', (tester) async {
    await setUpShelf({'bookshelf_unified_covers': false});
    await pumpShelf(tester);
    expect(tileCover(tester), cover);

    await tester.tap(find.byTooltip('整理書架'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('統一封面'));
    await tester.pumpAndSettle();

    expect(provider.unifiedCovers, isTrue);
    expect(tileCover(tester), isNull);
    expect(
      GetIt.instance<SharedPreferences>().getBool('bookshelf_unified_covers'),
      isTrue,
    );

    provider.setUnifiedCovers(false);
    await tester.pumpAndSettle();
    expect(tileCover(tester), cover);
  });

  testWidgets('列表併成一面在整理選單切換並存下來，另一台同步過來時跟著換', (tester) async {
    await setUpShelf({'bookshelf_is_grid': false});
    await pumpShelf(tester);
    expect(ShelfLook.mergedList.value, isFalse);

    await tester.tap(find.byTooltip('整理書架'));
    await tester.pumpAndSettle();
    expect(find.textContaining('試用'), findsNothing);
    await tester.tap(find.text('列表併成一面'));
    await tester.pumpAndSettle();

    final prefs = GetIt.instance<SharedPreferences>();
    expect(ShelfLook.mergedList.value, isTrue);
    expect(prefs.getBool(PreferKey.shelfMergedList), isTrue);
    expect(SettingsSync.keys, contains(PreferKey.shelfMergedList));

    // 另一台改回預設（偏好設定移除），同步套用過來。
    await prefs.remove(PreferKey.shelfMergedList);
    SettingsSync.applied.value++;
    await tester.pumpAndSettle();
    expect(ShelfLook.mergedList.value, isFalse);
  });

  testWidgets('重開 App 時沿用上次的統一封面設定', (tester) async {
    await setUpShelf({'bookshelf_unified_covers': true});
    await pumpShelf(tester);

    expect(provider.unifiedCovers, isTrue);
    expect(tileCover(tester), isNull);
  });

  testWidgets('同名、作者不同的兩本書，預設封面各照自己在書架上的位置', (tester) async {
    final sameName = [
      Book(bookUrl: 'a', origin: 'o', name: '同名書', author: '甲'),
      Book(bookUrl: 'b', origin: 'o', name: '同名書', author: '乙'),
    ]..forEach((book) => book.isInBookshelf = true);
    await setUpShelf({}, shelf: sameName);
    await pumpShelf(tester);

    final tiles = tester
        .widgetList<BookCoverWidget>(find.byType(BookCoverWidget))
        .map((cover) => cover.bookUrl)
        .toList();
    expect(tiles, unorderedEquals(['a', 'b']));
    expect({ShelfLook.positionOf('a'), ShelfLook.positionOf('b')}, {0.0, 1.0});
  });
}
