// 臨時：全 App 搜尋區的動畫儀表板探索（每個使用者操作一步）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:night_reader/features/search/widgets/search_app_bar.dart';
import 'package:night_reader/features/search/widgets/search_history_view.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:provider/provider.dart';

import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'search';

const _listRule = {
  'bookList': 'class.item',
  'name': 'class.name@text',
  'author': 'class.author@text',
  'bookUrl': 'class.name@href',
  'intro': 'class.intro@text',
  'kind': 'class.kind@text',
  'lastChapter': 'class.last@text',
};

/// 假網站只回應 explore.test。搜尋要多幾個書源才會陸續回來：這 40 個書源的
/// 搜尋網址寫成同一台的絕對網址，每個都回同樣的 30 本；同時最多 8 個（預設），
/// 整批約 1.5 秒搜完，中途才按得到「停止」。idempotent，兩次跑都照呼叫。
Future<void> _seedExtraSources() => getIt<BookSourceDao>().upsertAll([
  for (var i = 1; i <= 40; i++)
    BookSource.fromJson({
      'bookSourceUrl': 'https://explore.test/src$i',
      'bookSourceName': '夜讀分源 $i',
      'customOrder': 10 + i,
      'searchUrl': 'https://explore.test/search?q={{key}}',
      'ruleSearch': _listRule,
    }),
]);

/// 搜尋頁的 provider；頁面還沒開或已關掉時是 null。
SearchProvider? _search() {
  final elements = find.byType(SearchView).evaluate();
  if (elements.isEmpty) return null;
  return Provider.of<SearchProvider>(elements.first, listen: false);
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: search', (tester) async {
    // 篩選、失敗書源的面板用 Provider.value 包 ChangeNotifier（SearchProvider），
    // 偵錯模式會丟例外、面板建不出來；正式版不檢查，這裡照正式版的行為關掉。
    final checkValueType = Provider.debugCheckInvalidValueType;
    Provider.debugCheckInvalidValueType = null;
    addTearDown(() => Provider.debugCheckInvalidValueType = checkValueType);

    final field = find.descendant(
      of: find.byType(SearchAppBar),
      matching: find.byType(TextField),
    );
    Finder inSearchBar(String text) => find.descendant(
      of: find.byType(SearchAppBar),
      matching: find.text(text),
    );
    final resultList = find.descendant(
      of: find.byType(SearchView),
      matching: find.byType(ListView),
    );
    final scopeCapsule = find.byWidgetPredicate(
      (w) => w is Tooltip && (w.message ?? '').startsWith('選擇搜尋範圍'),
    );
    Finder inSheetHeader(String text) => find.descendant(
      of: find.byType(SheetHeader),
      matching: find.text(text),
    );

    // 搜尋完、結果在畫面上、停下來。
    bool searchFinished() {
      final p = _search();
      return p != null &&
          !p.isSearching &&
          p.results.isNotEmpty &&
          surveyQuiet();
    }

    // 書架「＋」選單 → 搜尋書籍，兩步。
    Future<void> openSearchFromShelf(String keyMenu, String keyPick) async {
      await surveyStep(
        tester,
        area: _area,
        key: keyMenu,
        label: '書架：打開「加入書籍」選單',
        action: () => tester.tap(find.byTooltip('加入書籍')),
      );
      await surveyStep(
        tester,
        area: _area,
        key: keyPick,
        label: '選「搜尋書籍」，進搜尋頁',
        action: () => tester.tap(find.text('搜尋書籍').last),
      );
    }

    await runSurvey(
      tester,
      steps: () async {
        // 每次開始都回到預設的網路延遲（第二次進搜尋會改成慢的，見下）。
        await tester.runAsync(() async {
          await _seedExtraSources();
          await installFakeSite();
        });

        // 第一次進搜尋：打字、送出、看結果、排序、篩選、範圍，最後取消離開。
        await openSearchFromShelf('search01', 'search02');
        await surveyStep(
          tester,
          area: _area,
          key: 'search03',
          label: '搜尋框：點一下取得焦點',
          action: () => tester.tap(field),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search04',
          label: '打字「夜」，跳出建議',
          action: () => tester.enterText(field, '夜'),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search05',
          label: '鍵盤搜尋鍵送出，結果陸續進來',
          action: () async =>
              tester.testTextInput.receiveAction(TextInputAction.search),
          until: searchFinished,
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search06',
          label: '結果往下滑',
          action: () =>
              tester.fling(resultList.first, const Offset(0, -600), 2000),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search07',
          label: '結果滑回頂端',
          action: () =>
              tester.fling(resultList.first, const Offset(0, 6000), 6000),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search08',
          label: '點「排序」選單',
          action: () => tester.tap(find.textContaining('排序：')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search09',
          label: '選排序「書名」',
          action: () => tester.tap(find.text('書名').last),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search10',
          label: '點「篩選」，打開篩選面板',
          action: () => tester.tap(
            find.descendant(
              of: find.byType(SearchView),
              matching: find.text('篩選'),
            ),
          ),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search11',
          label: '篩選：開「只看已加入書架」',
          action: () => tester.tap(find.text('只看已加入書架')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search12',
          label: '篩選面板：清除',
          action: () => tester.tap(inSheetHeader('清除')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search13',
          label: '關閉篩選面板',
          action: () => goBack(tester),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search14',
          label: '點搜尋範圍，打開範圍面板',
          action: () => tester.tap(scopeCapsule),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search15',
          label: '範圍：改回「全部書源」並關閉',
          action: () => tester.tap(inSheetHeader('全部書源')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search16',
          label: '點「取消」，離開搜尋',
          action: () => tester.tap(inSearchBar('取消')),
        );

        // 第二次進搜尋：歷史關鍵字在，點一個進去，搜尋途中按停止。假網站的回應
        // 預設 0.3 秒，搜完前就錄完了、按不到停止，這次改成 2 秒才回來。
        await tester.runAsync(
          () => installFakeSite(latency: const Duration(seconds: 2)),
        );
        await openSearchFromShelf('search17', 'search18');
        await surveyStep(
          tester,
          area: _area,
          key: 'search19',
          label: '點歷史關鍵字「夜」，開始搜尋',
          action: () => tester.tap(
            find.descendant(
              of: find.byType(SearchHistoryView),
              matching: find.text('夜'),
            ),
          ),
          until: () => _search()?.isSearching ?? false,
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search20',
          label: '搜尋途中按「停止」',
          action: () => tester.tap(inSearchBar('停止')),
          until: () {
            final p = _search();
            return p != null && !p.isSearching && surveyQuiet();
          },
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'search21',
          label: '點「取消」，離開搜尋',
          action: () => tester.tap(inSearchBar('取消')),
        );
      },
    );
  });
}
