// 網站原型用的 App 畫面（只在 prototype/website-redesign 分支）。
//
//   flutter test --run-skipped -t screens test/screens/website_shots_test.dart
//   SHOT_MODE=dark SHOT_STYLE=tea flutter test --run-skipped -t screens test/screens/website_shots_test.dart
//
// 和 app_screens_test 同一套 App，書架換成像樣的書名與封面，正文畫兩段標註、
// 留一個書籤。圖檔寫在 screenshotDir，檔名是「web_情境_風格_深淺.png」。
@Tags(['screens'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:night_reader/features/search/widgets/search_app_bar.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/screenshot.dart';

typedef Steps = Future<void> Function(WidgetTester tester);

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first, warnIfMissed: false);
  await settle(tester, const Duration(milliseconds: 900));
}

Future<void> _openMine(WidgetTester tester, String row) async {
  await _tapText(tester, '我的');
  await _tapText(tester, row);
  for (var i = 0; i < 100; i++) {
    if (find.byType(SkeletonShapes).evaluate().isEmpty) break;
    await settle(tester, const Duration(milliseconds: 100));
  }
}

final _scenes = <String, Steps>{
  'shelf': (t) async {},
  'reader': (t) async => openReader(t),
  'layout': (t) async {
    await openReader(t);
    // 畫面正中間是標註，點了會開標註面板；點中間偏上沒有標註的那行。
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    await t.tapAt(Offset(size.width / 2, size.height * 0.42));
    await settle(t, const Duration(milliseconds: 800));
    await waitForText(t);
    await _tapText(t, '排版');
  },
  'search': _searchResults,
  'marks': (t) async => _openMine(t, '書籤與標註'),
  'appearance': (t) async => _openMine(t, '外觀與主題'),
};

/// 搜尋「夜」：兩個書源各回幾本，同一本書從兩個書源回來合併成一張卡。
/// 書源的回應從記憶體給（同 search_frame_budget_test）。
const _searchAnswers = {
  kOrigin: [
    ('夜雨聽書', '沈知秋', '第一百二十章 書頁之間'),
    ('長夜行舟', '林晚', '第八十六章 渡口'),
    ('夜航船記', '青衫客', '第四十二章 潮聲'),
    ('守夜人手記', '周以寧', '第二百零三章 燈'),
  ],
  'https://www.sample.org': [
    ('夜雨聽書', '沈知秋', '第一百二十章 書頁之間'),
    ('春夜喜雨', '沈默', '第十九章 隨風'),
    ('夜行者', '陸遠', '第六十章 天亮以前'),
  ],
};

Future<List<SearchBook>> _searchLoader(
  BookSource source,
  String key, {
  CancelToken? cancelToken,
}) => Future.delayed(const Duration(milliseconds: 200), () {
  final answers = _searchAnswers[source.bookSourceUrl] ?? const [];
  return [
    for (final (i, (name, author, latest)) in answers.indexed)
      SearchBook(
        bookUrl: '${source.bookSourceUrl}/book/$name',
        name: name,
        author: author,
        kind: '連載',
        wordCount: '${80 + i * 37}.2萬字',
        latestChapterTitle: latest,
        origin: source.bookSourceUrl,
        originName: source.bookSourceName,
      ),
  ];
});

/// 搜尋頁換成上面那組書源回應，主題沿用 App 這次的主題。
Future<void> _searchResults(WidgetTester tester) async {
  final theme = Theme.of(tester.element(find.byType(Scaffold).first));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChangeNotifierProvider(
                  create: (context) => SearchProvider(
                    entrance: TransitionSettled.entered(context),
                    searchLoader: _searchLoader,
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
  );
  await tester.pump();
  await _tapText(tester, '打開搜尋');
  final provider = Provider.of<SearchProvider>(
    tester.element(find.byType(SearchView)),
    listen: false,
  );
  await tester.runAsync(() => provider.ready);
  await tester.enterText(find.byType(TextField), '夜');
  await tester.pump();
  await tester.tap(
    find.descendant(of: find.byType(SearchAppBar), matching: find.text('搜尋')),
  );
  for (
    var i = 0;
    i < 100 && (provider.isSearching || provider.results.isEmpty);
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await settle(tester, const Duration(milliseconds: 100));
  }
  // 收起鍵盤與建議，只留結果。
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester, const Duration(milliseconds: 600));
}

