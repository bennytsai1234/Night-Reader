// AI 找書：從「過去的找書」打開一份推薦了 30 本的報告（換頁、骨架、骨架
// 換成內容）再返回，每一幀的成本（ADR 0018、0029）。骨架照推薦的每一本
// 排版書名、「作者 · 字數 · 分類」與推薦理由，本數多時排版落在換場那幾
// 幀。用法見 `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常
// 的全套測試跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/ai_find/ai_find_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

/// 最多能要的本數（開始前的「本數」收 1 到 30）。
const _pickCount = 30;

AiFindRecord _record() => AiFindRecord(
  id: 'x',
  description: '爽文、穿越，我在看鏈鋸人和咒術迴戰，想要更刺激的',
  depth: 'deep',
  createdAt: 0,
  outcome: AiFindOutcome.found,
  summary: '先查了兩部作品的各地譯名，再搜書名帶作品名與角色名的同人。' * 3,
  picks: [
    for (var i = 0; i < _pickCount; i++)
      (
        book: SearchBook(
          bookUrl: 'https://a.test/$i',
          name: '第 $i 本：穿越到鏈鋸人的世界當惡魔獵人',
          author: '作者 $i',
          origin: 'https://a.test',
          originName: 'A 站',
          wordCount: '${100 + i}萬字',
          kind: i.isEven ? '同人 · 都市' : '玄幻',
        ),
        reason:
            '穿越到鏈鋸人的世界當惡魔獵人，一路變強，節奏快、打鬥多。'
            '${'最後一章是斷更公告，可能太監。' * (i % 3)}',
      ),
  ],
  rounds: 24,
  tokens: 513000,
);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('a past AI find with 30 books', (tester) async {
    setUpScreenshot(tester);
    late SharedPreferences prefs;
    await tester.runAsync(() async {
      await setUpApp();
      prefs = await SharedPreferences.getInstance();
    });
    final record = _record();

    for (final round in ['第一輪', '第二輪']) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AiFindPage(prefs: prefs, record: record),
                    ),
                  ),
                  child: const Text('打開過去的找書'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await measureNavigation(
        tester,
        '$round 打開過去的找書',
        action: () => tester.tap(find.text('打開過去的找書')),
        page: find.byType(AiFindPage),
      );
      await rest(tester);
      expect(find.textContaining('第 0 本'), findsOneWidget);

      await measureNavigation(
        tester,
        '$round 過去的找書返回',
        action: () => goBack(tester),
        settled: () => find.text('打開過去的找書').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }
    await tearDownApp(tester);
  });
}
