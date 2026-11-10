// 漫畫閱讀器（ADR 0052）：開閱讀器、手指拖著捲過換章分隔再放手慣性滑、
// 叫出選單按「下一話」跳章（骨架換成圖淡入），每一幀的成本。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。圖從記憶體來（每種顏色只產生一次），解碼在引擎的執行緒；App 裡的
// 讀檔、抓圖在背景 isolate，這裡不算。
@Tags(['frame_budget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/comic_reader/comic_reader_page.dart';
import 'package:night_reader/features/comic_reader/comic_strip_view.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../features/comic_reader/comic_test_pages.dart';
import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

const _chapterCount = 6;

final _book = Book(
  bookUrl: 'local://comic/frame-budget',
  origin: 'local',
  name: '夜行漫畫',
  type: 2,
  isInBookshelf: true,
);

final _chapters = [
  for (var i = 0; i < _chapterCount; i++)
    BookChapter(
      url: 'local://comic/frame-budget/$i',
      title: '第${i + 1}話 夜行的少年',
      bookUrl: _book.bookUrl,
      index: i,
    ),
];

/// 一個手勢：第 0 幀按下，接著每幀移一步，走完放開；放開後的那一幀起
/// [released] 為 true。
class _FrameGesture {
  _FrameGesture(
    this.tester,
    this.at, {
    required this.step,
    required this.steps,
  });

  final WidgetTester tester;
  final Offset at;
  final Offset step;
  final int steps;
  TestGesture? _gesture;
  bool released = false;

  Future<void> onFrame(int frame) async {
    final timeStamp = Duration(milliseconds: 16 * frame);
    if (frame == 0) {
      _gesture = await tester.startGesture(at);
    } else if (frame <= steps) {
      await _gesture!.moveBy(step, timeStamp: timeStamp);
    } else if (!released) {
      await _gesture!.up(timeStamp: timeStamp);
      released = true;
    }
  }
}

bool _scrolling() => find
    .byType(Scrollable)
    .evaluate()
    .map((e) => (e as StatefulElement).state as ScrollableState)
    .any((s) => s.position.isScrollingNotifier.value);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('comic reader', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await getIt<BookDao>().upsert(_book);
    });
    // 一張 720×1100（約一張漫畫單頁），一話八張。
    final source = FakeComicSource(
      pagesPerChapter: 8,
      width: 720,
      height: 1100,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ComicReaderPage(
                      book: _book,
                      initialChapters: _chapters,
                      pageSource: source,
                    ),
                  ),
                ),
                child: const Text('打開漫畫'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await measureNavigation(
      tester,
      '開漫畫閱讀器',
      action: () => tester.tap(find.text('打開漫畫')),
      page: find.byType(ComicStripView),
    );
    await rest(tester);

    const centre = Offset(196, 426);
    for (final round in ['第一輪', '第二輪']) {
      // 拖著往下捲兩個多螢幕（跨過換章分隔），放手慣性滑。
      final fling = _FrameGesture(
        tester,
        centre,
        step: const Offset(0, -80),
        steps: 24,
      );
      await measureNavigation(
        tester,
        '$round 拖動捲過換章再慣性滑',
        action: () async {},
        settled: () => fling.released && !_scrolling(),
        note: () => fling.released ? '慣性' : '拖動',
        onFrame: fling.onFrame,
      );
      await rest(tester);

      // 叫出選單、按「下一話」：那一話的骨架換成圖淡入。
      await tester.tapAt(centre);
      await settle(tester, const Duration(milliseconds: 800));
      await measureNavigation(
        tester,
        '$round 按下一話跳章',
        action: () => tester.tap(find.text('下一話')),
        settled: () => !_scrolling(),
        note: () => '跳章',
      );
      await rest(tester);
      // 收起選單，下一輪從只有圖的畫面開始。
      await tester.tapAt(centre);
      await rest(tester);
    }
    await tearDownApp(tester);
  });
}
