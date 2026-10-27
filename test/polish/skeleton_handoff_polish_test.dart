// 細節檢查：骨架換成內容時長度與位置對不對得上（`test/support/skeleton_handoff.dart`）。
// 每個情境照真的流程操作，淺色、深色各跑一次。
//
//   flutter test --run-skipped -t polish test/polish
//   POLISH_ONLY=open-a flutter test --run-skipped -t polish test/polish
//   POLISH_MODES=light flutter test --run-skipped -t polish test/polish
//
// 結果印在輸出裡（`POLISH` 開頭的行），截圖與資料寫在 [polishDir]
// （系統暫存區，不在 repo 裡），`tool/polish_viewer/` 拿它做成總覽頁。這組測試
// 帶 `polish` 標籤，`dart_test.yaml` 讓它平常跳過。
//
// 每一次執行前都把書的閱讀位置、偏好與快取重設成同一個起點，所以淺色、深色
// 條件一樣，情境之間互不影響。
//
// 不量「電量晚到」：閱讀器一訂閱電量，原生端就立刻送出目前的電量（Android
// 是系統留著的最後一筆電量廣播，iOS 直接回報），骨架畫出來時電量已經在了。
// 也不量拖進度條：進度條只在本章內換位置（`commitChapterPercent`），不會出現
// 骨架。
@Tags(['polish'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';
import '../support/skeleton_handoff.dart';

/// 細節檢查的輸出資料夾。
final Directory polishDir = Directory(
  '${Directory.systemTemp.path}${Platform.pathSeparator}night-reader-polish',
);

typedef Steps = Future<void> Function(WidgetTester tester);

/// 頁首頁尾放滿每一種欄位：A、B 兩組合起來八種都有。代碼見
/// `ReaderV2InfoItem`。
const _infoA = <String, Object>{
  PreferKey.readerHeaderInfo: '2,8', // 書名｜電量（含圖示）
  PreferKey.readerFooterInfo: '3,6', // 章節名稱｜全書進度
};
const _infoB = <String, Object>{
  PreferKey.readerHeaderInfo: '4,1', // 章節序號｜時間
  PreferKey.readerFooterInfo: '5,7', // 本章進度｜電量
};

/// 一個情境：[before] 在書架或閱讀器停好之後做的事（不算在要看的那一下裡），
/// [action] 是要看的那一下。
class _Scenario {
  const _Scenario(
    this.title,
    this.action, {
    this.prefs = _infoA,
    this.before = _none,
    this.textScale = 1.0,
  });

  /// 總覽頁上顯示的說明。
  final String title;
  final Map<String, Object> prefs;
  final Steps before;
  final Steps action;

  /// 系統字型放大倍率（[TestPlatformDispatcher.textScaleFactorTestValue]）。
  final double textScale;
}

Future<void> _none(WidgetTester tester) async {}

Future<void> _tapBook(WidgetTester tester) =>
    tester.tap(find.text('夜雨聽書').first);

/// 讀過一次再回書架：閱讀器記下了離開時那一頁，下次開書骨架照它畫。
Future<void> _readOnceAndBack(WidgetTester tester) async {
  await openReader(tester);
  await goBack(tester);
  await settle(tester, const Duration(milliseconds: 1500));
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.longPress(find.text('夜雨聽書').first);
  await settle(tester, const Duration(milliseconds: 900));
  await tester.tap(find.text('書籍詳情'));
  await settle(tester, const Duration(milliseconds: 1500));
}

Future<void> _openMenu(WidgetTester tester) async {
  await openReader(tester);
  await showReaderMenu(tester);
}

/// 選單的「目錄」，抽屜開好。
Future<void> _openToc(WidgetTester tester) async {
  await _openMenu(tester);
  await tester.tap(find.text('目錄'));
  await settle(tester, const Duration(milliseconds: 1200));
}

/// 選單的「排版」，面板開好（字號、行高、邊距都在上面）。
Future<void> _openTypography(WidgetTester tester) async {
  await _openMenu(tester);
  await tester.tap(find.text('排版'));
  await settle(tester, const Duration(milliseconds: 1200));
}

/// 按「開始自動翻頁」（選單隨即收起），翻一陣子後再叫出選單。
Future<void> _startAutoPage(WidgetTester tester) async {
  await _openMenu(tester);
  await tester.tap(find.byTooltip('開始自動翻頁'));
  await settle(tester, const Duration(milliseconds: 1500));
  await showReaderMenu(tester);
}

/// 書架上的書超出第一屏時先滾到它，等書架停穩再點（還在慣性滑動時點會點
/// 到書滑走前的位置）。
Future<void> _tapOnShelf(WidgetTester tester, String name) async {
  final shelf = find
      .descendant(
        of: find.byType(BookshelfPage),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(find.text(name), 300, scrollable: shelf);
  await settle(tester, const Duration(milliseconds: 800));
  await tester.tap(find.text(name).first);
}

/// 同一列裡的「加」鈕（步進列的加號沒有 Tooltip，只有語意標籤）。
Finder _stepUp(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
  matching: find.byIcon(Icons.add_rounded),
);

// 額外加進書架的書（見 [_seedExtraBooks]）。
const _newBook = '剛加入的新書';
const _longBook = '章名很長的書';
const _siteBook = '網路上的書';
const _missBook = '抓不到正文的書';
const _localBook = '西游记';

final String _localTxtPath =
    '${Directory.current.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}西游记.txt';

const _siteBookUrl = '$kSiteOrigin/book/1/';
const _missBookUrl = '$kSiteOrigin/missing/';

/// 這次執行加進書架的書（重設時整本寫回去，回到剛加入的樣子）。
final _extraBooks = <Book>[];

/// 情境清單，順序就是執行順序。
final scenarios = <String, _Scenario>{
  'open-a': _Scenario('書架開書（A 組欄位）', _tapBook),
  'open-b': _Scenario('書架開書（B 組欄位）', _tapBook, prefs: _infoB),
  'reopen-a': _Scenario('讀過再開（A 組欄位）', _tapBook, before: _readOnceAndBack),
  'reopen-b': _Scenario(
    '讀過再開（B 組欄位）',
    _tapBook,
    prefs: _infoB,
    before: _readOnceAndBack,
  ),
  'detail-a': _Scenario(
    '書籍詳情「繼續閱讀」（A 組欄位）',
    (t) => t.tap(find.text('繼續閱讀')),
    before: _openDetail,
  ),
  'next-a': _Scenario(
    '選單「下一章」（A 組欄位）',
    (t) => t.tap(find.text('下一章')),
    before: _openMenu,
  ),
  'next-b': _Scenario(
    '選單「下一章」（B 組欄位）',
    (t) => t.tap(find.text('下一章')),
    prefs: _infoB,
    before: _openMenu,
  ),
  'prev-a': _Scenario(
    '選單「上一章」（A 組欄位）',
    (t) => t.tap(find.text('上一章')),
    before: _openMenu,
  ),
  'toc-a': _Scenario(
    '目錄抽屜點另一章（A 組欄位）',
    (t) => t.tap(find.text('第六章 祖父的信')),
    before: _openToc,
  ),
  'font-a': _Scenario(
    '閱讀中加大字號（A 組欄位）',
    (t) => t.tap(_stepUp('字號')),
    before: _openTypography,
  ),
  'margin-a': _Scenario(
    '閱讀中加大左右邊距（A 組欄位）',
    (t) => t.tap(_stepUp('左右邊距')),
    before: _openTypography,
  ),
  'new-a': _Scenario('剛加入書架、從沒讀過的書（A 組欄位）', (t) => _tapOnShelf(t, _newBook)),
  'long-a': _Scenario('章名很長，被刪節號截掉（A 組欄位）', (t) => _tapOnShelf(t, _longBook)),
  'net-a': _Scenario('正文要從網路抓（A 組欄位）', (t) => _tapOnShelf(t, _siteBook)),
  'net-miss-a': _Scenario('正文抓不到（A 組欄位）', (t) => _tapOnShelf(t, _missBook)),
  'tc-a': _Scenario(
    '簡繁轉換開著，繁轉簡（A 組欄位）',
    _tapBook,
    prefs: {..._infoA, PreferKey.readerChineseConvert: 2},
  ),
  'hide-a': _Scenario(
    '隱藏系統狀態列（A 組欄位）',
    _tapBook,
    prefs: {..._infoA, PreferKey.readerHideStatusBar: true},
  ),
  'auto-a': _Scenario(
    '自動翻頁中再跳章（A 組欄位）',
    (t) => t.tap(find.text('下一章')),
    before: _startAutoPage,
  ),
  'only-header-a': _Scenario(
    '只開頁首，頁尾關閉（A 組欄位的頁首）',
    _tapBook,
    prefs: {
      PreferKey.readerHeaderInfo: '2,8',
      PreferKey.readerFooterInfo: '0,0',
    },
  ),
  'only-footer-a': _Scenario(
    '只開頁尾，頁首關閉（A 組欄位的頁尾）',
    _tapBook,
    prefs: {
      PreferKey.readerHeaderInfo: '0,0',
      PreferKey.readerFooterInfo: '3,6',
    },
  ),
  'one-column-a': _Scenario(
    '左右只放一欄：頁首只放左邊、頁尾只放右邊',
    _tapBook,
    prefs: {
      PreferKey.readerHeaderInfo: '2,0',
      PreferKey.readerFooterInfo: '0,5',
    },
  ),
  'local-a': _Scenario(
    '本機 TXT 書《西遊記》（A 組欄位）',
    (t) => _tapOnShelf(t, _localBook),
  ),
  'textscale-a': _Scenario('系統字型放大到 1.5 倍（A 組欄位）', _tapBook, textScale: 1.5),
};

/// 一本書放進書架。[readIndex] 是讀到第幾章（null 是剛加入、沒讀過）；
/// [withContent] 為 false 時正文不存進資料庫，要從網路抓。
Future<void> _seedBook({
  required String name,
  required String bookUrl,
  required String origin,
  required String originName,
  required List<String> titles,
  int? readIndex,
  bool withContent = true,
}) async {
  final now = DateTime(2026, 10, 15, 21).millisecondsSinceEpoch;
  final book = Book(
    bookUrl: bookUrl,
    origin: origin,
    originName: originName,
    name: name,
    author: '測試',
    latestChapterTitle: titles.last,
    totalChapterNum: titles.length,
    chapterIndex: readIndex ?? 0,
    durChapterTitle: readIndex == null ? null : titles[readIndex],
    durChapterTime: readIndex == null ? 0 : now,
    isInBookshelf: true,
  );
  final chapters = [
    for (final (i, title) in titles.indexed)
      BookChapter(
        url: '${bookUrl}c$i.html',
        title: title,
        bookUrl: bookUrl,
        index: i,
      ),
  ];
  // 同加入書架：照目錄記下目前那一章的章名。
  book.fillChapterTitle(chapters);
  _extraBooks.add(book);
  await getIt<BookDao>().upsertAll([book]);
  await getIt<ChapterDao>().insertChapters(chapters);
  if (!withContent) return;
  final store = ReaderChapterContentStore(
    chapterDao: getIt<ChapterDao>(),
    contentDao: getIt<ReaderChapterContentDao>(),
  );
  for (final chapter in chapters) {
    await store.saveRawContent(
      book: book,
      chapter: chapter,
      content: chapterText(chapter.index),
      saveChapterMetadata: false,
    );
  }
}

/// 情境用的額外書：剛加入的新書、章名很長的書、網路上的書（正文要抓）、抓
/// 不到正文的書、本機 TXT。在 `runAsync` 裡、[seedLibrary] 之後呼叫。
Future<void> _seedExtraBooks() async {
  await _seedBook(
    name: _newBook,
    bookUrl: 'https://www.example.com/book/4000/',
    origin: kOrigin,
    originName: '筆趣閣',
    titles: [for (var i = 0; i < 12; i++) '第${i + 1}章 初見'],
  );
  await _seedBook(
    name: _longBook,
    bookUrl: 'https://www.example.com/book/4001/',
    origin: kOrigin,
    originName: '筆趣閣',
    readIndex: 2,
    titles: [
      for (var i = 0; i < 12; i++)
        i == 2 ? '第3章 這一章的章名非常非常長，長到頁尾一定放不下，只能讓刪節號截掉' : '第${i + 1}章 短',
    ],
  );
  await _seedBook(
    name: _siteBook,
    bookUrl: _siteBookUrl,
    origin: kSiteOrigin,
    originName: kSiteName,
    withContent: false,
    // 和假網站的目錄一樣（`installFakeSite`）：開書時重抓目錄，章名不會變。
    titles: [for (var i = 0; i < 800; i++) '第${i + 1}章 書頁之間（$i）'],
  );
  await _seedBook(
    name: _missBook,
    bookUrl: _missBookUrl,
    origin: kSiteOrigin,
    originName: kSiteName,
    withContent: false,
    titles: [for (var i = 0; i < 12; i++) '第${i + 1}章 抓不到'],
  );
  await seedSiteSource();
  await installFakeSite();
  // 同書架的「匯入本機書」：解析完把書和目錄一起存進書架。
  final imported = (await LocalBookService().importBook(_localTxtPath))!;
  imported.book.fillChapterTitle(imported.chapters);
  _extraBooks.add(imported.book);
  await getIt<BookDao>().upsertAll([imported.book]);
  await getIt<ChapterDao>().insertChapters(imported.chapters);
}

/// 每次執行前把書回到同一個起點：書架上的位置、從網路抓來的正文快取（要重新
/// 抓，才量得到抓的過程）。在 `runAsync` 裡呼叫。
Future<void> _resetBooks() async {
  final dao = getIt<BookDao>();
  await dao.updateProgress(kBookUrl, 2, kChapterTitles[2], 0);
  await dao.upsertAll(_extraBooks);
  await getIt<ReaderChapterContentDao>().deleteByBook(
    kSiteOrigin,
    _siteBookUrl,
  );
  await getIt<ReaderChapterContentDao>().deleteByBook(
    kSiteOrigin,
    _missBookUrl,
  );
}

void main() {
  setUpAll(loadScreenshotFonts);
  final only = Platform.environment['POLISH_ONLY']?.split(',');
  final modes =
      Platform.environment['POLISH_MODES']?.split(',') ??
      const ['light', 'dark'];

  // 全部情境在同一個測試裡依序跑，理由同 `test/screens/app_screens_test.dart`。
  testWidgets('skeleton handoff', (tester) async {
    setUpPhone(tester);
    mockBattery();
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await _seedExtraBooks();
      if (polishDir.existsSync()) polishDir.deleteSync(recursive: true);
      polishDir.createSync(recursive: true);
    });
    final runs = <Map<String, Object?>>[];
    final selected = [
      for (final name in scenarios.keys)
        if (only == null || only.any(name.startsWith)) name,
    ];
    var done = 0;
    for (final name in selected) {
      final scenario = scenarios[name]!;
      for (final mode in modes) {
        final run = '$name-$mode';
        await tester.runAsync(() async {
          await resetPrefs({'themeMode': mode, ...scenario.prefs});
          await _resetBooks();
        });
        tester.platformDispatcher.textScaleFactorTestValue = scenario.textScale;
        await pumpApp(tester);
        // 情境的操作找不到東西（例如按鈕不在畫面上）只記下來，不讓整個測試停掉，
        // 後面的情境照常跑。
        SkeletonHandoffWatch? watch;
        String? error;
        try {
          await scenario.before(tester);
          watch = await watchSkeletonHandoffs(
            tester,
            () => scenario.action(tester),
            capture: (shot) async => (await saveScreenshot(
              tester,
              '$run-$shot',
              dir: polishDir,
            )).path,
          );
        } catch (e) {
          error = '$e'.split('\n').first;
        }
        done += 1;
        if (watch == null) {
          // ignore: avoid_print
          print(
            'POLISH $done/${selected.length * modes.length} $run：操作失敗：$error',
          );
          runs.add({
            'scenario': name,
            'title': scenario.title,
            'mode': mode,
            'infoSlots': scenario.prefs,
            'check': 'skeleton_handoff',
            'error': error,
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester, const Duration(milliseconds: 300));
          continue;
        }
        final findings = watch.findings();
        // 沒看到骨架時留下最後的畫面，總覽頁上看得到那時畫面上是什麼。
        final endImage = watch.sawAny
            ? null
            : (await saveScreenshot(tester, '$run-end', dir: polishDir)).path;
        // ignore: avoid_print
        print(
          'POLISH $done/${selected.length * modes.length} $run：'
          '${!watch.sawAny
              ? '沒看到骨架（最後的畫面：$endImage）'
              : findings.isEmpty
              ? '全部對得上'
              : '${findings.length} 處對不上'}',
        );
        for (final finding in findings) {
          // ignore: avoid_print
          print('POLISH   ${finding.replaceAll('\n', '\nPOLISH   ')}');
        }
        runs.add({
          'scenario': name,
          'title': scenario.title,
          'mode': mode,
          'infoSlots': scenario.prefs,
          'check': 'skeleton_handoff',
          'sawSkeleton': watch.sawAny,
          'endImage': endImage,
          'slots': watch.toJson(),
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester, const Duration(milliseconds: 300));
      }
    }
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.runAsync(
      () =>
          File('${polishDir.path}${Platform.pathSeparator}report.json')
              .writeAsString(const JsonEncoder.withIndent(' ').convert(runs)),
    );
    // 讓 App 留下的計時器（下載排程、重試）跑完，測試才能正常結束。
    await tester.pump(const Duration(minutes: 1));
  });
}
