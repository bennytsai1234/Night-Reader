import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';
import 'package:night_reader/features/book_detail/change_cover_provider.dart';
import 'package:night_reader/features/book_detail/change_cover_sheet.dart';
import 'package:night_reader/features/book_detail/widgets/cover/cover_grid_item.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

class _FakeBookDao extends Fake implements BookDao {
  Book? book;

  @override
  Future<Book?> getByUrl(String url) async => book;

  @override
  Future<void> upsert(Book value) async {
    book = value.copyWith();
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {
  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async => const [];
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<BookSource?> getByUrl(String url) async => null;

  @override
  Future<List<BookSource>> getEnabled() async => const [];
}

class _FakeSearchBookDao extends Fake implements SearchBookDao {
  @override
  Future<List<SearchBook>> getEnabledHasCover(
    String name,
    String author,
  ) async {
    return [
      SearchBook(
        bookUrl: 'stored-without-extra-grid-item',
        name: name,
        author: author,
        origin: 'source://theme',
        originName: '主題測試書源',
      ),
    ];
  }
}

class _FakeCoverStorage extends Fake implements BookCoverStorageService {
  @override
  Future<void> ensureDisplayCoverStored(Book book) async {}
}

AggregatedSearchBook _coverResult() {
  return AggregatedSearchBook(
    book: SearchBook(
      bookUrl: 'https://example.com/book',
      name: '主題測試書',
      author: '作者',
      origin: 'source://theme',
      originName: '主題測試書源',
      coverUrl: 'https://example.com/broken.jpg',
    ),
    sources: const ['主題測試書源'],
  );
}

void main() {
  setUp(() {
    GetIt.instance.registerLazySingleton<BookDao>(() => _FakeBookDao());
    GetIt.instance.registerLazySingleton<ChapterDao>(() => _FakeChapterDao());
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => _FakeSourceDao());
    GetIt.instance.registerLazySingleton<SearchBookDao>(
      () => _FakeSearchBookDao(),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  for (final brightness in Brightness.values) {
    testWidgets('ChangeCoverSheet 使用 ${brightness.name} surface', (
      tester,
    ) async {
      final colorScheme = ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      );
      final detailProvider = BookDetailProvider(
        _coverResult(),
        sourceDao: _FakeSourceDao(),
        coverStorage: _FakeCoverStorage(),
      );
      final coverProvider = ChangeCoverProvider();
      addTearDown(detailProvider.dispose);
      addTearDown(coverProvider.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BookDetailProvider>.value(
              value: detailProvider,
            ),
            ChangeNotifierProvider<ChangeCoverProvider>.value(
              value: coverProvider,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(colorScheme: colorScheme),
            home: const Scaffold(
              body: ChangeCoverSheet(bookName: '主題測試書', author: '作者'),
            ),
          ),
        ),
      );
      await tester.pump();

      final sheetSurface = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ChangeCoverSheet),
              matching: find.byType(Container),
            ),
          )
          .firstWhere((container) {
            final decoration = container.decoration;
            return decoration is BoxDecoration &&
                decoration.borderRadius == AppRadius.topSheetXl;
          });
      final decoration = sheetSurface.decoration! as BoxDecoration;
      expect(decoration.color, colorScheme.surface);
    });
  }

  testWidgets('封面破圖背景與 icon 保持對比', (tester) async {
    final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: colorScheme),
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 220,
            child: CoverGridItem(result: _coverResult()),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    final imageContext = tester.element(find.byType(CachedNetworkImage));
    final errorContainer =
        image.errorWidget!(imageContext, 'broken', StateError('broken'))
            as Container;
    final icon = errorContainer.child! as Icon;

    expect(errorContainer.color, colorScheme.surfaceContainerHighest);
    expect(icon.color, colorScheme.onSurfaceVariant);
    expect(errorContainer.color, isNot(icon.color));
  });
}
