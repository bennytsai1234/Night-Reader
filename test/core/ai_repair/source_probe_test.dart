import 'dart:io';

import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/ai_repair/repair_rule_tools.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() =>
      _instance ??= _MinimalServicesBinding();
}

const _chapter = '夜雨落在書鋪的瓦上，掌櫃把燈芯挑亮，翻開那一匣手抄的書稿。';

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
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    site = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
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
        '/explore' => '<div class="book"><a href="/book/1">夜雨聽書</a></div>',
        '/limited' =>
          '<script>alert("搜索间隔: 30 秒");window.history.go(-1);</script>',
        // 一章分兩頁（下書網）：第一頁有指向第二頁的連結。
        '/book/3/1.html' =>
          '<div id="content">$_chapter</div><a href="/book/3/1_2.html">下一页</a>',
        '/book/3/1_2.html' => '<div id="content">後半章</div>',
        _ => '',
      };
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html><body>$body</body></html>');
      await request.response.close();
    });
  });

  tearDownAll(() async {
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
    expect(unjoinedContentPage(report, paged), isNull);
    expect(
      unjoinedContentPage(report, source(content: 'id.content@text')),
      isNull,
      reason: '抓過了就算接上',
    );
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
}
