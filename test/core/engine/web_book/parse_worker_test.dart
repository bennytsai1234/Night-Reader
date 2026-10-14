import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/engine/web_book/parse_worker.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

/// 不帶 JS 的搜尋結果與目錄在背景 isolate 解析，結果要與原地解析相同；
/// 帶 JS、`@put`／`@get` 或帶回呼的解析留在原地。
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

  test('a JS-free TOC is parsed off the main isolate with the same '
      'result', () async {
    ParseWorker.enabled = false;
    final inPlace = await parseToc(tocSource());
    ParseWorker.enabled = true;
    final before = ParseWorker.completed;
    final offMain = await parseToc(tocSource());

    expect(ParseWorker.completed, before + 1);
    expect(
      offMain.chapters.map((c) => (c.title, c.url, c.index)),
      inPlace.chapters.map((c) => (c.title, c.url, c.index)),
    );
    expect(offMain.chapters.map((c) => c.title), ['第1章', '第2章']);
    expect(offMain.nextUrls, inPlace.nextUrls);
    expect(offMain.nextUrls, ['https://worker.test/book/?page=2']);
  });

  test('JS-free search results are parsed off the main isolate', () async {
    final before = ParseWorker.completed;
    final books = await BookListParser.parse(
      source: searchSource,
      body: searchHtml,
      baseUrl: 'https://worker.test/search',
      isSearch: true,
    );

    expect(ParseWorker.completed, before + 1);
    expect(books.map((b) => (b.name, b.author, b.bookUrl)), [
      ('甲書', '作者甲', 'https://worker.test/b/1'),
      ('乙書', '作者乙', 'https://worker.test/b/2'),
    ]);
  });

  test('rules with JS or variables stay on the main isolate', () async {
    final before = ParseWorker.completed;
    final result = await parseToc(
      tocSource(chapterName: 'a@text@js:result + "!"'),
    );

    expect(ParseWorker.completed, before);
    expect(result.chapters.map((c) => c.title), ['第1章!', '第2章!']);
    expect(ParseWorker.isPureRule(['a@text', null, 'class.x@href##\\d']), true);
    for (final rule in [
      '<js>result</js>',
      '{{java.ajax(baseUrl)}}',
      'a@text@put:{n:"a@text"}',
      '@get:{n}',
    ]) {
      expect(ParseWorker.isPureRule([rule]), false, reason: rule);
    }
  });

  test('search with a filter stays on the main isolate', () async {
    final before = ParseWorker.completed;
    final books = await BookListParser.parse(
      source: searchSource,
      body: searchHtml,
      baseUrl: 'https://worker.test/search',
      isSearch: true,
      filter: (name, author) => name == '乙書',
    );

    expect(ParseWorker.completed, before);
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
}
