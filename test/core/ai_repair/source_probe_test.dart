import 'dart:io';

import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/ai_repair/ai_repair_prompt.dart';
import 'package:night_reader/core/ai_repair/repair_agent.dart';
import 'package:night_reader/core/ai_repair/repair_pages.dart';
import 'package:night_reader/core/ai_repair/repair_rule_tools.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/cookie_store.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() =>
      _instance ??= _MinimalServicesBinding();
}

const _chapter = '夜雨落在書鋪的瓦上，掌櫃把燈芯挑亮，翻開那一匣手抄的書稿。';

const _left = 'LEFTq7Wk';
const _right = 'RIGHTz3Pm';

void main() {
  _MinimalServicesBinding.ensureInitialized();
  late HttpServer server;
  late String site;
  late DriftIsolate databaseIsolate;
  late AppDatabase db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    await NetworkService().init(ephemeral: true);
    databaseIsolate = await DriftIsolate.spawn(NativeDatabase.memory);
    db = AppDatabase.connected(await databaseIsolate.connect());
    registerDatabase(db);
    // 規則 JS 的 `java.ajax` 停住 worker、交給網路 isolate 送；App 裡開書源
    // isolate 時設好它連哪個資料庫（[SourceIsolate.start]），這裡沒開，要
    // 自己設，不然它等 App 的資料庫等不到。
    SourceIo.configure(database: Future.value(databaseIsolate));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    site = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      // 很慢的正文頁：試抓的時限內回不來。
      if (request.uri.path == '/book/9/1.html') {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      // 轉址的章節網址：轉到一章分兩頁的那一章。
      if (request.uri.path == '/book/4/1.html') {
        request.response
          ..statusCode = HttpStatus.movedPermanently
          ..headers.set(HttpHeaders.locationHeader, '/book/3/1.html');
        await request.response.close();
        return;
      }
      // 確認圖片能不能下載時只回格式與大小（2026-11-25 清單第 3 項）。
      if (request.uri.path == '/img/cover.png') {
        request.response
          ..headers.contentType = ContentType('image', 'png')
          ..add(<int>[
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
            ...List.filled(59, 0xAB),
          ]);
        await request.response.close();
        return;
      }
      // 沒有 Content-Type，開頭是 JPEG 檔頭。
      if (request.uri.path == '/img/photo.jpg') {
        request.response.headers.removeAll(HttpHeaders.contentTypeHeader);
        request.response.add(<int>[
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          ...List.filled(996, 0xAB),
        ]);
        await request.response.close();
        return;
      }
      final body = switch (request.uri.path) {
        '/search' => '<div class="book"><a href="/book/1">夜雨聽書</a></div>',
        '/book/1' =>
          '<h1>夜雨聽書</h1><ul class="toc">'
              '<li><a href="/book/1/1.html">第一章</a></li>'
              '<li><a href="/book/1/2.html">第二章</a></li></ul>',
        '/book/1/1.html' => '<div id="content">$_chapter</div>',
        // 懶載入的網站：正文只有一張佔位圖，含標籤 95 字（漲姿勢）。
        '/book/2/1.html' =>
          '<div id="content"><img src="/static/lazy.png" '
              'data-original="/img/chapter-1-page-1.jpg"></div>',
        '/explore/1.html' =>
          '<div class="book"><a href="/book/1">夜雨聽書</a></div>',
        // 一章分兩頁（下書網）：第一頁有指向第二頁的連結。
        '/book/3/1.html' =>
          '<div id="content">$_chapter</div><a href="/book/3/1_2.html">下一页</a>',
        '/book/3/1_2.html' => '<div id="content">後半章</div>',
        // 秘密剛好跨過回應開頭截字處（前面接著 `<html><body>`）。
        '/secret' => '${'x' * 144}$_left$_right',
        _ => '',
      };
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html><body>$body</body></html>');
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await SourceIo.stop();
    await server.close(force: true);
    await db.close();
    await databaseIsolate.shutdownAll();
    await GetIt.instance.reset();
  });

  BookSource source({String content = 'id.content@text'}) => BookSource(
    bookSourceUrl: site,
    bookSourceName: '本機書源',
    searchUrl: '/search?q={{key}}',
    ruleSearch: SearchRule(
      bookList: 'class.book',
      name: 'tag.a@text',
      bookUrl: 'tag.a@href',
    ),
    ruleBookInfo: BookInfoRule(name: 'tag.h1@text'),
    ruleToc: TocRule(
      chapterList: 'class.toc@tag.a',
      chapterName: 'text',
      chapterUrl: 'href',
    ),
    ruleContent: ContentRule(content: content),
  );

  test('a search name that differs from the detail page is spelled out', () {
    // 2026-11-13 肉肉屋#3：搜尋的書名規則抓到「目录」連結。
    SourceProbeReport walked(String listed, String info, String author) =>
        SourceProbeReport(
          logs: [
            (10, '︽搜尋頁解析完成，獲取到 20 本書籍'),
            (10, '  [0] $listed - 连山会'),
            (10, '  [1] 目录 - 陌筱欷'),
            (20, '︽詳情頁解析完成: $info'),
            (20, '  作者: $author, 目錄: https://a.example/index/1'),
          ],
          requests: const [],
        );

    expect(
      searchInfoMismatch(walked('目录', '《救命！》', '连山会')),
      '搜尋結果第一本進了詳情頁，書名搜尋是「目录」、詳情頁是「《救命！》」',
    );
    expect(
      searchInfoMismatch(walked('救命！', '救命！', '别人')),
      '搜尋結果第一本進了詳情頁，作者搜尋是「连山会」、詳情頁是「别人」',
    );
    expect(searchInfoMismatch(walked('救命！', '救命！', '连山会')), isNull);
    expect(
      searchInfoMismatch(
        const SourceProbeReport(logs: [(20, '︽詳情頁解析完成: 救命！')], requests: []),
      ),
      isNull,
      reason: '從詳情開始試抓，沒有搜尋結果可比',
    );
  });

  test('a probe walks from search to content and keeps each page', () async {
    final report = await probeSource(
      source(),
      keyword: '夜雨',
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    expect(report.succeeded, isTrue, reason: report.fullText);
    expect(report.stagesReached, '搜尋、詳情、目錄、正文');
    expect(report.summary, '正文 ${_chapter.length} 字');
    expect(report.pageCount, greaterThanOrEqualTo(3));
    expect(report.fullText, contains('<a href="/book/1/1.html">第一章</a>'));
    expect(report.fullText, contains(_chapter));
  });

  test('a probe that runs out of time says how far it got', () async {
    // 2026-11-13 肉肉屋⑥：四次超過時間，紀錄都是空的。
    final report = await probeSource(
      source(),
      keyword: probeStart('content', keyword: '', url: '$site/book/9/1.html')!,
      timeout: const Duration(seconds: 1),
      database: Future.value(databaseIsolate),
    );

    expect(report.timedOut, isTrue);
    expect(report.fullText, contains('正文 URL: $site/book/9/1.html'));
    expect(report.requests, contains(startsWith('$site/book/9/1.html')));
    expect(report.fullText, contains('（試抓超過時間，停在這裡）'));
  });

  // 規則 JS 同步等網路時 worker 停住，自己的計時器跑不到；外層結束它時交回
  // 已經走到的紀錄，不是空的（2026-11-14 Codex 審查用本機伺服器重現：兩次
  // java.ajax 各 10 秒、試抓時限 1 秒）。
  test(
    'a probe stuck in rule JS waiting on the network says how far it got',
    () async {
      final slow = '$site/book/9/1.html';
      final report = await probeSource(
        source(content: '@js:java.ajax("$slow"); java.ajax("$slow")'),
        keyword: probeStart(
          'content',
          keyword: '',
          url: '$site/book/1/1.html',
        )!,
        timeout: const Duration(seconds: 1),
        database: Future.value(databaseIsolate),
        workerGrace: const Duration(milliseconds: 500),
      );

      expect(report.timedOut, isTrue);
      expect(report.fullText, contains('正文 URL: $site/book/1/1.html'));
      expect(report.requests, contains(startsWith('$site/book/1/1.html')));
      expect(
        report.requests,
        contains(startsWith('  ← $site/book/1/1.html 200')),
      );
      // 規則 JS 正在等的那個請求送出了、還沒回。
      expect(report.requests, contains(startsWith(slow)));
      expect(report.requests, isNot(contains(startsWith('  ← $slow'))));
    },
    skip: quickJsUnavailableReason(),
  );

  test(
    'a broken rule says where it stopped and still shows the page',
    () async {
      final report = await probeSource(
        source(content: 'id.missing@text'),
        keyword: '夜雨',
        timeout: const Duration(seconds: 30),
        database: Future.value(databaseIsolate),
      );

      expect(report.summary, isNot(startsWith('正文 ${_chapter.length}')));
      expect(report.fullText, contains('<div id="content">'));
    },
  );

  test('a chapter that is only a placeholder image is not counted as '
      'content, the same as the source check', () async {
    // 正文規則留下 HTML：抓到的是佔位圖的標籤，原本照長度算成抓到了。
    final report = await probeSource(
      source(content: 'id.content@html'),
      keyword: probeStart('content', keyword: '', url: '$site/book/2/1.html')!,
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    expect(report.contentUsable, isFalse, reason: report.fullText);
    expect(report.succeeded, isFalse);
    expect(report.summary, contains('書源校驗不算抓到'));
  });

  test('the second page of a chapter that nextContentUrl follows is in the '
      'request log, so the joined-page check sees it', () async {
    final paged = source(content: 'id.content@text')
      ..ruleContent!.nextContentUrl = 'text.下一页@href';
    final report = await probeSource(
      paged,
      keyword: probeStart('content', keyword: '', url: '$site/book/3/1.html')!,
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    expect(report.fullText, contains('$site/book/3/1_2.html'));
    expect(report.unjoinedNextPage, isNull);
  });

  test('a chapter cut at its first page is caught the way the source check '
      'catches it, also when the chapter address redirects', () async {
    // 審查：原本照除錯紀錄的「正文 URL」找第一頁，章節網址轉址時找不到，
    // 試抓放過、校驗才擋下。
    for (final start in ['/book/3/1.html', '/book/4/1.html']) {
      final report = await probeSource(
        source(content: 'id.content@text'),
        keyword: probeStart('content', keyword: '', url: '$site$start')!,
        timeout: const Duration(seconds: 30),
        database: Future.value(databaseIsolate),
      );

      expect(report.succeeded, isTrue, reason: report.fullText);
      expect(
        report.unjoinedNextPage,
        '$site/book/3/1_2.html',
        reason: report.fullText,
      );
    }
  });

  test('a probe can start from a discovery page written like exploreUrl, '
      'relative and with {{page}}', () async {
    final report = await probeSource(
      source(),
      keyword: probeStart(
        'explore',
        keyword: '',
        url: '/explore/{{page}}.html',
      )!,
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    expect(report.succeeded, isTrue, reason: report.fullText);
    expect(report.requests.first, contains('/explore/1.html'));
  });

  test('a probe can start from the table of contents', () async {
    final report = await probeSource(
      source(),
      keyword: probeStart('toc', keyword: '夜雨', url: '$site/book/1')!,
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    expect(report.succeeded, isTrue, reason: report.fullText);
    expect(report.stagesReached, '目錄、正文');
  });

  test('a probe from a relative address starts on that page', () async {
    // 書源除錯同 Legado：不是 http 開頭的當成搜尋關鍵字。2026-11-12 AI 給
    // /551874.html 從詳情頁試抓，結果拿它去搜尋。
    expect(
      probeStart('info', keyword: '', url: '/book/1', baseUrl: site),
      '$site/book/1',
    );
    final report = await probeSource(
      source(),
      keyword: probeStart('toc', keyword: '', url: '/book/1', baseUrl: site)!,
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );
    expect(report.stagesReached, '目錄、正文', reason: report.fullText);
  });

  test(
    'parse says the book variables are empty when the rule uses them',
    () async {
      final result = await parseRepairPage(
        source()
          ..ruleToc = TocRule(
            chapterList: 'title',
            chapterName: '{{book.name}}',
          ),
        stage: 'toc',
        body: '<html><head><title>一篇</title></head><body></body></html>',
        url: '$site/1.html',
        timeout: const Duration(seconds: 30),
        database: Future.value(databaseIsolate),
      );

      expect(result, startsWith('解析成目錄頁：0 章'));
      expect(result, contains('book.name 這類都是空的'));
    },
  );

  test('parse runs the stage parser on a page already fetched', () async {
    const toc =
        '<html><body><ul class="toc"><li><a href="/book/1/1.html">第一章</a>'
        '</li><li><a href="/book/1/2.html">第二章</a></li></ul></body></html>';
    Future<String> parse(BookSource source, String stage, String body) =>
        parseRepairPage(
          source,
          stage: stage,
          body: body,
          url: '$site/book/1',
          timeout: const Duration(seconds: 30),
          database: Future.value(databaseIsolate),
        );

    expect(
      await parse(source(), 'toc', toc),
      '解析成目錄頁：2 章\n'
      '1. 第一章 → $site/book/1/1.html\n'
      '2. 第二章 → $site/book/1/2.html',
    );
    expect(
      await parse(source(), 'content', '<div id="content">$_chapter</div>'),
      startsWith('解析成正文頁：${_chapter.length} 字'),
    );
    expect(
      await parse(
        source(),
        'search',
        '<div class="book"><a href="/b/2">夜讀</a></div>',
      ),
      contains('書名：夜讀｜網址：$site/b/2'),
    );
    expect(await parse(source(), 'nope', toc), startsWith('不認得的段'));
  });

  // 解析結果截字前先遮秘密（#529 第 47 條）。
  test('parse hides a secret before cutting the content it shows', () async {
    const left = 'LEFTq7Wk';
    const right = 'RIGHTz3Pm';
    final result = await parseRepairPage(
      source(),
      stage: 'content',
      body: '<div id="content">${'字' * 296}$left$right${'字' * 100}</div>',
      url: '$site/1.html',
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
      secrets: const {'$left$right'},
    );

    expect(result, startsWith('解析成正文頁'));
    expect(result, isNot(contains(left.substring(0, 4))));
    expect(result, isNot(contains(right)));
  });

  // 確認圖片能不能下載時，回給 AI 的只有格式與大小（2026-11-25 清單第 3 項）：
  // 位元組當文字解開是幾萬字亂碼，佔掉上下文，AI 也讀不出東西。
  test(
    'a picture only reports its format and size, and is not a page',
    () async {
      for (final (path, note) in [
        ('/img/cover.png', '圖片 PNG，67 位元組'),
        ('/img/photo.jpg', '圖片 JPEG，1,000 位元組'),
      ]) {
        final pages = RepairPages();
        final page = await fetchPageForAi(
          source(),
          '$site$path',
          keyword: '夜雨',
          timeout: const Duration(seconds: 30),
          database: Future.value(databaseIsolate),
        );
        final reply = aiRepairFetchReply(
          '$site$path',
          pages.add(page.lines, page.pages),
        );

        expect(reply, contains(note), reason: reply);
        expect(reply, isNot(contains('\uFFFD')), reason: reply);
        expect(reply.length, lessThan(400), reason: reply);
        expect(page.pages.every((logged) => logged.body == null), isTrue);
        expect(pages.length, 0, reason: '圖片不是一頁，讀頁、找字指不到它');
      }
    },
  );

  test('a probe that meets a picture says its format and size, not its '
      'bytes', () async {
    final report = await probeSource(
      source(),
      keyword: probeStart('content', keyword: '', url: '$site/img/cover.png')!,
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    final reply = aiRepairProbeReply(withPageIds(RepairPages(), report));
    expect(reply, contains('圖片 PNG，67 位元組'), reason: reply);
    expect(reply, isNot(contains('\uFFFD')), reason: reply);
    expect(report.pages.every((logged) => logged.body == null), isTrue);
  });

  // 請求紀錄的回應開頭截字前先遮秘密（#529 第 47 條）。
  group('a secret across where a response is cut is hidden', () {
    void hidden(String text) {
      expect(text, isNot(contains(_left.substring(0, 4))));
      expect(text, isNot(contains(_right)));
    }

    test('when the AI looks at a page', () async {
      final page = await fetchPageForAi(
        source(),
        '$site/secret',
        keyword: '夜雨',
        timeout: const Duration(seconds: 30),
        pageLength: 160,
        secrets: const {'$_left$_right'},
        database: Future.value(databaseIsolate),
      );
      hidden(page.lines.join('\n'));
      expect(
        page.pages.map((p) => p.body).join(),
        contains('$_left$_right'),
        reason: '整頁原文照舊，規則解析要用',
      );
    });

    // `java.ajax` 停住 worker、在網路 isolate 送出與記錄。
    test('when rule JS fetches through the network isolate', () async {
      final result = await runRepairJs(
        source(),
        code: 'java.ajax("$site/secret")',
        pages: const {},
        timeout: const Duration(seconds: 30),
        database: Future.value(databaseIsolate),
        secrets: const {'$_left$_right'},
      );
      expect(result, contains('  ← $site/secret 200'), reason: result);
      hidden(result.substring(result.indexOf('# 這段程式送出的請求')));
    }, skip: quickJsUnavailableReason());
  });

  // 規則 JS 的寫入不等；worker 交回結果就被收掉。交回之前要寫完，主
  // isolate 才拿得到（之後重讀秘密才遮得到，#529 第 52 條）。
  test('what rule JS writes is all there when the JS tool returns', () async {
    final result = await runRepairJs(
      source(),
      code:
          'source.putLoginHeader(JSON.stringify('
          '{"Cookie": "sid=fresh-cookie-123456"})); "ok"',
      pages: const {},
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    expect(result, '傳回：ok');
    expect(
      CookieStore().getMemoryCookie(site),
      contains('fresh-cookie-123456'),
    );
  }, skip: quickJsUnavailableReason());

  test('js runs in the rule JS world and can read fetched pages', () async {
    final result = await runRepairJs(
      source(),
      code: 'page(2).length + ":" + source.bookSourceName',
      pages: {2: '夜讀'},
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    expect(result, '傳回：2:本機書源');
  }, skip: quickJsUnavailableReason());

  test('a JS tool run out of time still lists the requests it sent', () async {
    final result = await runRepairJs(
      source(),
      code:
          'java.ajax("$site/book/1/1.html"); java.ajax("$site/book/9/1.html")',
      pages: const {},
      timeout: const Duration(seconds: 1),
      database: Future.value(databaseIsolate),
    );

    expect(result, startsWith('超過時間，沒做完'), reason: result);
    expect(result, contains('# 這段程式送出的請求'), reason: result);
    expect(result, contains('  ← $site/book/1/1.html 200'), reason: result);
    expect(result, contains('$site/book/9/1.html'), reason: result);
    expect(result, isNot(contains('  ← $site/book/9/1.html')), reason: result);
  }, skip: quickJsUnavailableReason());

  test('JS tool includes synchronous java.ajax request and response', () async {
    final result = await runRepairJs(
      source(),
      code: 'java.ajax("$site/book/1/1.html")',
      pages: const {},
      timeout: const Duration(seconds: 30),
      database: Future.value(databaseIsolate),
    );

    expect(result, contains('# 這段程式送出的請求'), reason: result);
    expect(result, contains('$site/book/1/1.html'), reason: result);
    expect(result, contains('  ← $site/book/1/1.html 200'), reason: result);
  }, skip: quickJsUnavailableReason());
}
