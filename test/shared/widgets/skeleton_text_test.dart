// 照字畫的骨架長條要和換上來的字一樣長：被刪節的一行含「…」，行首與行尾
// 的全形標點扣掉那一格空著的部分（DESIGN.md「骨架是真實畫面的影子」）。
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
    final lines = skeletonTextLines(painter, _style);
    expect(lines, hasLength(1));
    expect(lines.single.left, 0);
    expect(lines.single.right, 50);
  });

  test('unmeasured fonts keep the full cells of punctuation', () {
    final lines = skeletonTextLines(_layout('「你好」'), _style);
    expect(lines.single.left, 0);
    expect(lines.single.right, 40);
  });

  test('punctuation at the start and end of a line drops its blank part', () {
    PunctuationInk.setTableForTest(_style, _table);
    final lines = skeletonTextLines(_layout('「你好」'), _style);
    expect(lines.single.left, 5);
    expect(lines.single.right, 35);

    final comma = skeletonTextLines(_layout('他說，'), _style);
    expect(comma.single.right, 23);
  });

  test('punctuation inside a line is left alone', () {
    PunctuationInk.setTableForTest(_style, _table);
    final lines = skeletonTextLines(_layout('你「好」嗎'), _style);
    expect(lines.single.left, 0);
    expect(lines.single.right, 50);
  });

  test('each wrapped line is trimmed by its own first and last mark', () {
    PunctuationInk.setTableForTest(_style, _table);
    // 一行四格：「你好，｜「再見」
    final lines = skeletonTextLines(_layout('「你好，「再見」', maxWidth: 40), _style);
    expect(lines, hasLength(2));
    expect(lines[0].left, 5);
    expect(lines[0].right, 33);
    expect(lines[1].left, 5);
    expect(lines[1].right, 35);
  });

  test('an ellipsized line keeps the ellipsis instead of trimming', () {
    PunctuationInk.setTableForTest(_style, _table);
    final painter = _layout('「你好」再見再見再見', maxWidth: 55, maxLines: 1);
    final lines = skeletonTextLines(painter, _style);
    expect(lines.single.left, 5);
    expect(lines.single.right, 50);
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
