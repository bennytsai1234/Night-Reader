// 漫畫閱讀器連續高速甩動（ADR 0052）：開書後連甩好幾下、一路捲過好幾話，
// 每一幀的成本，以及畫面上露出骨架的幀數。用法見 `test/support/frame_budget.dart`；
// 帶 `frame_budget` 標籤，平常的全套測試跳過。
//
// 每張圖晚 [_pageLatency]（假時間）才回，代表讀檔或抓圖的時間；解碼在引擎的
// 執行緒。骨架幀數看的是預載夠不夠早：圖在捲到之前就拿到、解好，畫面上就
// 不會出現骨架。
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
import 'package:night_reader/shared/widgets/skeleton.dart';

import '../features/comic_reader/comic_test_pages.dart';
import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

const _chapterCount = 12;
const _pageLatency = Duration(milliseconds: 120);

final _book = Book(
  bookUrl: 'local://comic/fast-scroll',
  origin: 'local',
  name: '夜行漫畫',
  type: 2,
  isInBookshelf: true,
);

final _chapters = [
  for (var i = 0; i < _chapterCount; i++)
    BookChapter(
      url: 'local://comic/fast-scroll/$i',
      title: '第${i + 1}話 夜行的少年',
      bookUrl: _book.bookUrl,
      index: i,
    ),
];

/// 連甩 [flings] 下：每下按住、每幀往上拖 [step]、拖 [steps] 幀後放開，
/// 隔 [pause] 幀再甩下一下。
class _Flings {
  _Flings(
    this.tester,
    this.at, {
    required this.flings,
    required this.step,
    required this.steps,
    required this.pause,
  });

  final WidgetTester tester;
  final Offset at;
  final int flings;
  final Offset step;
  final int steps;
  final int pause;
  TestGesture? _gesture;
  bool done = false;

  int get _period => steps + 1 + pause;

  Future<void> onFrame(int frame) async {
    if (done) return;
    final round = frame ~/ _period;
    final within = frame % _period;
    final timeStamp = Duration(milliseconds: 16 * frame);
    if (round >= flings) {
      done = true;
      return;
    }
    if (within == 0) {
      _gesture = await tester.startGesture(at);
    } else if (within <= steps) {
      await _gesture!.moveBy(step, timeStamp: timeStamp);
    } else if (within == steps + 1) {
      await _gesture!.up(timeStamp: timeStamp);
    }
  }
}

bool _scrolling() => find
    .byType(Scrollable)
    .evaluate()
    .map((e) => (e as StatefulElement).state as ScrollableState)
    .any((s) => s.position.isScrollingNotifier.value);

/// 條漫上露在畫面裡的骨架有幾塊（圖還沒到，或剛到、正在淡入）。
int _visibleSkeletons(WidgetTester tester, Rect screen) {
  final strip = find.byType(ComicStripView);
  var count = 0;
  for (final element
      in find
          .descendant(of: strip, matching: find.byType(SkeletonBox))
          .evaluate()) {
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.overlaps(screen)) count += 1;
  }
  return count;
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('comic fast scroll', (tester) async {
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
      pageLatency: _pageLatency,
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

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final screen = Offset.zero & size;
    final centre = size.center(Offset.zero);
    // 每下拖 10 幀、每幀 160 點（約每秒一萬點）放手，隔 30 幀再甩。
    final flings = _Flings(
      tester,
      centre,
      flings: 6,
      step: const Offset(0, -160),
      steps: 10,
      pause: 30,
    );
    var skeletonFrames = 0;
    var frames = 0;
    await measureNavigation(
      tester,
      '連續高速甩動',
      action: () async {},
      settled: () => flings.done && !_scrolling(),
      note: () => flings.done ? '慣性' : '甩動',
      onFrame: (frame) async {
        await flings.onFrame(frame);
        frames += 1;
        if (_visibleSkeletons(tester, screen) > 0) skeletonFrames += 1;
      },
    );
    // ignore: avoid_print
    print('連續高速甩動：露出骨架 $skeletonFrames／$frames 幀');
    await rest(tester);
    await tearDownApp(tester);
  });
}
