// 整個 App 的截圖環境：記憶體資料庫＋真的 DAO＋假資料，畫出來的就是 App
// 實際的頁面（閱讀器走真的排版引擎）。

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/keyboard_assist_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_history_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/database/dao/server_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screenshot.dart';

const kBookUrl = 'https://www.example.com/book/1024/';
const kOrigin = 'https://www.example.com';

final kParagraphs = <String>[
  '雨是從傍晚開始下的。沈知秋撐著一把舊油紙傘，沿著青石板路慢慢走回書鋪，鞋尖早已濕透。',
  '「掌櫃的，今天還收書嗎？」門口站著一個瘦高的少年，懷裡抱著一只木匣，匣面刻著三個小字：『聽雨樓』。',
  '沈知秋看了他一眼，收起傘，抖落傘面上的水珠：「收。不過得先看貨……你這匣子，是從哪裡來的？」',
  '少年沒有回答，只把木匣輕輕放在櫃臺上。燈火搖晃，匣蓋縫隙裡透出一股陳年的墨香——那是只有百年以上的松煙墨才會有的味道。',
  '她打開匣子，裡面是一疊手抄的書稿，紙頁泛黃，邊角卻整整齊齊。第一頁寫著「卷一．夜讀」，落款是民國 23 年，旁邊還用鉛筆補了一行英文：For the one who reads at night.',
  '「這字跡……」沈知秋的手指停在半空，「你知道這是誰寫的嗎？」',
  '少年搖頭：「我只知道，祖父臨走前說，這匣書要交給一個肯在夜裡讀書的人。」',
  '窗外的雨聲漸漸大了，打在屋簷上，像有人在很遠的地方翻書。沈知秋把書稿一頁一頁攤開，燈下的字句彷彿活了過來，一行接著一行，從紙面上緩緩浮起。',
  '她忽然明白，這不是一部普通的書稿。每一頁的頁腳都畫著一個小小的記號，有時是一彎新月，有時是一盞油燈，有時只是一個圓點，像是誰在提醒後來的讀者：讀到這裡，可以歇一歇了。',
  '「你今晚住哪裡？」她問。',
  '「還沒想好。」',
  '「那就留下來吧。」沈知秋把燈芯挑亮了一些，「後頭有間空房，被褥是新曬過的。明天一早，我們一起把這匣書從頭讀一遍。」',
  '少年愣了一下，終於笑了。那是他走進書鋪以來，第一次露出笑容。',
];

String chapterText(int index) =>
    [for (var round = 0; round < 3; round++) ...kParagraphs].join('\n');

final kChapterTitles = <String>[
  '第一章 雨夜來客',
  '第二章 聽雨樓',
  '第三章 松煙墨',
  '第四章 頁腳的月亮',
  '第五章 民國二十三年',
  '第六章 祖父的信',
  '第七章 夜讀之人',
  '第八章 天亮以前',
  for (var i = 9; i <= 120; i++) '第$i章 書頁之間（$i）',
];

late AppDatabase _db;

/// 註冊 App 的所有服務，資料庫換成記憶體。放在每個 testWidgets 開頭。
Future<void> setUpApp({Map<String, Object> prefs = const {}}) async {
  await getIt.reset();
  SharedPreferences.setMockInitialValues(<String, Object>{...prefs});
  _db = AppDatabase.forTesting(NativeDatabase.memory());
  getIt
    ..registerSingleton<Logger>(Logger(level: Level.off))
    ..registerSingleton<AppDatabase>(_db)
    ..registerLazySingleton<BookDao>(() => BookDao(_db))
    ..registerLazySingleton<BookSourceDao>(() => BookSourceDao(_db))
    ..registerLazySingleton<ChapterDao>(() => ChapterDao(_db))
    ..registerLazySingleton<BookGroupDao>(() => BookGroupDao(_db))
    ..registerLazySingleton<CacheDao>(() => CacheDao(_db))
    ..registerLazySingleton<CookieDao>(() => CookieDao(_db))
    ..registerLazySingleton<DownloadDao>(() => DownloadDao(_db))
    ..registerLazySingleton<ReadRecordDao>(() => ReadRecordDao(_db))
    ..registerLazySingleton<ReplaceRuleDao>(() => ReplaceRuleDao(_db))
    ..registerLazySingleton<SearchBookDao>(() => SearchBookDao(_db))
    ..registerLazySingleton<SearchHistoryDao>(() => SearchHistoryDao(_db))
    ..registerLazySingleton<SearchKeywordDao>(() => SearchKeywordDao(_db))
    ..registerLazySingleton<KeyboardAssistDao>(() => KeyboardAssistDao(_db))
    ..registerLazySingleton<ServerDao>(() => ServerDao(_db))
    ..registerLazySingleton<ReaderChapterContentDao>(
      () => ReaderChapterContentDao(_db),
    )
    ..registerSingleton<NetworkService>(NetworkService())
    ..registerSingleton<TTSService>(TTSService())
    ..registerLazySingleton<CheckSourceService>(CheckSourceService.new)
    ..registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  _mockPlatformChannels();
}

