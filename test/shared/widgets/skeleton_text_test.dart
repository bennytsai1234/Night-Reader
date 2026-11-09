// 照字畫的骨架長條要和換上來的字一樣長：被刪節的一行含「…」，行首與行尾
// 的全形標點扣掉那一格空著的部分（docs/design/loading.md「骨架的樣子」）。
//
// 測試字型的字都是方塊，所以標點空著多少由測試直接給表；
// 實際字型的量法另外驗證 [PunctuationInk.measure] 量得出每一格的寬。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_text.dart';

const _style = TextStyle(fontSize: 10, height: 1.3);

TextPainter _layout(String text, {double maxWidth = 1000, int? maxLines}) =>
    TextPainter(
      text: TextSpan(text: text, style: _style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);

/// 開頭括號右半有筆畫、結尾括號左半有筆畫、逗號只有左邊三成。
const _table = {
  '「': PunctuationBlank(left: 0.5, right: 0.1, advance: 1),
  '」': PunctuationBlank(left: 0.1, right: 0.5, advance: 1),
  '，': PunctuationBlank(left: 0.1, right: 0.7, advance: 1),
};

void main() {
  tearDown(PunctuationInk.resetForTest);

  test('an ellipsized line reaches the end of the ellipsis', () {
    // 一格 10 寬：放得下四個字加「…」。
    final painter = _layout('一二三四五六七八九十', maxWidth: 55, maxLines: 1);
    final lines = skeletonTextLines(painter);
    expect(lines, hasLength(1));
    expect(lines.single.left, 0);
    expect(lines.single.right, 50);
  });

  test('unmeasured fonts keep the full cells of punctuation', () {
    final lines = skeletonTextLines(_layout('「你好」'));
    expect(lines.single.left, 0);
    expect(lines.single.right, 40);
  });

  test('punctuation at the start and end of a line drops its blank part', () {
    PunctuationInk.setTableForTest(_style, _table);
    final lines = skeletonTextLines(_layout('「你好」'));
    expect(lines.single.left, 5);
    expect(lines.single.right, 35);

    final comma = skeletonTextLines(_layout('他說，'));
    expect(comma.single.right, 23);
  });

  test('punctuation inside a line is left alone', () {
    PunctuationInk.setTableForTest(_style, _table);
    final lines = skeletonTextLines(_layout('你「好」嗎'));
    expect(lines.single.left, 0);
    expect(lines.single.right, 50);
  });

  test('each wrapped line is trimmed by its own first and last mark', () {
    PunctuationInk.setTableForTest(_style, _table);
    // 一行四格：「你好，｜「再見」
    final lines = skeletonTextLines(_layout('「你好，「再見」', maxWidth: 40));
    expect(lines, hasLength(2));
    expect(lines[0].left, 5);
    expect(lines[0].right, 33);
    expect(lines[1].left, 5);
    expect(lines[1].right, 35);
  });

  test('an ellipsized line keeps the ellipsis instead of trimming', () {
    PunctuationInk.setTableForTest(_style, _table);
    final painter = _layout('「你好」再見再見再見', maxWidth: 55, maxLines: 1);
    final lines = skeletonTextLines(painter);
    expect(lines.single.left, 5);
    expect(lines.single.right, 50);
  });

  test('a line cut by a hard line break is still trimmed at its end', () {
    PunctuationInk.setTableForTest(_style, _table);
    // 超過最大行數是因為後面還有一行，不是放不下：這一行沒有「…」。
    final painter = _layout('你好」\n第二行', maxWidth: 200, maxLines: 1);
    expect(painter.didExceedMaxLines, isTrue);
    expect(skeletonTextLines(painter).single.right, 25);
  });

  test('each end mark uses its own span style and size', () {
    const big = TextStyle(fontSize: 20);
    PunctuationInk.setTableForTest(_style.merge(big), _table);
    final painter = TextPainter(
      text: const TextSpan(
        style: _style,
        children: [TextSpan(text: '「你好」', style: big)],
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 1000);
    final line = skeletonTextLines(painter).single;
    expect(line.left, 10);
    expect(line.right, 70);
  });

  testWidgets('SkeletonText applies the system letter spacing like Text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(letterSpacingOverride: 4),
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('一二三', style: _style),
                SkeletonText('一二三', style: _style),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(SkeletonText)),
      tester.getSize(find.text('一二三')),
    );
  });

  testWidgets('a font first used after launch is measured once the screen '
      'is still, even with an old table', (tester) async {
    // 上次存的表（別台或換過字型）：開引號左邊空一半。
    PunctuationInk.setTableForTest(_style, _table);
    await PunctuationInk.onLaunchSettled();
    final painter = _layout('「你好');
    expect(skeletonTextLines(painter).single.left, 5);

    // 畫面在動的時候不量（量的工作要等真的事件迴圈，每一步都讓它跑一下）。
    Future<void> step(Duration duration) async {
      await tester.pump(duration);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }

    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(seconds: 2),
    )..forward();
    addTearDown(controller.dispose);
    for (var i = 0; i < 90; i++) {
      await step(const Duration(milliseconds: 16));
    }
    expect(controller.isAnimating, isTrue);
    expect(skeletonTextLines(painter).single.left, 5);

    // 停下來之後量：測試字型的開引號沒有空白，長條回到字的左緣附近。量的
    // 時候把字畫成圖、讀回像素，要真的事件迴圈跑完；CI 的機器慢，多給幾輪、
    // 每輪多等一點，量到就停（原本 20 輪、每輪 20ms，CI 上偶爾不夠）。
    await tester.pumpAndSettle();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      if (skeletonTextLines(painter).single.left < 5) break;
    }
    expect(skeletonTextLines(painter).single.left, lessThan(5));
    painter.dispose();
  });

  testWidgets('SkeletonText sizes itself like Text and draws one bar a line', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 55,
            child: Skeleton(
              child: Align(
                alignment: Alignment.topLeft,
                child: SkeletonText('一二三四五六七八九十', style: _style, maxLines: 1),
              ),
            ),
          ),
        ),
      ),
    );
    final bar = tester.getRect(find.byType(SkeletonBox));
    expect(bar.left, 0);
    expect(bar.width, 50);
    expect(bar.height, 10);
    expect(tester.getSize(find.byType(SkeletonText)).height, 13);
  });

  testWidgets('each bar sits on its own line of glyphs, past empty lines', (
    tester,
  ) async {
    const text = '第一行\n\n第三行';
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: Skeleton(child: SkeletonText(text, style: _style)),
        ),
      ),
    );
    // 空行沒有長條；第二條在第三行的字上，不是空行上。
    final bars = [
      for (final box in find.byType(SkeletonBox).evaluate())
        tester.getRect(find.byElementPredicate((e) => identical(e, box))),
    ]..sort((a, b) => a.top.compareTo(b.top));
    expect(bars, hasLength(2));
    final painter = _layout(text);
    double glyphCenter(int start, int end) => painter
        .getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        )
        .map((box) => box.toRect().center.dy)
        .first;
    expect(bars[0].center.dy, moreOrLessEquals(glyphCenter(0, 3)));
    expect(bars[1].center.dy, moreOrLessEquals(glyphCenter(5, 8)));
  });

  testWidgets('measure finds every mark in the font', (tester) async {
    final table = await tester.runAsync(() => PunctuationInk.measure(_style));
    expect(table!.keys, containsAll(PunctuationInk.marks.split('')));
    // 測試字型一格一個字寬，每個字都畫得出筆畫。
    for (final blank in table.values) {
      expect(blank.advance, closeTo(1, 0.01));
      expect(blank.left + blank.right, lessThan(0.5));
    }
  });
}
