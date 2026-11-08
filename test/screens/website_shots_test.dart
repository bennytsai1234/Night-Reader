// 網站（website/）用的 App 畫面與短片。
//
//   flutter test --run-skipped -t screens test/screens/website_shots_test.dart
//   SHOT_ONLY=launch,reader-kraft_light flutter test --run-skipped -t screens test/screens/website_shots_test.dart
//
// 和 app_screens_test 同一套 App，書架換成像樣的書名與封面，正文畫兩段標註、
// 留一個書籤，正文照網站的排版（字大、兩側留白）。圖檔寫在
// screenshotDir/web/<名稱>.png，短片的每一格寫在 screenshotDir/web-clips/<名稱>/；
// 之後用 tool/website_preview/shots.py 縮成網站用的 webp 與 mp4。
@Tags(['screens'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/audio_handler.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content_transformer.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:night_reader/features/search/widgets/search_app_bar.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_text.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/screenshot.dart';

typedef Steps = Future<void> Function(WidgetTester tester);

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).first, warnIfMissed: false);
  await settle(tester, const Duration(milliseconds: 900));
}

/// 點右邊留白叫出閱讀選單：那裡沒有字，不會點到標註（點到會開標註面板），
/// 九宮格的每一格預設都是叫出選單。
Future<void> _showMenu(WidgetTester tester) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(size.width - 4, size.height / 2));
  await settle(tester, const Duration(milliseconds: 800));
  await waitForText(tester);
}

/// 等骨架換成內容。
Future<void> _waitSkeletons(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    if (find.byType(SkeletonShapes).evaluate().isEmpty) break;
    await settle(tester, const Duration(milliseconds: 100));
  }
  await settle(tester, const Duration(milliseconds: 800));
}

Future<void> _openMine(WidgetTester tester, String row) async {
  await _tapText(tester, '我的');
  await _tapText(tester, row);
  await _waitSkeletons(tester);
}

/// 錄短片：每一格（約 30 fps）存成 PNG，接在同一個資料夾裡；資料庫在真的
/// isolate 裡，每格讓出時間。
class _Recorder {
  _Recorder(this.tester, String name)
    : dir = Directory(
        '${screenshotDir.path}${Platform.pathSeparator}web-clips'
        '${Platform.pathSeparator}$name',
      ) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  }

  final WidgetTester tester;
  final Directory dir;
  var _frame = 0;

  static const step = Duration(milliseconds: 33);

  /// 錄 [length]；[onFrame] 在每格畫之前呼叫（這段裡的第幾格）。
  Future<void> run(Duration length, {void Function(int i)? onFrame}) async {
    final frames = length.inMilliseconds ~/ step.inMilliseconds;
    for (var i = 0; i < frames; i++) {
      onFrame?.call(i);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(step);
      await saveScreenshot(tester, 'f${'$_frame'.padLeft(4, '0')}', dir: dir);
      _frame++;
    }
  }
}

typedef _Clip = Future<void> Function(WidgetTester tester, _Recorder r);

/// 網站上的一張畫面或一段短片。[steps] 把畫面擺好（App 已經開好、在書架）；
/// 有 [clip] 時接著由它做動作、錄影，沒有就拍一張。[launch] 的短片錄的是
/// 開 App 本身。[tablet] 用平板的尺寸拍。
class _Shot {
  const _Shot(
    this.name, {
    this.steps,
    this.clip,
    this.mode = 'dark',
    this.prefs = const {},
    this.launch = false,
    this.tablet = false,
  });

  final String name;
  final Steps? steps;
  final _Clip? clip;
  final String mode;
  final Map<String, Object> prefs;
  final bool launch;
  final bool tablet;
}

const _styles = ['plain', 'paper', 'tea', 'kraft', 'bamboo', 'bean'];

Duration _ms(int ms) => Duration(milliseconds: ms);