void _mockPlatformChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in [
    'dev.fluttercommunity.plus/battery',
    'dev.fluttercommunity.plus/package_info',
    'night_reader/device',
    'flutter_tts',
    'wakelock_plus',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      switch (call.method) {
        case 'getAll':
          return <String, Object>{
            'appName': '夜讀',
            'packageName': 'com.night.reader',
            'version': '0.3.5',
            'buildNumber': '700',
          };
        case 'getBatteryLevel':
          return 82;
      }
      return null;
    });
  }
  // 外部連結與分享進 App 的事件串流。
  for (final name in [
    'com.llfbandit.app_links/events',
    'receive_sharing_intent/events-media',
    'receive_sharing_intent/events-text',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => null,
    );
  }
}

/// 換掉偏好設定的內容，下一次 [pumpApp] 建出的 App 照這組設定。同一個測試
/// 裡換情境用，不必重建資料庫。
Future<void> resetPrefs(Map<String, Object> values) async {
  final prefs = getIt<SharedPreferences>();
  await prefs.clear();
  for (final MapEntry(:key, :value) in values.entries) {
    switch (value) {
      case final bool v:
        await prefs.setBool(key, v);
      case final int v:
        await prefs.setInt(key, v);
      case final double v:
        await prefs.setDouble(key, v);
      case final List<String> v:
        await prefs.setStringList(key, v);
      default:
        await prefs.setString(key, '$value');
    }
  }
}

/// 書源、書架與一本有內容的書。
Future<void> seedLibrary({bool withContent = true}) async {
  await getIt<BookSourceDao>().upsertAll([
    BookSource(bookSourceUrl: kOrigin, bookSourceName: '筆趣閣'),
    BookSource(
      bookSourceUrl: 'https://www.sample.org',
      bookSourceName: '書海閣',
      bookSourceGroup: '常用',
    ),
  ]);
  final now = DateTime(2026, 10, 15, 21).millisecondsSinceEpoch;
  final books = [
    Book(
      bookUrl: kBookUrl,
      origin: kOrigin,
      originName: '筆趣閣',
      name: '夜雨聽書',
      author: '沈知秋',
      kind: '仙俠,連載',
      intro: '一匣手抄書稿，一間雨夜書鋪，一個肯在夜裡讀書的人。',
      wordCount: '128.6萬字',
      latestChapterTitle: kChapterTitles.last,
      totalChapterNum: kChapterTitles.length,
      durChapterTitle: kChapterTitles[2],
      chapterIndex: 2,
      durChapterTime: now,
      isInBookshelf: true,
    ),
    for (final (i, (name, author)) in [
      ('長安十二時辰之外', '佚名'),
      ('山海經異聞錄', '青衫客'),
      ('我在大唐開書鋪', '落葉知秋'),
      ('星河彼岸', 'Arthur Lin'),
      ('三體之後：一部很長很長很長的書名測試', '劉某某'),
    ].indexed)
      Book(
        bookUrl: 'https://www.example.com/book/${2000 + i}/',
        origin: kOrigin,
        originName: '筆趣閣',
        name: name,
        author: author,
        latestChapterTitle: '第${300 + i}章 終章',
        totalChapterNum: 300 + i,
        chapterIndex: 40 * i,
        durChapterTitle: '第${40 * i + 1}章',
        durChapterTime: now - (i + 1) * 3600000,
        isInBookshelf: true,
      ),
  ];
  await getIt<BookDao>().upsertAll(books);
  final chapters = [
    for (final (i, title) in kChapterTitles.indexed)
      BookChapter(
        url: '${kBookUrl}c$i.html',
        title: title,
        bookUrl: kBookUrl,
        index: i,
      ),
  ];
  await getIt<ChapterDao>().insertChapters(chapters);
  if (!withContent) return;
  final store = ReaderChapterContentStore(
    chapterDao: getIt<ChapterDao>(),
    contentDao: getIt<ReaderChapterContentDao>(),
  );
  for (final chapter in chapters.take(12)) {
    await store.saveRawContent(
      book: books.first,
      chapter: chapter,
      content: chapterText(chapter.index),
      saveChapterMetadata: false,
    );
  }
}

/// 書架上再多放 [count] 本書（書名、作者與進度各不相同），量一整個畫面的
/// 書架用。在 `runAsync` 裡、[seedLibrary] 之後呼叫。
Future<void> seedMoreBooks(int count) async {
  final now = DateTime(2026, 10, 15, 21).millisecondsSinceEpoch;
  await getIt<BookDao>().upsertAll([
    for (var i = 0; i < count; i++)
      Book(
        bookUrl: 'https://www.example.com/book/${3000 + i}/',
        origin: kOrigin,
        originName: '筆趣閣',
        name: '書架上的第${i + 7}本書${'長' * (i % 5)}',
        author: '作者${String.fromCharCode(0x7532 + i)}',
        latestChapterTitle: '第${100 + i}章',
        totalChapterNum: 100 + i,
        chapterIndex: i * 3,
        durChapterTitle: '第${i * 3 + 1}章',
        durChapterTime: now - (i + 10) * 3600000,
        isInBookshelf: true,
      ),
  ]);
}