Future<void> _seedShowcase() async {
  await getIt<BookSourceDao>().upsertAll([
    BookSource(bookSourceUrl: kOrigin, bookSourceName: '示範書源'),
    BookSource(
      bookSourceUrl: 'https://www.sample.org',
      bookSourceName: '常用書源',
      bookSourceGroup: '常用',
    ),
  ]);
  final dao = getIt<BookDao>();
  final names = [
    ('霧港來信', '林晚'),
    ('山海舊聞錄', '青衫客'),
    ('長街燈火', '周以寧'),
    ('星河彼岸', '陸遠'),
    ('北窗夜話', '沈默'),
  ];
  final books = await dao.getInBookshelf();
  await dao.upsertAll([
    for (final book in books)
      if (book.name == '夜雨聽書')
        book.copyWith(originName: '示範書源')
      else
        book.copyWith(
          name:
              names[(int.parse(book.bookUrl.split('/')[4]) - 2000) %
                      names.length]
                  .$1,
          author:
              names[(int.parse(book.bookUrl.split('/')[4]) - 2000) %
                      names.length]
                  .$2,
          originName: '示範書源',
        ),
  ]);
  final text = chapterText(2);
  int at(String quote) => text.indexOf(quote);
  const q1 = '匣蓋縫隙裡透出一股陳年的墨香';
  const q2 = '匣面刻著三個小字：『聽雨樓』';
  await getIt<HighlightDao>().upsertAll([
    Highlight(
      id: 1,
      bookName: '夜雨聽書',
      bookAuthor: '沈知秋',
      chapterIndex: 2,
      chapterTitle: kChapterTitles[2],
      charOffset: at(q1) + 12,
      quote: q1,
      note: '松煙墨的味道，後面還會再出現。',
    ),
    Highlight(
      id: 2,
      bookName: '夜雨聽書',
      bookAuthor: '沈知秋',
      chapterIndex: 2,
      chapterTitle: kChapterTitles[2],
      charOffset: at(q2) + 9,
      quote: q2,
      color: HighlightColor.blue,
      style: HighlightStyle.underline,
    ),
  ]);
  const b1 = '少年搖頭：「我只知道，祖父臨走前說，這匣書要交給一個肯在夜裡讀書的人。」';
  await getIt<BookmarkDao>().upsertAll([
    Bookmark(
      id: 3,
      bookName: '夜雨聽書',
      bookAuthor: '沈知秋',
      chapterIndex: 2,
      chapterTitle: kChapterTitles[2],
      charOffset: at(b1) + 16,
      excerpt: b1,
    ),
  ]);
}

void main() {
  setUpAll(loadScreenshotFonts);
  final mode = Platform.environment['SHOT_MODE'] ?? 'light';
  final style = Platform.environment['SHOT_STYLE'];
  final only = Platform.environment['SHOT_ONLY']?.split(',');

  testWidgets('website shots', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await _seedShowcase();
    });
    for (final MapEntry(key: name, value: steps) in _scenes.entries) {
      if (only != null && !only.contains(name)) continue;
      await tester.runAsync(
        () => resetPrefs({
          // 照 App 的預設玻璃（測試環境預設用霧面）。
          PreferKey.glassStrength: GlassStrength.defaultStrength.name,
          'themeMode': mode,
          PreferKey.lightStyle: ?style,
          PreferKey.darkStyle: ?style,
        }),
      );
      await pumpApp(tester);
      await steps(tester);
      if (name == 'reader' || name == 'layout') await waitForText(tester);
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await settle(tester, const Duration(milliseconds: 100));
      }
      await shot(tester, 'web_${name}_${style ?? 'default'}_$mode');
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(minutes: 1));
  });
}