final _shots = <_Shot>[
  const _Shot('launch', launch: true),
  _Shot(
    'open',
    // 先開一次再返回：測試裡第一次開書要等真的排版（手機上快得多），骨架會
    // 停很久；開過的書排版有快取，和手機上平常開書一樣。
    steps: (t) async {
      await openReader(t);
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await settle(t, _ms(1500));
    },
    clip: (t, r) async {
      await r.run(_ms(400));
      await t.tap(find.text('夜雨聽書').first);
      await r.run(_ms(5200));
    },
  ),
  for (final style in _styles)
    for (final mode in ['light', 'dark'])
      _Shot(
        'reader-${style}_$mode',
        steps: openReader,
        mode: mode,
        prefs: {PreferKey.lightStyle: style, PreferKey.darkStyle: style},
      ),
  // 測試裡不畫手機系統的狀態列，「顯示」那張和藏起來的看起來一樣，只拍藏起來的。
  _Shot(
    'statusbar-hidden',
    steps: openReader,
    prefs: const {PreferKey.readerHideStatusBar: true},
  ),
  const _Shot('covers-source', prefs: {'bookshelf_unified_covers': false}),
  const _Shot('covers-unified', prefs: {'bookshelf_unified_covers': true}),
  _Shot(
    'search',
    steps: _searchReady,
    clip: (t, r) async {
      await r.run(_ms(300));
      await t.tap(
        find.descendant(
          of: find.byType(SearchAppBar),
          matching: find.text('搜尋'),
        ),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await r.run(_ms(2400));
    },
  ),
  _Shot('sync-phone', steps: openReader),
  _Shot('sync-tablet', steps: openReader, tablet: true),
  _Shot(
    'tts',
    steps: (t) async {
      await openReader(t);
      await _showMenu(t);
      await _tapText(t, '朗讀');
      await _tapText(t, '從目前位置朗讀');
      // 關掉朗讀面板，只留正文與正在唸的那一句。
      await t.tap(find.byIcon(Icons.close_rounded).last);
      await settle(t, _ms(900));
      // 收起閱讀選單。
      await _showMenu(t);
    },
    // 每唸完一句（約 1.2 秒）就換下一句。
    clip: (t, r) => r.run(
      _ms(4800),
      onFrame: (i) {
        if (i > 0 && i % 36 == 0) ReaderAudioHandler.emitEvent('onComplete');
      },
    ),
  ),
  _Shot(
    'download',
    steps: (t) async {
      final service = DownloadService();
      service.tasks
        ..clear()
        ..addAll([
          for (final (i, (name, total)) in [
            ('夜雨聽書', 120),
            ('霧港來信', 86),
            ('山海舊聞錄', 203),
            ('長街燈火', 64),
          ].indexed)
            DownloadTask(
              bookUrl: 'https://www.example.com/book/dl$i/',
              bookName: name,
              totalCount: total,
              successCount: [96, 30, 12, 0][i],
              status: DownloadTask.statusDownloading,
              sortOrder: i,
            ),
        ]);
      await _openMine(t, '關於夜讀');
      await _tapText(t, '背景下載佇列');
      await _waitSkeletons(t);
    },
    clip: (t, r) => r.run(
      _ms(3600),
      onFrame: (i) {
        final service = DownloadService();
        for (final (n, task) in service.tasks.indexed) {
          // 一本接一本：前一本快好了，下一本才跑得快。
          final speed = [1, 1, 2, 1][n];
          if (i % 2 == 0) {
            task.successCount = (task.successCount + speed).clamp(
              0,
              task.totalCount,
            );
          }
          if (task.successCount == task.totalCount) {
            task.status = DownloadTask.statusCompleted;
          }
        }
        service.update();
      },
    ),
  ),
  _Shot(
    'local-toc',
    steps: (t) async {
      await openReader(t, '舊城雨季');
      await _showMenu(t);
      await _tapText(t, '目錄');
    },
  ),
  _Shot(
    'source-change',
    steps: (t) async {
      await openReader(t);
      await _showMenu(t);
      await t.tap(find.byTooltip('更多').first);
      await settle(t, _ms(700));
      await _tapText(t, '換源');
      await settle(t, _ms(1500));
      _fillChangeSource(t);
      await settle(t, _ms(800));
    },
  ),
  _Shot(
    'source-check',
    steps: (t) async {
      await t.runAsync(_seedCheckedSources);
      await _openMine(t, '書源管理');
    },
  ),
  // 下面三段改了正文與替換規則，放最後。
  // 選字隱藏用前後兩張，不錄短片：選字選單與隱藏後的提示沒有指定字型，
  // 手機上是系統字型，測試裡會畫成方塊。
  _Shot(
    'hide-before',
    steps: (t) async {
      await t.runAsync(() => _saveChapter(2, [_hideAd, ...kParagraphs]));
      await openReader(t);
    },
  ),
  _Shot(
    'hide-after',
    steps: (t) async {
      await openReader(t);
      // 廣告是這一章第一段（章名下面，y 約 203–272），長按它的第二行。
      // 測試的手勢一放開選取就消失（App 只處理長按開始，手機上放開會留著），
      // 所以按著就點「隱藏」；取消而不是放開，放開會被當成點一下正文。
      final gesture = await t.startGesture(const Offset(200, 240));
      await settle(t, _ms(1400));
      await t.tap(find.text('隱藏').first);
      await gesture.cancel();
      // 等「已隱藏」的提示收起來。
      await settle(t, _ms(8000));
    },
  ),
  _Shot(
    'clean-before',
    steps: (t) async {
      await t.runAsync(() => _saveChapter(2, _messyParagraphs));
      await openReader(t);
    },
    prefs: const {PreferKey.readerChineseConvert: 0},
  ),
  _Shot(
    'clean-after',
    steps: (t) async {
      await t.runAsync(_seedCleanRules);
      await openReader(t);
    },
  ),
];

const _hideAd = '【夜雨小說網】請記住本站網址 yeyu-novel.example，手機閱讀更方便';

/// 網站常見的樣子：簡體，段落之間夾著廣告與「本章未完」這類雜訊。
const _messyParagraphs = [
  '雨是从傍晚开始下的。沈知秋撑着一把旧油纸伞，沿着青石板路慢慢走回书铺，鞋尖早已湿透。',
  '本章未完，请点击下一页继续阅读》》》',
  '「掌柜的，今天还收书吗？」门口站着一个瘦高的少年，怀里抱着一只木匣，匣面刻着三个小字：『听雨楼』。',
  '（天才一秒记住本站地址：www.xiaoshuo-example.com 最快更新！无弹窗！）',
  '沈知秋看了他一眼，收起伞，抖落伞面上的水珠：「收。不过得先看货……你这匣子，是从哪里来的？」',
  '少年没有回答，只把木匣轻轻放在柜台上。灯火摇晃，匣盖缝隙里透出一股陈年的墨香——那是只有百年以上的松烟墨才会有的味道。',
  '手机用户请浏览阅读，更优质的阅读体验。',
  '她打开匣子，里面是一叠手抄的书稿，纸页泛黄，边角却整整齐齐。',
  '「这字迹……」沈知秋的手指停在半空，「你知道这是谁写的吗？」',
  '少年摇头：「我只知道，祖父临走前说，这匣书要交给一个肯在夜里读书的人。」',
  '窗外的雨声渐渐大了，打在屋檐上，像有人在很远的地方翻书。',
];

/// 書架上一本匯入的本地 TXT，章節是匯入時照章名自動切出來的。
Future<void> _seedLocalBook() async {
  const url = 'local://storage/emulated/0/Download/舊城雨季.txt';
  final titles = [
    '序章 雨落舊城',
    for (var i = 1; i <= 40; i++)
      '第${_cn(i)}章 ${['巷口', '舊信', '燈下', '渡口', '雨季', '茶樓', '夜車', '歸人'][i % 8]}',
  ];
  final book = Book(
    bookUrl: url,
    origin: 'local',
    originName: '本地',
    name: '舊城雨季',
    author: '本地',
    totalChapterNum: titles.length,
    durChapterTitle: titles[3],
    chapterIndex: 3,
    durChapterTime: DateTime(2026, 11, 6, 20).millisecondsSinceEpoch,
    isInBookshelf: true,
  );
  await getIt<BookDao>().upsertAll([book]);
  final chapters = [
    for (final (i, title) in titles.indexed)
      BookChapter(url: '$url#$i', title: title, bookUrl: url, index: i),
  ];
  await getIt<ChapterDao>().insertChapters(chapters);
  final store = ReaderChapterContentStore(
    chapterDao: getIt<ChapterDao>(),
    contentDao: getIt<ReaderChapterContentDao>(),
  );
  for (final chapter in chapters.take(8)) {
    await store.saveRawContent(
      book: book,
      chapter: chapter,
      content: kParagraphs.join('\n'),
      saveChapterMetadata: false,
    );
  }
}

String _cn(int n) {
  const digits = '零一二三四五六七八九';
  if (n < 10) return digits[n];
  final tens = n ~/ 10, ones = n % 10;
  return '${tens == 1 ? '' : digits[tens]}十${ones == 0 ? '' : digits[ones]}';
}

Future<void> _saveChapter(int index, List<String> paragraphs) async {
  ReaderV2ContentTransformWorker.instance.stop();
  // 示範的標註與書籤照原本的正文定位，換了正文就會畫錯地方。
  final highlights = getIt<HighlightDao>();
  await highlights.deleteByIds((await highlights.getAll()).map((h) => h.id));
  final bookmarks = getIt<BookmarkDao>();
  await bookmarks.deleteByIds((await bookmarks.getAll()).map((b) => b.id));
  // 從這一章開頭讀起：前面的情境開過這本書會記住別的位置，畫面就對不上。
  final book = (await getIt<BookDao>().getByUrl(kBookUrl))!
      .copyWith(chapterIndex: index, charOffset: 0);
  await getIt<BookDao>().upsertAll([book]);
  final chapter = (await getIt<ChapterDao>().getByBook(kBookUrl))[index];
  await ReaderChapterContentStore(
    chapterDao: getIt<ChapterDao>(),
    contentDao: getIt<ReaderChapterContentDao>(),
  ).saveRawContent(
    book: book,
    chapter: chapter,
    content: paragraphs.join('\n'),
    saveChapterMetadata: false,
  );
}

Future<void> _seedCleanRules() async {
  ReaderV2ContentTransformWorker.instance.stop();
  await getIt<ReplaceRuleDao>().upsertAll([
    ReplaceRule(id: 101, name: '本章未完', pattern: r'本章未完.*', order: 1),
    ReplaceRule(id: 102, name: '記住網址', pattern: r'（天才一秒.*?）', order: 2),
    ReplaceRule(id: 103, name: '手機用戶', pattern: r'手机用户请浏览.*', order: 3),
  ]);
}

/// 換源面板搜完之後，換成幾個書源都找到這本書的樣子。測試連不上網路，
/// 面板自己搜的每個書源都會失敗、清掉結果，所以等它搜完再把結果放進去。
void _fillChangeSource(WidgetTester tester) {
  final provider = Provider.of<BookDetailChangeSourceProvider>(
    tester.element(find.text('更換來源')),
    listen: false,
  );
  provider
    ..allResults = [
      for (final (url, name, words, latest, time) in [
        (kOrigin, '示範書源', '128.6萬字', kChapterTitles.last, 420),
        ('https://www.sample.org', '常用書源', '128.6萬字', kChapterTitles.last, 610),
        (
          'https://www.night.example',
          '松煙閣',
          '128.5萬字',
          kChapterTitles.last,
          880,
        ),
        (
          'https://www.rain.example',
          '聽雨文庫',
          '127.9萬字',
          '第119章 書頁之間（119）',
          1320,
        ),
      ])
        SearchBook(
          bookUrl: '$url/book/yeyu',
          name: '夜雨聽書',
          author: '沈知秋',
          kind: '仙俠,連載',
          wordCount: words,
          latestChapterTitle: latest,
          origin: url,
          originName: name,
          respondTime: time,
        ),
    ]
    ..status = '搜尋完成'
    ..applyFilter('');
}

/// 書源管理裡校驗過的一組書源：幾個正常，幾個標出失效的原因。
Future<void> _seedCheckedSources() async {
  await getIt<BookSourceDao>().upsertAll([
    for (final (url, name, group, error) in [
      ('https://www.night.example', '松煙閣', '常用', null),
      ('https://www.rain.example', '聽雨文庫', '常用', null),
      ('https://a.example', '晨光書屋', '異常,搜尋失效', '搜尋結果是空的'),
      ('https://b.example', '雲間小說', '異常,需要登入', null),
      ('https://c.example', '舊港文庫', '異常,網站失效', '伺服器回應錯誤（521）'),
      ('https://d.example', '北窗書局', '異常,正文失效', '正文是空的'),
      ('https://e.example', '星河書海', '', null),
    ])
      BookSource(
        bookSourceUrl: url,
        bookSourceName: name,
        bookSourceGroup: group,
        bookSourceComment: error == null ? null : '// Error: $error',
        lastUpdateTime: DateTime(2026, 11, 6, 21).millisecondsSinceEpoch,
      ),
  ]);
}

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

/// 搜尋頁換成上面那組書源回應，主題沿用 App 這次的主題；打好「夜」、
/// 還沒按搜尋（短片從按下搜尋開始錄）。
Future<void> _searchReady(WidgetTester tester) async {
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
  await settle(tester, const Duration(milliseconds: 300));
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

/// 網站上手機縮得小，正文照 App 預設排會字小、貼邊；拍網站用的畫面時字放大、
/// 兩側留白、行距放寬。
const _webTypography = <String, Object>{
  PreferKey.readerFontSize: 22.0,
  PreferKey.readerTitleFontSize: 26.0,
  PreferKey.readerPaddingHorizontal: 30.0,
  PreferKey.readerLineHeight: 1.55,
  PreferKey.readerParagraphSpacing: 0.5,
};

/// 網站上的手機：和 iPhone 一樣寬、矮一些（393×760、3 倍，1179×2280），
/// 太長看起來像遙控器。頂端是鏡頭挖孔那一條，高 27（照維護者的手機；隱藏
/// 狀態列時頁首在這一條裡），底部手勢條 16。
const _phoneSize = Size(393, 760);

void _setUpPhone(WidgetTester tester) {
  const ratio = 3.0;
  setUpScreenshot(tester, size: _phoneSize, devicePixelRatio: ratio);
  _usePhone(tester);
}

void _usePhone(WidgetTester tester) {
  const ratio = 3.0;
  tester.view
    ..devicePixelRatio = ratio
    ..physicalSize = _phoneSize * ratio;
  const padding = FakeViewPadding(top: 27 * ratio, bottom: 16 * ratio);
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
}

/// 維護者的 12.1 吋平板，直拿（800×1280、2 倍）。
void _useTablet(WidgetTester tester) {
  const ratio = 2.0;
  tester.view
    ..devicePixelRatio = ratio
    ..physicalSize = const Size(800, 1280) * ratio;
  const padding = FakeViewPadding(top: 24 * ratio, bottom: 16 * ratio);
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
}

/// 開 App 並錄下進場（同 [pumpApp]，但每一格都存下來）。
Future<void> _recordLaunch(WidgetTester tester) async {
  PunctuationInk.resetForTest(measure: false);
  addTearDown(PunctuationInk.resetForTest);
  await tester.pumpWidget(
    MultiProvider(providers: AppProviders.providers, child: const ReaderApp()),
  );
  await _Recorder(tester, 'launch').run(_ms(3000));
  await settle(tester, const Duration(milliseconds: 500));
}

/// 朗讀：手機有中文語音，`speak` 成功（每句唸完由短片自己送「唸完」）。
/// 長按選字：原生斷詞把整段廣告當成一個詞。
void _mockPhoneServices() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
    call,
  ) async {
    switch (call.method) {
      case 'getLanguages':
        return ['zh-TW', 'zh-CN'];
      case 'getVoices':
        return const [];
      case 'getEngines':
        return const [];
      case 'isLanguageAvailable':
        return true;
    }
    return 1;
  });
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.inkpage.reader/word_segmenter'),
    (call) async {
      final args = call.arguments as Map;
      final text = args['text'] as String;
      final offset = args['offset'] as int;
      // 畫面上的字經過標點整理（【】變成「」），整段有網址就整段選起來。
      if (text.contains('yeyu-novel.example')) return [0, text.length];
      return [offset, offset + 1];
    },
  );
}