/// 放書架封面的暫存資料夾；測試結束時刪掉。
Directory coverDirectory() {
  final covers = Directory.systemTemp.createTempSync('night-reader-covers-');
  addTearDown(() {
    try {
      covers.deleteSync(recursive: true);
    } on FileSystemException {
      // 還開著（Windows）就留給系統暫存區清理。
    }
  });
  return covers;
}

/// 書架上的每一本書都換成 [covers] 裡的本機封面（手機裡已經有的封面，開
/// App 換場前要等它們畫得出來，ADR 0031）。在 `runAsync` 裡呼叫。
Future<void> seedCovers(Directory covers) async {
  final dao = getIt<BookDao>();
  final books = await dao.getInBookshelf();
  await dao.upsertAll([
    for (final (i, book) in books.indexed)
      book.copyWith(
        coverUrl: 'local://${covers.path}${Platform.pathSeparator}$i.png',
      ),
  ]);
  for (var i = 0; i < books.length; i++) {
    File('${covers.path}${Platform.pathSeparator}$i.png')
        .writeAsBytesSync(await _encodeCover(i));
  }
}

Future<Uint8List> _encodeCover(int seed) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final hue = seed * 57.0 % 360;
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 120, 168),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 168), [
        HSVColor.fromAHSV(1, hue, 0.6, 0.9).toColor(),
        HSVColor.fromAHSV(1, (hue + 40) % 360, 0.7, 0.4).toColor(),
      ]),
  );
  canvas.drawCircle(
    const Offset(60, 70),
    30,
    Paint()..color = const Color(0xFFF0E6C8),
  );
  final image = await recorder.endRecording().toImage(120, 168);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// 整個 App（同 `main.dart` 的 runApp），等開 App 的進場播完：骨架長出
/// 0.6 秒、至少停 0.8 秒、收住呼吸（最多 1.6 秒）、靜止時準備書架與拍圖、
/// 換場 0.6 秒，換場播完前畫面不接點擊（ADR 0031）。收住、拍圖都要等某一格
/// 畫完，一格一格推進（16ms）直到進場真的播完，不照固定的時間等。
Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiProvider(providers: AppProviders.providers, child: const ReaderApp()),
  );
  LaunchEntranceMotion? entrance;
  var finished = false;
  for (var i = 0; i < 1000 && !finished; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
    if (entrance != null) continue;
    final shelf = find.byType(BookshelfPage).evaluate();
    if (shelf.isEmpty) continue;
    entrance = LaunchEntrance.maybeOf(shelf.first);
    if (entrance == null) break;
    unawaited(entrance.finished.then((_) => finished = true));
  }
  // 推到上限還沒播完是進場卡住了（換場一直不來），不能當成開好了。
  if (entrance != null && !finished) {
    fail('開 App 的進場推進 1000 格（16 秒）仍沒播完');
  }
  await settle(tester, const Duration(milliseconds: 500));
}

/// App 有常駐的計時器（時鐘、流光），`pumpAndSettle` 等不完；改成推進
/// 一段固定時間。資料庫在真的 isolate 裡，讓出時間給它。
Future<void> settle(
  WidgetTester tester, [
  Duration duration = const Duration(seconds: 2),
]) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < duration; t += step) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(step);
  }
}

/// 點書架上的書開閱讀器，等正文排好、載入的紙掀開。
Future<void> openReader(WidgetTester tester, [String name = '夜雨聽書']) async {
  await tester.tap(find.text(name).first);
  await settle(tester, const Duration(milliseconds: 600));
  await waitForText(tester);
}

/// 等閱讀器的正文排好：載入的紙一直在元件樹裡，看它蓋著沒有。資料庫在真的
/// isolate 裡，花多久不一定；連續幾次都掀開才算排好（換章、重排時會再蓋上）。
Future<void> waitForText(WidgetTester tester) async {
  bool covered() => find
      .byType(LoadingVeil)
      .evaluate()
      .any((e) => (e.widget as LoadingVeil).controller.isVisible);
  for (var clear = 0, i = 0; clear < 5 && i < 300; i++) {
    clear = covered() ? 0 : clear + 1;
    await settle(tester, const Duration(milliseconds: 100));
  }
  await settle(tester, const Duration(milliseconds: 600));
}

/// 點正文中央叫出閱讀選單。
Future<void> showReaderMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(196, 420));
  await settle(tester, const Duration(milliseconds: 800));
  await waitForText(tester);
}

Future<void> shot(WidgetTester tester, String name) async {
  final file = await saveScreenshot(tester, name);
  // ignore: avoid_print
  print('SHOT ${file.path}');
}

void setUpPhone(WidgetTester tester) {
  setUpScreenshot(tester);
  tester.view.padding = const FakeViewPadding(top: 32 * 3, bottom: 24 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 32 * 3, bottom: 24 * 3);
}
