import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/engine/web_book/parse_worker.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';

import '../../../test_helper.dart';

/// 不帶 JS、或 JS 只做計算的搜尋結果與目錄在背景 isolate 解析，結果要與
/// 原地解析相同；會用到主 isolate 狀態的 JS、`@put`／`@get` 或帶回呼的解析
/// 留在原地。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  setUp(() => ParseWorker.enabled = true);
  tearDown(() => ParseWorker.enabled = false);

  BookSource tocSource({String chapterName = 'a@text'}) => BookSource.fromJson({
    'bookSourceName': '背景解析',
    'bookSourceUrl': 'https://worker.test',
    'ruleToc': {
      'chapterList': 'class.list@a',
      'chapterName': chapterName,
      'chapterUrl': 'a@href',
      'nextTocUrl': 'class.next@href',
    },
  });
  final book = Book(
    bookUrl: 'https://worker.test/book/',
    origin: 'https://worker.test',
    name: '背景解析',
    tocUrl: 'https://worker.test/book/',
  );
  const tocHtml =
      '<html><body><div class="list">'
      '<a href="/book/1.html">第1章</a><a href="/book/2.html">第2章</a>'
      '</div><a class="next" href="/book/?page=2">下一頁</a></body></html>';

  final searchSource = BookSource.fromJson({
    'bookSourceName': '背景搜尋',
    'bookSourceUrl': 'https://worker.test',
    'ruleSearch': {
      'bookList': 'class.item',
      'name': 'class.name@text',
      'author': 'class.author@text',
      'bookUrl': 'a@href',
    },
  });
  const searchHtml =
      '<html><body>'
      '<div class="item"><a class="name" href="/b/1">甲書</a>'
      '<span class="author">作者甲</span></div>'
      '<div class="item"><a class="name" href="/b/2">乙書</a>'
      '<span class="author">作者乙</span></div>'
      '</body></html>';

  Future<ChapterListResult> parseToc(BookSource source) =>
      ChapterListParser.parse(
        source: source,
        book: book,
        body: tocHtml,
        baseUrl: book.tocUrl,
      );

  test('a JS-free TOC parsed with the worker on matches parsing in '
      'place', () async {
    ParseWorker.enabled = false;
    final inPlace = await parseToc(tocSource());
    ParseWorker.enabled = true;
    final offMain = await parseToc(tocSource());

    expect(
      offMain.chapters.map((c) => (c.title, c.url, c.index)),
      inPlace.chapters.map((c) => (c.title, c.url, c.index)),
    );
    expect(offMain.chapters.map((c) => c.title), ['第1章', '第2章']);
    expect(offMain.nextUrls, inPlace.nextUrls);
    expect(offMain.nextUrls, ['https://worker.test/book/?page=2']);
  });

  test('JS-free search results parse with the worker on', () async {
    final books = await BookListParser.parse(
      source: searchSource,
      body: searchHtml,
      baseUrl: 'https://worker.test/search',
      isSearch: true,
    );

    expect(books.map((b) => (b.name, b.author, b.bookUrl)), [
      ('甲書', '作者甲', 'https://worker.test/b/1'),
      ('乙書', '作者乙', 'https://worker.test/b/2'),
    ]);
  });

  test('JS that only computes parses the same with the worker on', () async {
    final source = tocSource(chapterName: 'a@text@js:result + "!"');
    ParseWorker.enabled = false;
    final inPlace = await parseToc(source);
    ParseWorker.enabled = true;
    final withWorker = await parseToc(source);

    expect(inPlace.chapters.map((c) => c.title), ['第1章!', '第2章!']);
    expect(
      withWorker.chapters.map((c) => (c.title, c.url)),
      inPlace.chapters.map((c) => (c.title, c.url)),
    );
  });

  test('rules are handed to the worker only when the worker gives the same '
      'result', () {
    final source = tocSource();
    ParseWorkerFit fitOf(String rule) => ParseWorker.fit(source, [rule]);

    expect(
      ParseWorker.fit(source, ['a@text', null, 'class.x@href##\\d']),
      ParseWorkerFit.pure,
    );
    for (final rule in [
      'a@text@js:result + "!"',
      '<js>java.md5Encode(result)</js>',
      '{{java.base64Encode(key)}}',
      '@js:java.getString("a@text").trim()',
    ]) {
      expect(fitOf(rule), ParseWorkerFit.js, reason: rule);
    }
    for (final rule in [
      '{{java.ajax(baseUrl)}}',
      'a@text@put:{n:"a@text"}',
      '@get:{n}',
      '@js:java.put("n", result)',
      '@js:java.get("n")',
      '@js:java.t2s(result)',
      '@js:cache.get("n")',
      '@js:source.getVariable()',
      '@js:book.name = result',
      '@js:chapter.putVariable("n", result)',
      '@js:fetch(baseUrl)',
    ]) {
      expect(fitOf(rule), ParseWorkerFit.none, reason: rule);
    }

    final withUrlLib = BookSource.fromJson({
      'bookSourceName': '外部函式庫',
      'bookSourceUrl': 'https://worker.test',
      'jsLib': '{"lib": "https://cdn.test/lib.js"}',
    });
    expect(ParseWorker.fit(withUrlLib, ['@js:result']), ParseWorkerFit.none);
  });

  test(
    'search results that @put values keep them with the worker on',
    () async {
      final source = BookSource.fromJson({
        'bookSourceName': '背景搜尋變數',
        'bookSourceUrl': 'https://worker.test',
        'ruleSearch': {
          'bookList': 'class.item',
          'name': 'class.name@text@put:{"tag":"class.author@text"}',
          'author': '@get:{tag}',
          'bookUrl': 'a@href',
        },
      });
      expect(
        ParseWorker.fit(source, ['@get:{tag}'], variablesInResult: true),
        ParseWorkerFit.pure,
      );
      Future<List<SearchBook>> parse() => BookListParser.parse(
        source: source,
        body: searchHtml,
        baseUrl: 'https://worker.test/search',
        isSearch: true,
      );

      ParseWorker.enabled = false;
      final inPlace = await parse();
      ParseWorker.enabled = true;
      final withWorker = await parse();

      expect(inPlace.map((b) => b.author), ['作者甲', '作者乙']);
      expect(
        withWorker.map((b) => (b.name, b.author, b.variable)),
        inPlace.map((b) => (b.name, b.author, b.variable)),
      );
    },
  );

  test('search with a filter still filters with the worker on', () async {
    final books = await BookListParser.parse(
      source: searchSource,
      body: searchHtml,
      baseUrl: 'https://worker.test/search',
      isSearch: true,
      filter: (name, author) => name == '乙書',
    );

    expect(books.map((b) => b.name), ['乙書']);
  });

  test('tasks run in the worker isolate, and a failing task returns null '
      'so the caller parses in place', () async {
    expect(
      await ParseWorker.run(() async => Isolate.current.debugName!),
      'ParseWorker',
    );
    expect(
      await ParseWorker.run<String>(() async => throw StateError('x')),
      isNull,
    );

    ParseWorker.enabled = false;
    expect(await ParseWorker.run(() async => 'x'), isNull);
  });

  test('a search URL built by JS is the same with the worker on', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '網址 JS',
      'bookSourceUrl': 'https://worker.test',
      'header': '@js:JSON.stringify({"X-Key": java.md5Encode("夜讀")})',
    });
    const rawUrl =
        '/search?q={{java.base64Encode(key)}}&p={{page + 1}}'
        ',{"method": "POST", "body": "k={{key}}"}';
    Future<AnalyzeUrl> build() => AnalyzeUrl.create(
      rawUrl,
      key: '夜讀',
      page: 2,
      baseUrl: 'https://worker.test',
      source: source,
    );

    ParseWorker.enabled = false;
    final inPlace = await build();
    ParseWorker.enabled = true;
    final withWorker = await build();

    expect(inPlace.url, startsWith('https://worker.test/search?q='));
    expect(
      (withWorker.url, withWorker.method, withWorker.body, withWorker.charset),
      (inPlace.url, inPlace.method, inPlace.body, inPlace.charset),
    );
    expect(withWorker.headerMap, inPlace.headerMap);
    expect(withWorker.headerMap['X-Key'], isNotEmpty);
  });
}