void main() {
  setUpAll(loadScreenshotFonts);
  final only = Platform.environment['SHOT_ONLY']?.split(',');
  final webDir = Directory('${screenshotDir.path}${Platform.pathSeparator}web');

  testWidgets('website shots', timeout: const Timeout(Duration(minutes: 40)), (
    tester,
  ) async {
    _setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await _seedShowcase();
      await seedCovers(coverDirectory());
      await _seedLocalBook();
    });
    _mockPhoneServices();
    for (final s in _shots) {
      if (only != null && !only.contains(s.name)) continue;
      s.tablet ? _useTablet(tester) : _usePhone(tester);
      await tester.runAsync(
        () => resetPrefs({
          // 照 App 的預設玻璃（測試環境預設用霧面）。
          PreferKey.glassStrength: GlassStrength.defaultStrength.name,
          'themeMode': s.mode,
          ..._webTypography,
          ...s.prefs,
        }),
      );
      if (s.launch) {
        await _recordLaunch(tester);
      } else {
        await pumpApp(tester);
        await s.steps?.call(tester);
        if (s.clip case final clip?) {
          await clip(tester, _Recorder(tester, s.name));
          // ignore: avoid_print
          print('CLIP ${s.name}');
        } else {
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await settle(tester, const Duration(milliseconds: 100));
          }
          final file = await saveScreenshot(tester, s.name, dir: webDir);
          // ignore: avoid_print
          print('SHOT ${file.path}');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, const Duration(milliseconds: 300));
    }
    _usePhone(tester);
    await tester.pump(const Duration(minutes: 1));
  });
}
