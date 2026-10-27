// 臨時：全 App 動畫儀表板探索的「書源管理」區：進頁、捲長清單、開關書源、篩選與排序
// 選單、搜尋框、多選進出與批次停用、點進編輯與除錯頁再返回、長按選單。不存、不刪
// 書源（編輯頁只看不改）。書源是 upsert 固定代號的 300 筆假資料，可重跑。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/source_manager/widgets/source_item_tile.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'sources';
const _sourceCount = 300;

/// 同 `source_manager_frame_budget_test.dart`：三十個域名各十個書源。
BookSource _source(int i) => BookSource.fromJson({
  'bookSourceUrl': 'https://www.site${i % 30}.example/path$i',
  'bookSourceName': '書源 $i',
  'bookSourceGroup': i % 4 == 0
      ? '常用'
      : i % 7 == 0
      ? '繁體,精選'
      : null,
  'bookSourceComment': i % 11 == 0 ? '備註 $i' : null,
  'customOrder': i,
  'enabled': i % 5 != 0,
  'searchUrl': '/search?q={{key}}',
  'exploreUrl': i % 3 == 0 ? '最新::/new' : null,
  'ruleBookInfo': {'name': 'tag.h1@text'},
  'ruleToc': {'chapterList': 'class.toc@tag.a'},
  'ruleContent': {'content': 'id.content@html'},
});

/// 書源管理頁（最上層）裡的清單。
Finder get _page => find.byType(SourceManagerPage);

Finder get _list =>
    find.descendant(of: _page, matching: find.byType(Scrollable)).first;

/// 最上面（還看得到的）那一筆書源列。
Finder get _firstTile =>
    find.descendant(of: _page, matching: find.byType(SourceItemTile)).first;

/// 把 [target] 捲到看得到。
Future<void> _show(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 100, scrollable: _list);
  }
  await tester.ensureVisible(target.first);
  await tester.pump();
}

/// 點選單、動作表、確認框裡的一項。浮在最上層，取最後一個。
Future<void> _tapTop(WidgetTester tester, String text) =>
    tester.tap(find.text(text).last);

