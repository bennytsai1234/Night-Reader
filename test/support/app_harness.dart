// 整個 App 的截圖環境：記憶體資料庫＋真的 DAO＋假資料，畫出來的就是 App
// 實際的頁面（閱讀器走真的排版引擎）。

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_group_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/cache_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/cookie_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/keyboard_assist_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
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
import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/core/chinese/chinese_display.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/storage/reader_chapter_content_store.dart';
import 'package:night_reader/core/playback/tts_service.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/reader/chapter/reader_content_transformer.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/features/reader/text_view/overlay/loading_veil.dart';
import 'package:night_reader/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/shared/widgets/skeleton_text.dart';

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

/// 上一個測試開的資料庫，下一次 [setUpApp] 開新的之前關掉；不關的話 drift
/// 每個測試都警告同一個資料庫類別開了好幾次，記憶體裡的資料庫也一直留著。
AppDatabase? _openDb;

/// 這個測試的資料庫開在另一個 isolate（[setUpApp] 的 `databaseInIsolate`）。
var _databaseInIsolate = false;

/// 註冊 App 的所有服務，資料庫換成記憶體。放在每個 testWidgets 開頭，包在
/// `tester.runAsync` 裡。
///
/// 量幀預算與錄動畫的測試給 [databaseInIsolate]：資料庫和 App 一樣開在另一個
/// isolate（drift 的 `DriftIsolate`），SQL 不佔主執行緒，量到的只有送查詢、
/// 收結果；回覆要等真實時間，量測本來就每幀讓出真實時間（`recordFrames` 的
/// `realAsync`）。其他測試的資料庫在主執行緒、查詢當下就做完，不必等真實
/// 時間，結果不隨電腦快慢變。
Future<void> setUpApp({
  Map<String, Object> prefs = const {},
  bool databaseInIsolate = false,
}) async {
  await getIt.reset();
  // 整個程式共用、存著 future 的東西，上一個測試留下的會在上一個測試的
  // zone 裡通知等的人，那個假時鐘已經沒人推動，這個測試開書就一直等不到
  // 正文：正文轉換的 worker，與 rootBundle 快取的字典字串。
  ReaderV2ContentTransformWorker.instance.stop();
  rootBundle.clear();
  SharedPreferences.setMockInitialValues(_harnessPrefs(prefs));
  // 同步服務是整個程式共用的，記著上一個測試的偏好設定與執行狀態。
  SyncService.instance = SyncService();
  await _openDb?.close();
  _databaseInIsolate = databaseInIsolate;
  _db = _openDb = databaseInIsolate
      // 只有這一個連線：關掉時 drift isolate 跟著結束，不留到下一個測試。
      ? AppDatabase.connected(
          await (await DriftIsolate.spawn(NativeDatabase.memory))
              .connect(singleClientMode: true),
        )
      : AppDatabase.forTesting(NativeDatabase.memory());
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
    ..registerLazySingleton<BookmarkDao>(() => BookmarkDao(_db))
    ..registerLazySingleton<HighlightDao>(() => HighlightDao(_db))
    ..registerLazySingleton<ReplaceRuleDao>(() => ReplaceRuleDao(_db))
    ..registerLazySingleton<SearchBookDao>(() => SearchBookDao(_db))
    ..registerLazySingleton<SearchHistoryDao>(() => SearchHistoryDao(_db))
    ..registerLazySingleton<SearchKeywordDao>(() => SearchKeywordDao(_db))
    ..registerLazySingleton<AiFindDao>(() => AiFindDao(_db))
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
  _startChineseDisplay(getIt<SharedPreferences>());
}

/// 測試環境的偏好設定：玻璃用霧面（預設的實色不模糊，玻璃的進出場檢查與
/// 幀預算要量有模糊的那種），其餘照 [values]，沒給的照 App 的預設。
Map<String, Object> _harnessPrefs(Map<String, Object> values) => {
  PreferKey.glassStrength: GlassStrength.frosted.name,
  ...values,
};

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
  // 閱讀器頁首的電量：和手機上一樣，一訂閱就送出目前的電量。
  messenger.setMockStreamHandler(
    const EventChannel('night_reader/battery'),
    MockStreamHandler.inline(
      onListen: (arguments, events) =>
          events.success({'percent': 82, 'charging': false}),
    ),
  );
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
  for (final MapEntry(:key, :value) in _harnessPrefs(values).entries) {
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
  _startChineseDisplay(prefs);
}

