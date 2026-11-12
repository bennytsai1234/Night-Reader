import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book_source.dart';

const _chapter = 'https://www.site.example/book/149032/95393.html';

/// 試抓到正文的報告：正文頁是 [body]（下書網 2026-11-12 的結構）。
SourceProbeReport _probe(String body) => SourceProbeReport(
  logs: const [
    (40, '︾開始解析正文頁: 第一章 车祸'),
    (40, '  正文 URL: $_chapter'),
    (1000, '︽解析完成'),
  ],
  requests: const ['  ← $_chapter 200：…'],
  pages: [
    (line: _chapter, body: null),
    (line: '  ← $_chapter 200 text/html，7752 位元組：…', body: body),
  ],
  contentUsable: true,
);

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

void main() {
  test('a chapter whose second page is never fetched is caught', () {
    expect(
      unjoinedContentPage(_probe(_halfChapter), _source()),
      'https://www.site.example/book/149032/95393_2.html',
    );
  });

  test('a rule that follows the next page, or fetches it itself, is fine', () {
    expect(
      unjoinedContentPage(_probe(_halfChapter), _source(next: 'text.下一页@href')),
      isNull,
    );
    expect(
      unjoinedContentPage(
        _probe(_halfChapter),
        _source(content: "@js:java.ajax(baseUrl.replace('.html','_2.html'))"),
      ),
      isNull,
    );
  });

  test('a link to the next chapter is not a next page', () {
    expect(
      unjoinedContentPage(
        _probe('<div id="content">整章</div><a href="95394.html">下一章</a>'),
        _source(),
      ),
      isNull,
    );
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
