import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/source/content_next_page.dart';

const _chapter = 'https://www.site.example/book/149032/95393.html';
const _chapterNext = 'https://www.site.example/book/149032/95393_2.html';

final _text = '前半章的一段話，' * 40;

/// 抓這一章時的請求：正文頁是 [body]（下書網 2026-11-12 的結構）。
List<LoggedPage> _pages(
  String body, {
  bool fetchedNext = false,
  String? redirectedFrom,
}) => [
  if (redirectedFrom != null) ...[
    (line: redirectedFrom, body: null),
    (line: '  ← $redirectedFrom 301 text/html，0 位元組', body: ''),
    (line: '$_chapter（轉址）', body: null),
  ] else
    (line: _chapter, body: null),
  (line: '  ← $_chapter 200 text/html，7752 位元組：…', body: body),
  if (fetchedNext) ...[
    (line: _chapterNext, body: null),
    (line: '  ← $_chapterNext 200 text/html，7752 位元組：…', body: '…'),
  ],
];

const _halfChapter =
    '<div id="content">前半章</div>'
    '<a href="/book/149032/95392.html">上一章</a>'
    '<a href="/book/149032/95393_2.html">下一页</a>';

BookSource _source({String? next, String content = '#content@html'}) =>
    BookSource(
      bookSourceUrl: 'https://www.site.example',
      bookSourceName: '下書網',
      ruleContent: ContentRule(content: content, nextContentUrl: next),
    );

final _book = Book(origin: 'https://www.site.example', bookUrl: 'b');

String? _cut(
  List<LoggedPage> pages, {
  BookSource? source,
  String? content,
  List<String> toc = const [],
}) => chapterCutAtFirstPage(
  source ?? _source(),
  _book,
  content ?? _text,
  pages,
  toc: toc,
);

void main() {
  test('a chapter whose second page is never fetched is caught', () {
    expect(_cut(_pages(_halfChapter)), _chapterNext);
  });

  test('the next-page link written in the first page does not count as '
      'fetching it', () {
    // 審查：回應那一行的內容裡正好有下一頁的絕對網址。
    expect(
      _cut(
        _pages(
          '<div id="content">前半章</div>'
          '<a href="$_chapterNext">下一页</a>',
        ),
      ),
      _chapterNext,
    );
  });

  test('a next-page rule that fetches nothing is caught too', () {
    // 2026-11-13 下書網：nextContentUrl 的選擇器在頁面上抓不到連結。
    expect(
      _cut(
        _pages(_halfChapter),
        source: _source(next: '#content a:contains(下一页)@href'),
      ),
      _chapterNext,
    );
  });

  test('the first page is the one the site answered after a redirect', () {
    // 審查：章節網址轉址時，第一頁是轉址後回了內容的那一頁，中間那一跳不是，
    // 轉址的一跳也不算之後又送了請求。
    expect(
      _cut(
        _pages(
          _halfChapter,
          redirectedFrom: 'http://www.site.example/book/149032/95393.html',
        ),
      ),
      _chapterNext,
    );
  });

  test('a rule that follows the next page, or fetches it itself, is fine', () {
    expect(
      _cut(
        _pages(_halfChapter, fetchedNext: true),
        source: _source(next: 'text.下一页@href'),
      ),
      isNull,
    );
    expect(
      _cut(
        _pages(_halfChapter),
        source: _source(
          content: "@js:java.ajax(baseUrl.replace('.html','_2.html'))",
        ),
      ),
      isNull,
    );
  });

  test('a link to the next chapter is not a next page', () {
    expect(
      _cut(_pages('<div id="content">整章</div><a href="95394.html">下一章</a>')),
      isNull,
    );
  });

  test('a next page that the table of contents lists as a chapter is not '
      'missing', () {
    // 2026-11-13 腐文小说：整本書一頁一章，目錄的第二章就是 27752_2.html，
    // 引擎照 Legado 不把下一章當同一章的下一頁抓。目錄上任何一章都算，
    // 不只下一章。
    expect(_cut(_pages(_halfChapter), toc: [_chapter, _chapterNext]), isNull);
    expect(
      _cut(
        _pages(_halfChapter),
        toc: [_chapter, '/book/149032/95394.html', '/book/149032/95393_2.html'],
      ),
      isNull,
    );
  });

  test('a table of contents on http still lists the https page', () {
    // 審查：目錄頁沒轉到 https、正文頁轉了時，同一章的網址只差在這裡。
    expect(
      _cut(
        _pages(_halfChapter),
        toc: [_chapter, _chapterNext.replaceFirst('https:', 'http:')],
      ),
      isNull,
    );
  });

  test('only text is checked: a comic page that lists every picture is fine, '
      'whatever the source says it is', () {
    final pictures = [
      for (var i = 1; i <= 5; i++) '<img src="https://img.example/$i.jpg">',
    ].join('\n');
    expect(_cut(_pages(_halfChapter), content: pictures), isNull);
    final saysComic = _source()..bookSourceType = SourceType.image;
    expect(
      _cut(_pages(_halfChapter), source: saysComic),
      _chapterNext,
      reason: '正文是字就照字看',
    );
  });

  test('unreadable content is left to the readable check', () {
    expect(_cut(_pages(_halfChapter), content: '短'), isNull);
  });

  test('the next page of a chapter: a numbered file or a page number', () {
    final chapter = Uri.parse(_chapter);
    bool next(String url) => isNextPageOfChapter(chapter, Uri.parse(url));
    expect(next('https://www.site.example/book/149032/95393_2.html'), isTrue);
    expect(next('https://www.site.example/book/149032/95393-3.html'), isTrue);
    expect(next('https://www.site.example/book/149032/95394.html'), isFalse);
    expect(next('https://other.example/book/149032/95393_2.html'), isFalse);
    final query = Uri.parse('https://s.example/read?id=7');
    expect(
      isNextPageOfChapter(
        query,
        Uri.parse('https://s.example/read?id=7&page=2'),
      ),
      isTrue,
    );
  });
}
