// 搜尋頁：進頁、送出搜尋後幾十個書源、幾百筆結果陸續到達（合併同一本書、
// 重排、建卡）、搜尋結束時進度與工具列交叉淡換、改排序與篩選整個清單重建、
// 建議清單蓋上與收起、捲動後固定順序再接尾端，每一幀的成本（ADR 0018、
// 0029）。用法見 `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，
// 平常的全套測試跳過。
//
// 書源的回應直接從記憶體給（App 裡在書源 isolate 解析，主執行緒只收結果），
// 每個書源晚 0.1–0.6 秒回來，同時最多 8 個（`thread_count` 預設），60 個書源
// 約 2.5 秒搜完；書名從 150 個裡取，同一本書會從好幾個書源回來，合併成一張卡。
@Tags(['frame_budget'])
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:night_reader/features/search/widgets/search_app_bar.dart';
import 'package:night_reader/features/search/widgets/search_suggestion_view.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

const _sourceCount = 60;
const _booksPerSource = 8;
const _nameCount = 150;

BookSource _source(int i) => BookSource.fromJson({
  'bookSourceUrl': 'https://s$i.example',
  'bookSourceName': '書源 $i',
  'customOrder': i,
  'searchUrl': '/search?q={{key}}',
  'ruleSearch': {'bookList': 'class.item', 'name': 'class.name@text'},
});

/// 關鍵字「夜」：完全相符、部分相符與其他結果，三段都有。
String _bookName(int n) => switch (n % 3) {
  _ when n == 0 => '夜',
  0 => '夜讀第$n卷',
  1 => '長夜$n書',
  _ => '第$n本書的書名',
};

List<SearchBook> _answer(BookSource source) {
  final i = source.customOrder;
  return [
    for (var b = 0; b < _booksPerSource; b++)
      SearchBook(
        bookUrl: '${source.bookSourceUrl}/book/${(i * 5 + b * 7) % _nameCount}',
        name: _bookName((i * 5 + b * 7) % _nameCount),
        author: '作者${(i * 5 + b * 7) % _nameCount % 40}',
        kind: '仙俠,連載',
        wordCount: '${120 + b}.6萬字',
        latestChapterTitle: '第${300 + i + b}章 夜深了',
        origin: source.bookSourceUrl,
        originName: source.bookSourceName,
        originOrder: i,
      ),
  ];
}

Future<List<SearchBook>> _loader(
  BookSource source,
  String key, {
  CancelToken? cancelToken,
}) => Future.delayed(
  Duration(milliseconds: 100 + (source.customOrder * 37) % 500),
  () => _answer(source),
);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('searching 60 sources while results stream in', (tester) async {
    setUpScreenshot(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await getIt<BookSourceDao>().deleteByUrls([
        kOrigin,
        'https://www.sample.org',
      ]);
      await getIt<BookSourceDao>().upsertAll([
        for (var i = 0; i < _sourceCount; i++) _source(i),
      ]);
      // 繁簡字典在開 App 時背景載入；這裡先載好，不算進搜尋的那幾幀。
      try {
        await ChineseUtils.initialize();
      } catch (_) {}
    });

    // 第一輪含 debug 模式第一次執行程式的編譯成本，只暖機；看第二輪。
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
                      builder: (_) => ChangeNotifierProvider(
                        create: (context) => SearchProvider(
                          entrance: TransitionSettled.entered(context),
                          searchLoader: _loader,
                        ),
                        child: const SearchView(),
                      ),
                    ),
                  ),
                  child: const Text('打開搜尋'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await measureNavigation(
        tester,
        '$round 進搜尋頁',
        action: () => tester.tap(find.text('打開搜尋')),
        page: find.byType(SearchView),
      );
      await rest(tester);
      final provider = Provider.of<SearchProvider>(
        tester.element(find.byType(SearchView)),
        listen: false,
      );
      await tester.runAsync(() => provider.ready);

      String? progress() => provider.isSearching
          ? '搜尋中 ${provider.completedSources}/${provider.totalSources}，'
                '${provider.results.length} 本'
          : '結束，${provider.results.length} 本';
      final searchButton = find.descendant(
        of: find.byType(SearchAppBar),
        matching: find.text('搜尋'),
      );

      await tester.enterText(find.byType(TextField), '夜');
      await tester.pump();
      await measureActivity(
        tester,
        '$round 搜尋「夜」到結束',
        action: () => tester.tap(searchButton),
        until: () => !provider.isSearching && provider.totalSources > 0,
        note: progress,
      );
      expect(provider.results.length, greaterThan(100));
      expect(provider.completedSources, _sourceCount);
      expect(provider.totalSources, _sourceCount);
      expect(provider.failedSources, 0);
      await rest(tester);

      await measureActivity(
        tester,
        '$round 改排序為書名',
        action: () => provider.updateSortMode(SearchResultSortMode.name),
        tailFrames: 40,
      );
      expect(provider.sortMode, SearchResultSortMode.name);
      await measureActivity(
        tester,
        '$round 改回相關度',
        action: () => provider.updateSortMode(SearchResultSortMode.relevance),
        tailFrames: 40,
      );
      expect(provider.sortMode, SearchResultSortMode.relevance);
      await measureActivity(
        tester,
        '$round 只看已加入書架',
        action: () => provider.setOnlyInBookshelf(true),
        tailFrames: 40,
      );
      expect(provider.results, isEmpty);
      await measureActivity(
        tester,
        '$round 清除篩選',
        action: provider.clearResultFilters,
        tailFrames: 40,
      );
      expect(provider.results.length, greaterThan(100));

      // 建議清單：打一個還沒搜過的詞蓋上，收起鍵盤後收起。
      await measureActivity(
        tester,
        '$round 打字叫出建議',
        action: () async {
          await tester.tap(find.byType(TextField));
          await tester.enterText(find.byType(TextField), '夜雨');
        },
        tailFrames: 40,
      );
      expect(find.byType(SearchSuggestionView), findsOneWidget);
      await measureActivity(
        tester,
        '$round 收起建議',
        action: () => FocusManager.instance.primaryFocus?.unfocus(),
        tailFrames: 40,
      );
      expect(find.byType(SearchSuggestionView), findsNothing);

      // 再搜一次：結果開始進來後捲一下，順序固定，之後的結果接在尾端。
      await tester.enterText(find.byType(TextField), '夜');
      await tester.pump();
      await measureActivity(
        tester,
        '$round 再搜尋到首批結果',
        action: () => tester.tap(searchButton),
        until: () => provider.results.length > 10,
        note: progress,
        tailFrames: 0,
      );
      await measureActivity(
        tester,
        '$round 搜尋途中捲動固定順序',
        action: () => tester.drag(find.byType(ListView), const Offset(0, -300)),
        until: () => !provider.isSearching && provider.totalSources > 0,
        note: progress,
      );
      expect(provider.resultOrderHeld, isTrue);
      expect(provider.completedSources, _sourceCount);
      expect(provider.results.length, greaterThan(100));
      await rest(tester);

      await measureNavigation(
        tester,
        '$round 搜尋頁返回',
        action: () => goBack(tester),
        settled: () => find.text('打開搜尋').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }
    await tearDownApp(tester);
  });
}
