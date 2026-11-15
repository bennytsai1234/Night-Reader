// 從「過去的找書」推入報告時的骨架（ADR 0029）：推薦的每一本（封面、書名、
// 「作者 · 字數 · 分類」、推薦理由）與 AI 的說明，骨架都和換上的內容一樣。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/ai_find/ai_find_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/screenshot.dart';
import '../../../support/skeleton_match.dart';

SearchBook _book(String name, String kind) => SearchBook(
  bookUrl: 'https://a.test/$name',
  name: name,
  author: '作者',
  origin: 'https://a.test',
  originName: 'A 站',
  wordCount: '120萬字',
  kind: kind,
);

void main() {
  testWidgets('推入過去的找書，骨架就和推薦的書與說明一樣', (tester) async {
    setUpScreenshot(tester);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final record = AiFindRecord(
      id: 'x',
      description: '爽文、穿越，我在看鏈鋸人和咒術迴戰，想要更刺激的',
      depth: 'normal',
      createdAt: 0,
      outcome: AiFindOutcome.found,
      summary: '先查了兩部作品的各地譯名，再搜書名帶作品名與角色名的同人。',
      picks: [
        (book: _book('鏈鋸人之惡魔獵人', '同人'), reason: '穿越到鏈鋸人的世界當惡魔獵人，一路變強，節奏快、打鬥多。'),
        (book: _book('咒術迴戰：最強的我', '同人 · 都市'), reason: '短'),
      ],
      rounds: 9,
      tokens: 213000,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AiFindPage(prefs: prefs, record: record),
              ),
            ),
            child: const Text('開啟'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pump();
    final list = find.byType(GroupedListView, skipOffstage: false);
    final route = ModalRoute.of(tester.element(list))!;
    while (!route.animation!.isCompleted) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final skeleton = skeletonLayoutOf(
      tester,
      find.descendant(of: list, matching: find.byType(SkeletonShapes)),
    );
    expect(skeleton.marks, isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShapes), findsNothing);
    expect(
      skeletonMismatches(
        skeleton,
        contentLayoutOf(tester, list),
        visible: tester.getRect(list),
      ),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
