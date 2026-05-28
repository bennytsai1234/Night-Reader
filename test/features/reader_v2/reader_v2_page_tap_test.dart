import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/constant/page_anim.dart';
import 'package:reader/core/constant/prefer_key.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:reader/features/reader_v2/render/reader_v2_tile_layer.dart';
import 'package:reader/features/reader_v2/shell/reader_v2_page.dart';
import 'package:reader/features/reader_v2/viewport/scroll_reader_v2_viewport.dart';
import 'package:reader/features/reader_v2/viewport/slide_reader_v2_viewport.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  for (final mode in _pageTurnModes) {
    group(mode.label, () {
      testWidgets('reading area tap opens and closes controls', (tester) async {
        await _pumpReaderPage(tester, pageTurnMode: mode.pageTurnMode);
        final tapPosition = tester.getCenter(
          _viewportFinder(mode.pageTurnMode),
        );

        expect(_controlsVisible(tester), isFalse);

        await _tapAtAndPump(tester, tapPosition);
        expect(_controlsVisible(tester), isTrue);

        await _tapAtAndPump(tester, tapPosition);
        expect(_controlsVisible(tester), isFalse);
      });

      testWidgets('reading area slight move does not open controls', (
        tester,
      ) async {
        await _pumpReaderPage(tester, pageTurnMode: mode.pageTurnMode);
        final tapPosition = tester.getCenter(
          _viewportFinder(mode.pageTurnMode),
        );

        final gesture = await tester.startGesture(tapPosition);
        await gesture.moveBy(const Offset(4, 3));
        await gesture.up();
        await _pumpScheduledReaderFrames(tester);

        expect(_controlsVisible(tester), isFalse);
      });
    });
  }
}

const _pageTurnModes = <_PageTurnMode>[
  _PageTurnMode(label: 'slide mode', pageTurnMode: PageAnim.slide),
  _PageTurnMode(label: 'scroll mode', pageTurnMode: PageAnim.scroll),
];

Future<void> _pumpReaderPage(
  WidgetTester tester, {
  required int pageTurnMode,
}) async {
  final book = _book();
  final chapters = _chapters(book.bookUrl);
  SharedPreferences.setMockInitialValues(<String, Object>{
    PreferKey.readerPageTurnMode: pageTurnMode,
  });
  getIt.registerLazySingleton<BookDao>(() => _FakeBookDao());
  getIt.registerLazySingleton<ChapterDao>(() => _FakeChapterDao(chapters));
  getIt.registerLazySingleton<BookSourceDao>(() => _FakeSourceDao());

  await tester.pumpWidget(
    MaterialApp(home: ReaderV2Page(book: book, initialChapters: chapters)),
  );
  await _pumpReaderContentReady(tester, pageTurnMode: pageTurnMode);
}

Future<void> _pumpReaderContentReady(
  WidgetTester tester, {
  required int pageTurnMode,
}) async {
  final expectedViewport = _viewportFinder(pageTurnMode);
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (expectedViewport.evaluate().isNotEmpty &&
        find.byType(ReaderV2TileLayer).evaluate().isNotEmpty) {
      await _pumpScheduledReaderFrames(tester);
      return;
    }
  }
  fail('ReaderV2Page did not render readable content');
}

Future<void> _tapAtAndPump(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await _pumpScheduledReaderFrames(tester);
}

Future<void> _pumpScheduledReaderFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Finder _viewportFinder(int pageTurnMode) {
  return pageTurnMode == PageAnim.scroll
      ? find.byType(ScrollReaderV2Viewport)
      : find.byType(SlideReaderV2Viewport);
}

bool _controlsVisible(WidgetTester tester) {
  return tester
      .widget<ReaderV2TopMenu>(find.byType(ReaderV2TopMenu))
      .controlsVisible;
}

Book _book() {
  return Book(
    bookUrl: 'test://reader-page',
    origin: 'local',
    originName: '本地',
    name: '測試書',
  );
}

List<BookChapter> _chapters(String bookUrl) {
  return List<BookChapter>.generate(3, (index) {
    return BookChapter(
      index: index,
      bookUrl: bookUrl,
      title: '第${index + 1}章',
      content: List<String>.filled(
        24,
        '這是第${index + 1}章的測試內容，用於建立完整閱讀頁點擊測試所需的文字。',
      ).join('\n\n'),
    );
  });
}

class _PageTurnMode {
  const _PageTurnMode({required this.label, required this.pageTurnMode});

  final String label;
  final int pageTurnMode;
}

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {}
}

class _FakeChapterDao extends Fake implements ChapterDao {
  _FakeChapterDao(this.storedChapters);

  final List<BookChapter> storedChapters;

  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async => storedChapters;
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<BookSource?> getByUrl(String url) async => null;
}