/// App 開機時從偏好讀進記憶體的繁簡轉換模式（App 是 ChineseDisplay.start）。
/// 模式是整個程式共用的，不照偏好重設就沿用上一個測試留下的。開著轉換時
/// 書架等字典載好才換成內容，字典要和 App 一樣先載好，不然一直停在骨架。
void _startChineseDisplay(SharedPreferences prefs) {
  final mode =
      prefs.getInt(PreferKey.readerChineseConvert) ??
      ChineseDisplay.defaultMode;
  if (mode != 0 && !ChineseUtils.isInitialized) {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  }
  ChineseDisplay.mode.value = mode;
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
///
/// 進場播完後 App 開始背景工作，其中書架補下載、接著檢查書架更新（書架標題
/// 播流光）最久。資料庫在另一個 isolate 時（量幀的測試）它們要等真實時間，
/// 等這兩件做完、流光掃完這一輪才交回，接下來的量測不和它們疊在一起；要量
/// 開 App 後馬上操作的（例如同步還在跑時點書）給 [waitForBackgroundWork]
/// false。資料庫在主執行緒時只再推 0.5 秒：同一個檔的第二項測試起，補下載
/// 等的是上一項留下、綁在上一項假時鐘上的下載服務，檢查不會開始。
Future<void> pumpApp(
  WidgetTester tester, {
  bool waitForBackgroundWork = true,
}) async {
  await startApp(tester);
  LaunchEntranceMotion? entrance;
  ValueNotifier<bool>? checking;
  var finished = false;
  var checked = false;
  void onChecking() {
    if (!checking!.value) checked = true;
  }

  for (var i = 0; i < 1000 && !finished; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
    if (entrance != null) continue;
    final shelf = find.byType(BookshelfPage).evaluate();
    if (shelf.isEmpty) continue;
    entrance = LaunchEntrance.maybeOf(shelf.first);
    if (entrance == null) break;
    unawaited(entrance.finished.then((_) => finished = true));
    // 檢查從進場播完後才開始，這之前掛上就不會漏掉它結束的那一下。
    checking = Provider.of<BookshelfProvider>(
      shelf.first,
      listen: false,
    ).checkingShelf..addListener(onChecking);
  }
  // 推到上限還沒播完是進場卡住了（換場一直不來），不能當成開好了。
  if (entrance != null && !finished) {
    fail('開 App 的進場推進 1000 格（16 秒）仍沒播完');
  }
  if (!_databaseInIsolate || !waitForBackgroundWork) {
    checking?.removeListener(onChecking);
    await settle(tester, const Duration(milliseconds: 500));
    return;
  }
  if (checking != null && AppConfig.autoRefresh) {
    for (var i = 0; i < 600 && !checked; i++) {
      await settle(tester, const Duration(milliseconds: 50));
    }
    checking.removeListener(onChecking);
    if (!checked) fail('開 App 後的書架檢查更新推進 30 秒仍沒做完');
  }
  await waitForDownloads(tester);
  await settle(tester, AppMotion.sheen);
}

/// 掛上整個 App（同 `main.dart` 的 runApp）就交回，不等進場；要從開 App
/// 的第一幀看起的（例如細節檢查開 App 的骨架換場）用它，其他用 [pumpApp]。
Future<void> startApp(WidgetTester tester) async {
  // 開 App 的進場播完會量標點的筆畫位置；測試字型量出來的和手機無關，
  // 骨架照字的格子畫，每項測試也不留給下一項。
  PunctuationInk.resetForTest(measure: false);
  addTearDown(PunctuationInk.resetForTest);
  await tester.pumpWidget(
    MultiProvider(providers: AppProviders.providers, child: const ReaderApp()),
  );
}

/// App 有常駐的計時器（時鐘、流光），`pumpAndSettle` 等不完；改成推進
/// 一段固定時間。每一步讓出真實時間給真的 isolate（內容轉換、書源，量幀
/// 時還有資料庫）。
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

/// 資料庫在另一個 isolate 時，等下載排程停下。下載服務是整個程式共用的，
/// 開 App 後排的書架自動下載（測試沒有網路，很快失敗）跑著時，排程每秒看
/// 一次還有沒有任務，留著那個計時器測試就結束不了；任務要等真實時間才收得
/// 到資料庫的回覆，只推假時間等不完。資料庫在主執行緒時任務在假時間裡就
/// 做完，不用等。[pumpApp] 開好 App 時與拆掉 App 後（`tearDownApp`）呼叫。
Future<void> waitForDownloads(WidgetTester tester) async {
  if (!_databaseInIsolate) return;
  final downloads = DownloadService();
  for (var i = 0; i < 300 && downloads.isScheduling; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(seconds: 1));
  }
  if (downloads.isScheduling) fail('下載排程推進 300 秒仍沒停下');
}

/// 點書架上的書開閱讀器，等正文排好、載入的紙掀開。
Future<void> openReader(WidgetTester tester, [String name = '夜雨聽書']) async {
  await tester.tap(find.text(name).first);
  await settle(tester, const Duration(milliseconds: 600));
  await waitForText(tester);
}

/// 等閱讀器的正文排好：載入的紙一直在元件樹裡，看它蓋著沒有。正文轉換在
/// 真的 isolate 裡，花多久不一定；連續幾次都掀開才算排好（換章、重排時會再
/// 蓋上）。
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
  final view = tester.view;
  await tester.tapAt(
    (view.physicalSize / view.devicePixelRatio).center(Offset.zero),
  );
  await settle(tester, const Duration(milliseconds: 800));
  await waitForText(tester);
}

Future<void> shot(WidgetTester tester, String name) async {
  final file = await saveScreenshot(tester, name);
  // ignore: avoid_print
  print('SHOT ${file.path}');
}

/// 預設是手機；[size] 給平板這類其他尺寸（邏輯像素，2 倍）。
void setUpPhone(WidgetTester tester, {Size? size}) {
  final ratio = size == null ? 3.0 : 2.0;
  if (size == null) {
    setUpScreenshot(tester);
  } else {
    setUpScreenshot(tester, size: size, devicePixelRatio: ratio);
  }
  final padding = FakeViewPadding(top: 32 * ratio, bottom: 24 * ratio);
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
}
