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
import 'package:night_reader/shared/widgets/skeleton.dart';

import '../support/app_harness.dart';
import '../support/screenshot.dart';

typedef Steps = Future<void> Function(WidgetTester tester);

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first, warnIfMissed: false);
  await settle(tester, const Duration(milliseconds: 900));
}

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  final byTooltip = find.byTooltip(tooltip);
  await tester.tap(
    byTooltip.evaluate().isNotEmpty
        ? byTooltip.last
        : find.bySemanticsLabel(tooltip).last,
    warnIfMissed: false,
  );
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
    await showReaderMenu(t);
    await _tapText(t, '排版');
  },
  'search': (t) async => _tapTooltip(t, '搜尋'),
  'marks': (t) async => _openMine(t, '書籤與標註'),
  'appearance': (t) async => _openMine(t, '外觀與主題'),
};

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
