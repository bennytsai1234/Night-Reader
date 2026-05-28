import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/engine/web_book/book_info_parser.dart';
import 'package:reader/core/engine/web_book/book_list_parser.dart';
import 'package:reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:reader/core/engine/web_book/content_parser.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/chapter.dart';
import '../../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  group('User Source Compatibility', () {
    test(
      'Legado-style relative URL source supports search to read flow',
      () async {
        final source = BookSource.fromJson({
          'bookSourceName': '武俠測試網',
          'bookSourceUrl': 'https://novels-a.test',
          'searchUrl': '/search/?q={{key}}&page={{page}}',
          'ruleSearch': {
            'bookList': 'class.novel-item',
            'name': 'class.info@tag.a@text',
            'bookUrl': 'class.info@tag.a@href',
            'author': 'class.meta@text',
            'coverUrl': 'tag.a@img@data-src',
            'intro': 'class.desc@text',
          },
          'ruleBookInfo': {
            'name': 'tag.h1@text',
            'author': 'tag.p.0@text',
            'coverUrl': 'class.cover@tag.img@src',
            'intro': 'class.desc@text',
            'kind': 'tag.p.2@text',
            'lastChapter': 'class.novel-list@a.-1@text',
          },
          'ruleToc': {
            'chapterList': 'class.novel-list@a',
            'chapterName': 'a@text',
            'chapterUrl': 'a@href',
          },
          'ruleContent': {'content': 'class.article@tag.p@html'},
        });

        const searchHtml = '''
        <html><body>
          <div class="novel-item">
            <a href="/novel/15786/"><img data-src="/data/cover/book.webp" /></a>
            <div class="info"><a href="/novel/15786/">劍鋒問蒼天</a></div>
            <div class="meta">武陵客</div>
            <div class="desc">那片山嶽，籠罩在薄霧之中。</div>
          </div>
        </body></html>
        ''';

        final searchBooks = await BookListParser.parse(
          source: source,
          body: searchHtml,
          baseUrl: 'https://novels-a.test/search/?q=%E5%8A%8D%E9%8B%92&page=1',
          isSearch: true,
        );

        expect(searchBooks, hasLength(1));
        final selected = searchBooks.first;
        expect(selected.name, '劍鋒問蒼天');
        expect(selected.author, '武陵客');
        expect(selected.bookUrl, 'https://novels-a.test/novel/15786/');
        expect(selected.coverUrl, 'https://novels-a.test/data/cover/book.webp');

        const bookHtml = '''
        <html><body>
          <div class="cover"><img src="/data/cover/book.webp" /></div>
          <h1>劍鋒問蒼天</h1>
          <p>作者：武陵客</p>
          <p>状态：已完结</p>
          <p>分类：武俠</p>
          <div class="desc">那片山嶽，籠罩在薄霧之中。</div>
          <div class="novel-list">
            <a href="/novel/15786/1461060.html">第1章 踏入江湖</a>
            <a href="/novel/15786/1461058.html">第2章 初遇仇人</a>
          </div>
        </body></html>
        ''';

        final hydratedBook = await BookInfoParser.parse(
          source: source,
          book: selected.toBook(),
          body: bookHtml,
          baseUrl: selected.bookUrl,
        );

        expect(hydratedBook.name, '劍鋒問蒼天');
        expect(hydratedBook.author, '作者：武陵客');
        expect(
          hydratedBook.coverUrl,
          'https://novels-a.test/data/cover/book.webp',
        );
        expect(hydratedBook.tocUrl, 'https://novels-a.test/novel/15786/');
        expect(hydratedBook.latestChapterTitle, '第2章 初遇仇人');

        final toc = await ChapterListParser.parse(
          source: source,
          book: hydratedBook,
          body: bookHtml,
          baseUrl: hydratedBook.tocUrl,
        );

        expect(toc.chapters, hasLength(2));
        expect(toc.chapters[0].title, '第1章 踏入江湖');
        expect(
          toc.chapters[0].url,
          'https://novels-a.test/novel/15786/1461060.html',
        );
        expect(toc.chapters[1].title, '第2章 初遇仇人');
        expect(
          toc.chapters[1].url,
          'https://novels-a.test/novel/15786/1461058.html',
        );

        const chapter1Html = '''
        <html><body>
          <section class="article">
            <p>那片山嶽，籠罩在薄霧之中。</p>
            <p>一切都從那天開始了。</p>
          </section>
        </body></html>
        ''';

        const chapter2Html = '''
        <html><body>
          <section class="article">
            <p>他握緊劍柄，向前踏出一步。</p>
            <p>遠方的城，依稀可見燈火。</p>
          </section>
        </body></html>
        ''';

        final content1 = await ContentParser.parse(
          source: source,
          book: hydratedBook,
          chapter: toc.chapters[0],
          body: chapter1Html,
          baseUrl: toc.chapters[0].url,
        );
        final content2 = await ContentParser.parse(
          source: source,
          book: hydratedBook,
          chapter: toc.chapters[1],
          body: chapter2Html,
          baseUrl: toc.chapters[1].url,
        );

        expect(content1.content, contains('那片山嶽'));
        expect(content2.content, contains('握緊劍柄'));
        expect(content1.content, isNot(equals(content2.content)));
      },
    );

    test('Legado-style :root search selectors parse results', () async {
      final source = BookSource.fromJson({
        'bookSourceName': '星海書屋',
        'bookSourceUrl': 'https://novels-b.test/',
        'searchUrl': '/search.html?q={{key}}&p={{page}}',
        'ruleSearch': {
          'bookList': '.list-group-item',
          'name': ':root@[0]@[0]@text##^\\d+\\.\\s*',
          'author': ':root@[1]@[0]@text',
          'bookUrl': ':root@[0]@[0]@href',
          'intro': '.content-txt@text',
        },
      });

      const searchHtml = '''
      <div class="list-group">
        <div class="list-group-item">
          <h5>
            <a href="/novel/40321.html" target="_blank">1. 星際迷途</a>
            <small class="text-muted ms-2">[已完结]</small>
          </h5>
          <p class="mb-1 text-muted">
            作者：<a href="/search?q=%E5%AF%92%E5%B1%B1%E6%97%85%E8%80%85&f=author" target="_blank">寒山旅者</a>
            字数：1.01万
          </p>
          <p class="content-txt">星際旅行者在迷途中尋找回家的路。</p>
        </div>
      </div>
      ''';

      final results = await BookListParser.parse(
        source: source,
        body: searchHtml,
        baseUrl: 'https://novels-b.test/search.html?q=%E6%98%9F%E9%9A%9B&p=1',
        isSearch: true,
      );

      expect(results, hasLength(1));
      expect(results.first.name, '星際迷途');
      expect(results.first.author, '寒山旅者');
      expect(results.first.bookUrl, 'https://novels-b.test/novel/40321.html');
      expect(results.first.intro, '星際旅行者在迷途中尋找回家的路。');
    });

    test(
      'Legado-style regex extraction reads element outerHtml for bookUrl',
      () async {
        final source = BookSource.fromJson({
          'bookSourceName': '隨意閱讀',
          'bookSourceUrl': 'https://novels-c.test#♤test',
          'searchUrl': 'https://novels-c.test/s/1.html?keyword={{key}}',
          'ruleSearch': {
            'bookList': '.v-list-item',
            'name': '.v-title@text',
            'author': '.v-author@text',
            'bookUrl': "##=\\\"newWebView\\('([^']+)'##\$1###",
          },
        });

        const searchHtml = '''
      <div class="v-list-item flex" onclick="newWebView('/b/27094.html', '', '')">
        <div class="v-title">神道帝尊</div>
        <div class="v-author">蜗牛狂奔</div>
      </div>
      ''';

        final results = await BookListParser.parse(
          source: source,
          body: searchHtml,
          baseUrl:
              'https://novels-c.test/s/1.html?keyword=%E7%A5%9E%E9%81%93%E5%B8%9D%E5%B0%8A',
          isSearch: true,
        );

        expect(results, hasLength(1));
        expect(results.first.name, '神道帝尊');
        expect(results.first.author, '蜗牛狂奔');
        expect(results.first.bookUrl, 'https://novels-c.test/b/27094.html');
      },
    );

    test('Legado-style XPath search rules parse HTML results', () async {
      final source = BookSource.fromJson({
        'bookSourceName': '測試書庫',
        'bookSourceUrl': 'https://novels-d.test/',
        'ruleSearch': {
          'bookList':
              '//div[@class="one-row"]/div[@class="col-md-3 col-sm-6 col-xs-6 home-truyendecu"]',
          'bookUrl': '//div[@class="each_truyen"]/a/@href',
          'coverUrl': '//div[@class="each_truyen"]/a/img/@src',
          'name': '//h3[@itemprop="name"]/text()',
        },
      });

      const searchHtml = '''
      <!DOCTYPE html>
      <html lang="en-US">
        <body>
          <div class="container" id="truyen-slide">
            <div class="main-home">
              <div class="col-xs-12 col-sm-12 col-md-9 col-truyen-main">
                <div class="row">
                  <div class="list list-thumbnail col-xs-12">
                    <div class="row">
                      <div class="one-row">
                        <div class="col-md-3 col-sm-6 col-xs-6 home-truyendecu" itemscope="" itemtype="http://schema.org/Book">
                          <div class="each_truyen">
                            <a href="/novel62406/" title="双燕归林">
                              <img src="https://img.novels-d.test/files/titlepic/bookimgalc50679.webp" alt="双燕归林" itemprop="image" />
                            </a>
                          </div>
                          <div class="caption">
                            <a href="/novel62406/" title="T双燕归林" itemprop="url">
                              <h3 itemprop="name">双燕归林</h3>
                            </a>
                          </div>
                        </div>
                        <div class="col-md-3 col-sm-6 col-xs-6 home-truyendecu" itemscope="" itemtype="http://schema.org/Book">
                          <div class="each_truyen">
                            <a href="/novel2709/" title="黑骑双燕">
                              <img src="https://img.novels-d.test/files/novel/bookimg4003s.jpg" alt="黑骑双燕" itemprop="image" />
                            </a>
                          </div>
                          <div class="caption">
                            <a href="/novel2709/" title="T黑骑双燕" itemprop="url">
                              <h3 itemprop="name">黑骑双燕</h3>
                            </a>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </body>
      </html>
      ''';

      final results = await BookListParser.parse(
        source: source,
        body: searchHtml,
        baseUrl:
            'https://novels-d.test/e/search/result/?searchid=187204&page=1',
        isSearch: true,
      );

      expect(results, hasLength(2));
      expect(results.first.name, '双燕归林');
      expect(results.first.bookUrl, 'https://novels-d.test/novel62406/');
      expect(
        results.first.coverUrl,
        'https://img.novels-d.test/files/titlepic/bookimgalc50679.webp',
      );
      expect(results[1].name, '黑骑双燕');
      expect(results[1].bookUrl, 'https://novels-d.test/novel2709/');
    });

    test('Legado-style tocUrl and toc list parse from detail pages', () async {
      final source = BookSource.fromJson({
        'bookSourceName': '星海書屋',
        'bookSourceUrl': 'https://novels-b.test/',
        'ruleBookInfo': {'tocUrl': '.book_newchap > .tabtitle@.0@href'},
        'ruleToc': {
          'chapterList': '.mulu_list a',
          'chapterName': ':root@text',
          'chapterUrl': ':root@href',
          'isVolume': 'false',
          'isVip': 'false',
          'isPay': 'false',
        },
      });

      const detailHtml = '''
      <div class="book_newchap">
        <div class="tit tabtitle">
          最新章节：全1章
          <a href="/other/chapters/id/40321.html">查看所有章节</a>
        </div>
      </div>
      ''';

      final hydratedBook = await BookInfoParser.parse(
        source: source,
        book: Book(
          bookUrl: 'https://novels-b.test/novel/40321.html',
          origin: 'https://novels-b.test/',
          name: '星際迷途',
        ),
        body: detailHtml,
        baseUrl: 'https://novels-b.test/novel/40321.html',
      );

      expect(
        hydratedBook.tocUrl,
        'https://novels-b.test/other/chapters/id/40321.html',
      );

      const tocHtml = '''
      <ul class="mulu_list">
        <li><a href="/book/41828/85a73a6d71bd9.html" target="_blank">全1章</a></li>
      </ul>
      ''';

      final toc = await ChapterListParser.parse(
        source: source,
        book: hydratedBook,
        body: tocHtml,
        baseUrl: hydratedBook.tocUrl,
      );

      expect(toc.chapters, hasLength(1));
      expect(toc.chapters.first.title, '全1章');
      expect(
        toc.chapters.first.url,
        'https://novels-b.test/book/41828/85a73a6d71bd9.html',
      );
      expect(toc.chapters.first.isVolume, isFalse);
    });

    test('Legado-style bare JSON item fields parse search results', () async {
      final source = BookSource.fromJson({
        'bookSourceName': '測試閱讀',
        'bookSourceUrl': 'https://novels-api.test',
        'ruleSearch': {
          'bookList': r'$.body.list',
          'name': 'v_book',
          'author': 'penname',
          'bookUrl':
              r'https://novels-api.test/v1/book/get_book_infos?from=search&subsite=m&book={{$.book}}',
          'lastChapter': 'v_u_chapter',
          'wordCount': 'public_size',
        },
      });

      const searchJson = '''
      {
        "body": {
          "list": [
            {
              "book": "66226",
              "v_book": "天龙殿",
              "penname": "疯狂小牛",
              "v_u_chapter": "第1651章 龙浩恪守之道（终）",
              "public_size": "3570395"
            }
          ]
        }
      }
      ''';

      final results = await BookListParser.parse(
        source: source,
        body: searchJson,
        baseUrl:
            'https://novels-api.test/v1/book/search?keyword=%E9%BE%99%E7%8E%8B%E6%AE%BF',
        isSearch: true,
      );

      expect(results, hasLength(1));
      expect(results.first.name, '天龙殿');
      expect(results.first.author, '疯狂小牛');
      expect(
        results.first.bookUrl,
        'https://novels-api.test/v1/book/get_book_infos?from=search&subsite=m&book=66226',
      );
      expect(results.first.latestChapterTitle, '第1651章 龙浩恪守之道（终）');
      expect(results.first.wordCount, isNotEmpty);
    });

    test(
      'Legado-style bare JSON list rules parse from raw JSON strings',
      () async {
        final source = BookSource.fromJson({
          'bookSourceName': '測試小說',
          'bookSourceUrl': 'https://novels-e.test',
          'ruleSearch': {
            'bookList': 'data.books',
            'name': 'original_title',
            'author': 'original_author',
            'bookUrl': r'https://api.example.com/book/{{$.id}}',
          },
        });

        const searchJson = '''
      {
        "data": {
          "books": [
            {
              "id": "1885648",
              "original_title": "我的武俠夢",
              "original_author": "作者A"
            }
          ]
        }
      }
      ''';

        final results = await BookListParser.parse(
          source: source,
          body: searchJson,
          baseUrl: 'https://novels-e.test/api/v5/search/words',
          isSearch: true,
        );

        expect(results, hasLength(1));
        expect(results.first.name, '我的武俠夢');
        expect(results.first.author, '作者A');
        expect(results.first.bookUrl, 'https://api.example.com/book/1885648');
      },
    );

    test(
      'Search parsing keeps valid items when optional metadata rules are unusable',
      () async {
        final source = BookSource.fromJson({
          'bookSourceName': 'Optional metadata failure source',
          'bookSourceUrl': 'https://example.com',
          'ruleSearch': {
            'bookList': '.item',
            'name': '.title@text',
            'bookUrl': '.title@href',
            'kind': '@js:throw new Error("boom")',
            'intro': '@js:throw new Error("boom")',
          },
        });

        const searchHtml = '''
      <div class="item">
        <a class="title" href="/book/42">可保留的書</a>
      </div>
      ''';

        final results = await BookListParser.parse(
          source: source,
          body: searchHtml,
          baseUrl: 'https://example.com/search?q=test',
          isSearch: true,
        );

        expect(results, hasLength(1));
        expect(results.first.name, '可保留的書');
        expect(results.first.bookUrl, 'https://example.com/book/42');
      },
    );

    test('Legado-style content keeps multi-section chapter text', () async {
      final source = BookSource.fromJson({
        'bookSourceName': '隨意閱讀',
        'bookSourceUrl': 'https://novels-c.test#♤test',
        'ruleContent': {
          'content': 'class.con@html',
          'replaceRegex': '##\\s*.*?本章.*?完.*\\s*',
        },
      });

      const chapterHtml = '''
      <div class="section">
        <div class="con">
          <p>第一段内容。</p>
          <p>（本章未完，请翻页）</p>
        </div>
      </div>
      <div class="section none">
        <div class="con">
          <p>第二段内容。</p>
          <p>（本章未完，请翻页）</p>
        </div>
      </div>
      <div class="section none">
        <div class="con">
          <p>第三段内容。</p>
          <p>（本章完）</p>
        </div>
      </div>
      ''';

      final parsed = await ContentParser.parse(
        source: source,
        book: Book(
          bookUrl: 'https://novels-c.test/b/28654.html',
          origin: 'https://novels-c.test#♤test',
          name: '塞外孤星',
        ),
        chapter: BookChapter(
          title: '第1章',
          url: 'https://novels-c.test/r/28654/33046.html',
          bookUrl: 'https://novels-c.test/b/28654.html',
        ),
        body: chapterHtml,
        baseUrl: 'https://novels-c.test/r/28654/33046.html',
      );

      final finalized = await ContentParser.finalizeContent(
        source: source,
        book: Book(
          bookUrl: 'https://novels-c.test/b/28654.html',
          origin: 'https://novels-c.test#♤test',
          name: '塞外孤星',
        ),
        chapter: BookChapter(
          title: '第1章',
          url: 'https://novels-c.test/r/28654/33046.html',
          bookUrl: 'https://novels-c.test/b/28654.html',
        ),
        contentStr: parsed.content,
        baseUrl: 'https://novels-c.test/r/28654/33046.html',
      );

      expect(finalized, contains('第一段内容'));
      expect(finalized, contains('第二段内容'));
      expect(finalized, contains('第三段内容'));
      expect(finalized, isNot(contains('本章未完')));
      expect(finalized, isNot(contains('本章完')));
    });
  });
}
