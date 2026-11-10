import 'dart:io';

import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
