import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  test(
    'search bookUrl can reference fields populated earlier on SearchBook',
    () async {
      final source = BookSource(
        bookSourceUrl: 'source://test',
        bookSourceName: 'Test Source',
        ruleSearch: SearchRule(
          bookList: r'$.data[*]',
          name: r'$.name',
          kind: r'$.kind',
          bookUrl: r'https://example.com/book/{{book.kind}}',
        ),
      );

      final books = await BookListParser.parse(
        source: source,
        body: '{"data":[{"name":"測試書","kind":"47749"}]}',
        baseUrl: 'https://example.com/search',
        isSearch: true,
      );

      expect(books, hasLength(1));
      expect(books.first.kind, '47749');
      expect(books.first.bookUrl, 'https://example.com/book/47749');
    },
    skip: quickJsSkip,
  );

  test(
    'explore falls back to search rules when ruleExplore.bookList is empty',
    () async {
      final source = BookSource(
        bookSourceUrl: 'source://test',
        bookSourceName: 'Test Source',
        ruleSearch: SearchRule(
          bookList: '.book-item',
          name: '.name@text',
          author: '.author@text',
          bookUrl: '.name@href',
        ),
        ruleExplore: ExploreRule(),
      );

      const html = '''
      <div class="book-item">
        <a class="name" href="/book/1">書一</a>
        <span class="author">作者甲</span>
      </div>
      ''';

      final books = await BookListParser.parse(
        source: source,
        body: html,
        baseUrl: 'https://example.com/explore',
        isSearch: false,
      );

      expect(books, hasLength(1));
      expect(books.first.name, '書一');
      expect(books.first.author, '作者甲');
      expect(books.first.bookUrl, 'https://example.com/book/1');
    },
  );

  test(
    'explore falls back to search rules when configured explore bookList yields no elements',
    () async {
      final source = BookSource(
        bookSourceUrl: 'source://test',
        bookSourceName: 'Test Source',
        ruleSearch: SearchRule(
          bookList: r'$.data.books[*]',
          name: r'$.title',
          author: r'$.author',
          bookUrl: r'https://example.com/book/{{$.id}}',
        ),
        ruleExplore: ExploreRule(
          bookList: r'$[*]',
          name: r'$.title',
          author: r'$.author',
          bookUrl: r'https://example.com/book/{{$.id}}',
        ),
      );

      const body = '''
      {
        "data": {
          "books": [
            {"id":"100","title":"書一","author":"作者甲"}
          ]
        }
      }
      ''';

      final books = await BookListParser.parse(
        source: source,
        body: body,
        baseUrl: 'https://example.com/explore',
        isSearch: false,
      );

      expect(books, hasLength(1));
      expect(books.first.name, '書一');
      expect(books.first.author, '作者甲');
      expect(books.first.bookUrl, 'https://example.com/book/100');
    },
  );

  test(
    'explore fallback never exposes a transient source-rule mutation',
    () async {
      final originalExploreRule = ExploreRule(
        bookList: '.wrong',
        name: '.missing-title@text',
        bookUrl: '.missing-title@href',
      );
      final source = BookSource(
        bookSourceUrl: 'source://shared-state-test',
        bookSourceName: '共享狀態測試源',
        ruleSearch: SearchRule(
          bookList: '.book-item',
          name: '.title@text',
          author: '.author@text',
          bookUrl: '.title@href',
        ),
        ruleExplore: originalExploreRule,
      );
      var observedMutation = false;

      final books = await BookListParser.parse(
        source: source,
        body: '''
      <div class="wrong">不是書籍項目</div>
      <div class="book-item">
        <a class="title" href="/book/1">書一</a>
        <span class="author">作者甲</span>
      </div>
      ''',
        baseUrl: 'https://example.com/explore',
        isSearch: false,
        filter: (_, _) {
          observedMutation =
              observedMutation ||
              !identical(source.ruleExplore, originalExploreRule);
          return true;
        },
      );

      expect(books.single.name, '書一');
      expect(observedMutation, isFalse);
      expect(identical(source.ruleExplore, originalExploreRule), isTrue);
    },
  );

  test('dedup identity distinguishes separator characters in fields', () async {
    final source = BookSource(
      bookSourceUrl: 'source://dedup-test',
      bookSourceName: '去重測試源',
      ruleSearch: SearchRule(
        bookList: r'$.items[*]',
        name: r'$.name',
        author: r'$.author',
        bookUrl: r'$.url',
      ),
    );

    final books = await BookListParser.parse(
      source: source,
      body: '''
      {
        "items": [
          {
            "name": "A|B",
            "author": "C",
            "url": "https://example.com/shared"
          },
          {
            "name": "A",
            "author": "B|C",
            "url": "https://example.com/shared"
          }
        ]
      }
      ''',
      baseUrl: 'https://example.com/search',
      isSearch: true,
    );

    expect(books.map((book) => (book.name, book.author)), [
      ('A|B', 'C'),
      ('A', 'B|C'),
    ]);
  });
}
