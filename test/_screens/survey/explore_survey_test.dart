// 臨時：全 App 發現區的動畫儀表板探索（每個使用者操作一步）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/explore/explore_show_page.dart';
import 'package:night_reader/features/explore/explore_show_provider.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:provider/provider.dart';

import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'explore';

const _listRule = {
  'bookList': 'class.item',
  'name': 'class.name@text',
  'author': 'class.author@text',
  'bookUrl': 'class.name@href',
  'intro': 'class.intro@text',
  'kind': 'class.kind@text',
  'lastChapter': 'class.last@text',
};

/// 發現清單要長到捲得動，又要有分組可以篩。20 個額外書源都有發現網址（絕對
/// 網址，假網站回應），前 4 個放進「夜讀」分組；排在「夜讀書庫」之後。
/// idempotent，兩次跑都照呼叫。
Future<void> _seedExtraSources() => getIt<BookSourceDao>().upsertAll([
  for (var i = 1; i <= 20; i++)
    BookSource.fromJson({
      'bookSourceUrl': 'https://explore.test/src$i',
      'bookSourceName': '夜讀分源 $i',
      'customOrder': 100 + i,
      if (i <= 4) 'bookSourceGroup': '夜讀',
      'exploreUrl':
          '最新::https://explore.test/new\n熱門::https://explore.test/hot',
      'ruleExplore': _listRule,
    }),
]);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: explore', (tester) async {
    Finder inExplore(String text) => find.descendant(
      of: find.byType(ExplorePage),
      matching: find.text(text),
    );
    final sourceList = find.descendant(
      of: find.byType(ExplorePage),
      matching: find.byType(Scrollable),
    );
    final showList = find.descendant(
      of: find.byType(ExploreShowView),
      matching: find.byType(ListView),
    );
    var loadedBefore = 0;
    ExploreShowProvider? showProvider() {
      final elements = find.byType(ExploreShowView).evaluate();
      if (elements.isEmpty) return null;
      return Provider.of<ExploreShowProvider>(elements.first, listen: false);
    }

    // 假網站每一頁都回同樣的 30 本，下一頁的書全部重複、被去掉，所以不會變多；
    // 載入回來就是 hasMore 變成 false。
    int showBooks() => showProvider()?.books.length ?? 0;

    await runSurvey(
      tester,
      steps: () async {
        await tester.runAsync(_seedExtraSources);

        await surveyStep(
          tester,
          area: _area,
          key: 'explore01',
          label: '點「發現」分頁',
          action: () => tester.tap(
            find.descendant(
              of: find.byType(FloatingTabBar),
              matching: find.text('發現'),
            ),
          ),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore02',
          label: '點書源「夜讀書庫」，展開分類',
          action: () => tester.tap(find.text(kSiteName)),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore03',
          label: '點分類「最新」，進書單',
          action: () => tester.tap(inExplore('最新')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore04',
          label: '書單點第一本，進書籍詳情',
          action: () => tester.tap(find.text('夜讀第0卷').first),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore05',
          label: '詳情返回書單',
          action: () => goBack(tester),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore06',
          label: '書單往下滑',
          action: () =>
              tester.fling(showList.first, const Offset(0, -600), 2000),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore07',
          label: '書單一路滑到底，自動載入下一頁',
          action: () {
            loadedBefore = showBooks();
            return tester.fling(showList.first, const Offset(0, -6000), 6000);
          },
          // 下一頁回來（書變多，或假網站重複的書被去掉、hasMore 變 false）且停下來
          // 才算完；沒有載入會停不下來而被標出。
          until: () {
            final p = showProvider();
            return p != null &&
                (!p.hasMore || p.books.length > loadedBefore) &&
                surveyQuiet();
          },
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore08',
          label: '書單返回發現',
          action: () => goBack(tester),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore09',
          label: '點分類「熱門」，切到另一個書單',
          action: () => tester.tap(inExplore('熱門')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore10',
          label: '書單返回發現',
          action: () => goBack(tester),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore11',
          label: '點「夜讀書庫」收合分類',
          action: () => tester.tap(find.text(kSiteName)),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore12',
          label: '長按書源，打開書源選單',
          action: () => tester.longPress(find.text(kSiteName)),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore13',
          label: '關閉書源選單',
          action: () => goBack(tester),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore14',
          label: '發現清單往下滑',
          action: () =>
              tester.fling(sourceList.first, const Offset(0, -700), 2000),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore15',
          label: '點頂部「分組」，打開分組選單',
          action: () => tester.tap(find.byTooltip('分組')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore16',
          label: '選分組「夜讀」，清單只剩該組',
          action: () => tester.tap(find.textContaining('夜讀').last),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore17',
          label: '分組選單改回「全部」',
          action: () => tester.tap(find.byTooltip('分組')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'explore18',
          label: '選「全部」，清單還原',
          action: () => tester.tap(find.textContaining('全部').last),
        );
      },
    );
  });
}