/// 開書源管理頁的「更多操作」選單。
Future<void> _openMore(WidgetTester tester) =>
    tester.tap(find.byTooltip('更多操作').last);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: sources', (tester) async {
    Future<void> tapTab(String label) => tester.tap(
      find.descendant(
        of: find.byType(FloatingTabBar),
        matching: find.text(label),
      ),
    );

    await runSurvey(
      tester,
      prefs: const {'source_manager_last_count': _sourceCount},
      steps: () async {
        // 三百筆書源（upsert 固定代號，重跑不會多出來）。
        await tester.runAsync(
          () => getIt<BookSourceDao>().upsertAll([
            for (var i = 0; i < _sourceCount; i++) _source(i),
          ]),
        );

        var i = 0;
        Future<void> step(
          String label,
          Future<void> Function() action, {
          bool Function()? until,
        }) {
          i++;
          return surveyStep(
            tester,
            area: _area,
            key: 'sources${i.toString().padLeft(2, '0')}',
            label: label,
            action: action,
            until: until,
            // 點下去後第一格路由還沒蓋出來，不設下限會在 31 格就被當成停了。
            minFrames: 20,
          );
        }

        await step('點分頁：書架→我的', () => tapTab('我的'));
        await step('進入書源管理', () async {
          final row = find.descendant(
            of: find.byType(GroupedListView).last,
            matching: find.text('書源管理'),
          );
          await tester.tap(row.first);
        });

        // 清單很長：捲下去、再捲下去、捲回頂部。
        await step(
          '向上捲動書源清單',
          () => tester.fling(_list, const Offset(0, -2500), 3000),
        );
        await step(
          '再向上捲動書源清單',
          () => tester.fling(_list, const Offset(0, -3000), 4000),
        );
        await step(
          '捲回書源清單頂部',
          () => tester.fling(_list, const Offset(0, 9000), 9000),
        );

        // 開關：停用、再啟用最上面那一筆。
        Future<void> toggleFirst() async {
          final sw = find.descendant(
            of: _page,
            matching: find.byType(GroupedSwitch),
          );
          await _show(tester, sw.first);
          await tester.tap(sw.first);
        }

        await step('書源：停用第一筆', toggleFirst);
        await step('書源：重新啟用第一筆', toggleFirst);

        // 更多選單：按域名分組開與關。
        await step('更多操作：開選單', () => _openMore(tester));
        await step('更多操作：按域名分組（開）', () => _tapTop(tester, '按域名分組'));
        await step('更多操作：開選單', () => _openMore(tester));
        await step('更多操作：按域名分組（關）', () => _tapTop(tester, '按域名分組'));

        // 排序方式（第二層）：開、選按名稱、再選回手動排序。
        await step('更多操作：開選單', () => _openMore(tester));
        await step('排序方式：開子選單', () => _tapTop(tester, '排序方式'));
        await step('排序方式：選按名稱', () => _tapTop(tester, '按名稱'));
        await step('更多操作：開選單', () => _openMore(tester));
        await step('排序方式：開子選單', () => _tapTop(tester, '排序方式'));
        await step('排序方式：選手動排序', () => _tapTop(tester, '手動排序'));

        // 分組與篩選（第二層）：篩已啟用、再選回全部。
        await step('更多操作：開選單', () => _openMore(tester));
        await step('分組與篩選：開子選單', () => _tapTop(tester, '分組與篩選'));
        await step('分組與篩選：選已啟用', () => _tapTop(tester, '已啟用'));
        await step('更多操作：開選單', () => _openMore(tester));
        await step('分組與篩選：開子選單', () => _tapTop(tester, '分組與篩選'));
        await step('分組與篩選：選全部', () => _tapTop(tester, '全部'));

        // 關選單：開著時點外面關掉。
        await step('更多操作：開選單', () => _openMore(tester));
        await step('點選單外面關掉', () => tester.tapAt(const Offset(30, 40)));

        // 搜尋框：打字篩選，再清空。
        await step('搜尋框：輸入「書源 1」', () async {
          await tester.enterText(
            find.descendant(of: _page, matching: find.byType(TextField)),
            '書源 1',
          );
        });
        await step('搜尋框：清空', () async {
          await tester.enterText(
            find.descendant(of: _page, matching: find.byType(TextField)),
            '',
          );
        });

        // 多選：進入、勾兩筆、批次停用、批次啟用、完成離開。
        await step('更多操作：開選單', () => _openMore(tester));
        await step('進入多選（選取書源）', () => _tapTop(tester, '選取書源'));
        await step('多選：勾第一筆', () => tester.tap(_firstTile));
        await step('多選：勾第二筆', () async {
          await tester.tap(
            find
                .descendant(of: _page, matching: find.byType(SourceItemTile))
                .at(1),
          );
        });
        // 多選的標題列只有「全選」與「完成」；批次停用、啟用的工具列在程式裡沒有接上，這裡不列。
        await step('多選：全選', () => tester.tap(find.text('全選')));
        await step('多選：取消全選', () => tester.tap(find.text('取消全選')));
        await step('完成多選', () => tester.tap(find.text('完成')));

        // 點一筆進編輯頁（只看不存），返回。
        await step('點第一筆書源：進編輯頁', () => tester.tap(_firstTile));
        await step('返回書源管理（離開編輯頁）', () => goBack(tester));

        // 長按一筆：列出單一書源的選單，點除錯進除錯頁（不按開始），返回。
        await step('長按第一筆書源：開選單', () => tester.longPress(_firstTile));
        await step('長按選單：除錯書源', () => _tapTop(tester, '除錯書源'));
        await step('返回書源管理（離開除錯頁）', () => goBack(tester));

        await step('返回我的（離開書源管理）', () => goBack(tester));
      },
    );
  });
}
