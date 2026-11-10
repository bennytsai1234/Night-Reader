import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:night_reader/core/services/source_interaction.dart';

const _readable = '這是一段足夠長的正文內容，用來確認校驗會把它當成可以閱讀的章節。';

/// 各階段回傳什麼由測試指定；沒指定的階段給一本正常的書。
class _FakeBookSourceService extends BookSourceService {
  _FakeBookSourceService({this.search, this.info, this.chapters, this.content});

  final Future<List<SearchBook>> Function()? search;
  final Future<Book> Function(Book book)? info;
  final Future<List<BookChapter>> Function(Book book)? chapters;
  final Future<String> Function(BookChapter chapter)? content;

  final List<String> contentRequests = <String>[];
  final List<String> tocRequests = <String>[];

  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    final search = this.search;
    if (search != null) return search();
    return [
      SearchBook(
        bookUrl: 'https://site.example/book/1',
        name: '測試書',
        origin: source.bookSourceUrl,
      ),
    ];
  }

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    final info = this.info;
    if (info != null) return info(book);
    return book;
  }

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) async {
    tocRequests.add(book.name);
    final chapters = this.chapters;
    if (chapters != null) return chapters(book);
    return [
      for (var i = 0; i < 3; i++)
        BookChapter(
          url: 'https://site.example/book/1/$i.html',
          title: '第${i + 1}章',
          index: i,
        ),
    ];
  }

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    contentRequests.add(chapter.title);
    final content = this.content;
    if (content != null) return content(chapter);
    return _readable;
  }
}

/// 假裝網路層記下網站的一個回應（真正的請求由 `AppInterceptor` 記）。
void _siteAnswered(int status, String body) {
  final uri = Uri.parse('https://site.example/api');
  recordRequestUrl('GET', uri);
  recordResponse(
    Response<dynamic>(
      requestOptions: RequestOptions(path: uri.toString()),
      statusCode: status,
      data: body,
    ),
  );
}

const _searchOnly = IsolateCheckConfig(
  keyword: '我的',
  timeoutSeconds: 5,
  checkSearch: true,
  checkDiscovery: false,
  checkInfo: true,
  checkCategory: true,
  checkContent: true,
);

BookSource _source({String name = '測試書源', String? group}) => BookSource(
  bookSourceUrl: 'https://site.example',
  bookSourceName: name,
  bookSourceGroup: group,
  searchUrl: '/search?q={{key}}',
);

Future<(SourceCheckIsolateResult, BookSource)> _check(
  _FakeBookSourceService service, {
  BookSource? source,
}) async {
  final result = await SourceChecker(
    source: source ?? _source(),
    config: _searchOnly,
    service: service,
  ).run();
  return (result, BookSource.fromJson(result.updatedSourceJson));
}

void main() {
  test('a source that searches, opens and reads is healthy', () async {
    final (result, checked) = await _check(_FakeBookSourceService());

    expect(result.isHealthy, isTrue);
    expect(checked.runtimeHealth.category, SourceHealthCategory.healthy);
    expect(checked.bookSourceGroup, isNull);
  });

  test(
    'a new check drops the previous status tags but keeps user groups',
    () async {
      final (_, checked) = await _check(
        _FakeBookSourceService(),
        source: _source(group: '精選,$searchBrokenSourceGroupTag,異常'),
      );

      expect(checked.groupTags, {'精選'});
    },
  );

  test('an empty search marks search broken, still readable', () async {
    final (result, checked) = await _check(
      _FakeBookSourceService(search: () async => const <SearchBook>[]),
    );

    expect(result.isHealthy, isFalse);
    expect(checked.groupTags, contains(searchBrokenSourceGroupTag));
    expect(checked.runtimeHealth.allowsSearch, isFalse);
    expect(checked.runtimeHealth.allowsReading, isTrue);
  });

  test('a site that blocks Night Reader quarantines the source', () async {
    for (final reason in [
      ChallengeNotPassedException(),
      HumanVerificationRequiredException(),
      SiteBlockedException(),
    ]) {
      final (result, checked) = await _check(
        _FakeBookSourceService(
          search: () => Future.error(
            DioException(
              requestOptions: RequestOptions(path: 'https://site.example'),
              type: DioExceptionType.unknown,
              error: reason,
              message: reason.message,
            ),
          ),
        ),
      );

      expect(checked.isQuarantined, isTrue, reason: reason.message);
      expect(checked.runtimeHealth.allowsReading, isFalse);
      expect(result.message, contains(reason.message));
    }
  });

  test('a search timeout quarantines the source', () async {
    final (_, checked) = await _check(
      _FakeBookSourceService(
        search: () => Future.error(TimeoutException('搜尋超時')),
      ),
    );

    expect(checked.groupTags, contains(quarantineSourceGroupTag));
    expect(checked.isQuarantined, isTrue);
    expect(checked.runtimeHealth.allowsReading, isFalse);
  });

  test('a rule asking for web verification only marks the source', () async {
    final (_, checked) = await _check(
      _FakeBookSourceService(
        info: (_) => Future.error(
          SourceVerificationException(
            const SourceBrowseRequest(
              url: 'https://site.example/verify',
              title: '驗證',
              headers: {},
            ),
          ),
        ),
      ),
    );

    // 校驗不跳畫面、不隔離，只標狀態；書源照樣參加搜尋、照樣能開書，閱讀時
    // 遇到再去網頁上驗證（ADR 0038）。
    expect(checked.groupTags, contains(verificationRequiredSourceGroupTag));
    expect(checked.isQuarantined, isFalse);
    expect(checked.isCleanupCandidate, isFalse);
    expect(checked.isSearchEnabledByRuntime, isTrue);
    expect(checked.isReadingEnabledByRuntime, isTrue);
  });

  test(
    'a login wall on the content marks the source as needing login',
    () async {
      final (_, checked) = await _check(
        _FakeBookSourceService(
          content: (_) async => throw LoginCheckException('正文需要登入後閱讀'),
        ),
      );

      expect(checked.groupTags, contains(loginRequiredSourceGroupTag));
      // 要登入是書源的狀態，不是壞掉：照樣參加搜尋、照樣能開書，不列入清理
      // （ADR 0038）。
      expect(checked.isCleanupCandidate, isFalse);
      expect(checked.isSearchEnabledByRuntime, isTrue);
      expect(checked.isReadingEnabledByRuntime, isTrue);
    },
  );

  test('a readable chapter that mentions subscribing is healthy', () async {
    // 手机看书第一章的作者後記：抓得到的正文提到「订阅」不是登入牆。
    final (result, _) = await _check(
      _FakeBookSourceService(content: (_) async => '$_readable（在这里求收藏，求追更，订阅）'),
    );

    expect(result.isHealthy, isTrue);
  });

  // 付費章節不抓（ADR 0057）：只抽查免費章節。
  test('paid chapters are skipped and the free ones are checked', () async {
    final service = _FakeBookSourceService(
      chapters: (_) async => [
        BookChapter(url: 'https://site.example/1.html', title: '第一章'),
        BookChapter(
          url: 'https://site.example/2.html',
          title: '第二章',
          isVip: true,
        ),
      ],
    );
    final (result, checked) = await _check(service);

    expect(result.isHealthy, isTrue);
    expect(checked.groupTags, isNot(contains(loginRequiredSourceGroupTag)));
    expect(service.contentRequests, ['第一章']);
  });

  test(
    'a book of only paid chapters marks the source as needing login',
    () async {
      final service = _FakeBookSourceService(
        chapters: (_) async => [
          BookChapter(
            url: 'https://site.example/1.html',
            title: '第一章',
            isVip: true,
          ),
        ],
      );
      final (result, checked) = await _check(service);

      expect(checked.groupTags, contains(loginRequiredSourceGroupTag));
      expect(result.message, contains('付費章節'));
      expect(service.contentRequests, isEmpty);
    },
  );

  test(
    'a book served as a download file marks a download-only source',
    () async {
      final (_, checked) = await _check(
        _FakeBookSourceService(
          info: (book) async =>
              book.copyWith(tocUrl: 'https://site.example/down/1.txt'),
        ),
      );

      expect(checked.groupTags, contains(downloadOnlySourceGroupTag));
      expect(checked.isCleanupCandidate, isTrue);
    },
  );

  test(
    'short content in every probed chapter quarantines as content broken',
    () async {
      final service = _FakeBookSourceService(content: (_) async => '太短');
      final (result, checked) = await _check(service);

      expect(checked.groupTags, contains(contentBrokenSourceGroupTag));
      expect(checked.isQuarantined, isTrue);
      expect(result.message, contains('前 3 個候選章節'));
      expect(service.contentRequests, hasLength(3));
    },
  );

  test('one readable chapter is enough after a short one', () async {
    final service = _FakeBookSourceService(
      content: (chapter) async => chapter.title == '第1章' ? '太短' : _readable,
    );
    final (result, _) = await _check(service);

    expect(result.isHealthy, isTrue);
    expect(service.contentRequests, ['第1章', '第2章']);
  });

  test('an empty TOC quarantines as TOC broken', () async {
    final (_, checked) = await _check(
      _FakeBookSourceService(chapters: (_) async => const <BookChapter>[]),
    );

    expect(checked.groupTags, contains(tocBrokenSourceGroupTag));
    expect(checked.isQuarantined, isTrue);
  });

  test('a dropped connection is retried once before judging', () async {
    var attempts = 0;
    final service = _FakeBookSourceService(
      content: (_) async {
        if (attempts++ == 0) {
          throw DioException(
            requestOptions: RequestOptions(path: 'https://site.example/1'),
            type: DioExceptionType.connectionError,
          );
        }
        return _readable;
      },
    );
    final (result, _) = await _check(service);

    expect(result.isHealthy, isTrue);
    expect(service.contentRequests, ['第1章', '第1章']);
    expect(result.logs, contains(contains('重試一次')));
  });

  test('an empty response that breaks JSON.parse is retried once', () async {
    var attempts = 0;
    final service = _FakeBookSourceService(
      chapters: (book) async {
        if (attempts++ == 0) {
          _siteAnswered(200, '');
          throw ParsingException(
            '解析字串失敗',
            originalError: RuleJsException(
              'SyntaxError: unexpected end of input',
              code: 'JSON.parse(result)',
            ),
          );
        }
        return [BookChapter(url: 'https://site.example/1.html', title: '一')];
      },
    );
    final (result, _) = await _check(service);

    expect(result.isHealthy, isTrue);
    expect(service.tocRequests, hasLength(2));
  });

  test('a 503 the rule JS fetched itself is retried once', () async {
    // 規則 JS 用 java.ajax 抓 API：503 的錯誤頁交給規則，規則解析 JSON 失敗；
    // 校驗看的是網站回了 503，不是解析錯誤的文字。
    var attempts = 0;
    final service = _FakeBookSourceService(
      chapters: (book) async {
        if (attempts++ == 0) {
          _siteAnswered(503, '<html>Service Unavailable</html>');
          throw ParsingException(
            '解析字串失敗',
            originalError: RuleJsException("SyntaxError: unexpected token '<'"),
          );
        }
        return [BookChapter(url: 'https://site.example/1.html', title: '一')];
      },
    );
    final (result, _) = await _check(service);

    expect(result.isHealthy, isTrue);
    expect(service.tocRequests, hasLength(2));
  });

  test('an empty TOC from an empty page is fetched again', () async {
    var attempts = 0;
    final service = _FakeBookSourceService(
      chapters: (book) async {
        if (attempts++ == 0) {
          _siteAnswered(200, '');
          return const <BookChapter>[];
        }
        return [BookChapter(url: 'https://site.example/1.html', title: '一')];
      },
    );
    final (result, _) = await _check(service);

    expect(result.isHealthy, isTrue);
    expect(service.tocRequests, hasLength(2));
  });

  test('an empty TOC from a page with content is not retried', () async {
    final service = _FakeBookSourceService(
      chapters: (book) async {
        _siteAnswered(200, '<html><body>沒有章節</body></html>');
        return const <BookChapter>[];
      },
    );
    final (_, checked) = await _check(service);

    expect(checked.groupTags, contains(tocBrokenSourceGroupTag));
    expect(service.tocRequests, hasLength(1));
  });

  test(
    'a TOC retry fetches again instead of reusing the stored page',
    () async {
      // 詳情頁和目錄是同一頁：詳情那一段網站回了空白，存下的頁面就是壞的。
      final pagesSeen = <String?>[];
      final service = _FakeBookSourceService(
        info: (book) async {
          _siteAnswered(200, '');
          return book.copyWith()..tocHtml = '';
        },
        chapters: (book) async {
          pagesSeen.add(book.tocHtml);
          return book.tocHtml == null
              ? [BookChapter(url: 'https://site.example/1.html', title: '一')]
              : const <BookChapter>[];
        },
      );
      final (result, _) = await _check(service);

      expect(result.isHealthy, isTrue);
      expect(pagesSeen, ['', null]);
    },
  );

  test('a rule error is not retried and its diagnosis shows the JS', () async {
    final service = _FakeBookSourceService(
      chapters: (_) async => throw ParsingException(
        '解析字串失敗',
        originalError: RuleJsException(
          'SyntaxError: invalid increment/decrement operand',
          code: 'java.put("bid",2024--01)',
        ),
      ),
    );
    final (result, checked) = await _check(service);

    expect(checked.groupTags, contains(tocBrokenSourceGroupTag));
    expect(service.tocRequests, hasLength(1));
    expect(result.diagnostics.single, contains('java.put("bid",2024--01)'));
  });

  test('a timeout is not retried: a slow site is just as slow again', () async {
    var searches = 0;
    await _check(
      _FakeBookSourceService(
        search: () {
          searches++;
          return Future.error(TimeoutException('搜尋超時'));
        },
      ),
    );

    expect(searches, 1);
  });

  group('when the first book will not open', () {
    final twoBooks = [
      for (final (i, name) in ['第一本', '第二本'].indexed)
        SearchBook(
          bookUrl: 'https://site.example/book/${i + 1}',
          name: name,
          origin: 'https://site.example',
        ),
    ];

    test('a second book that opens keeps the source healthy', () async {
      final service = _FakeBookSourceService(
        search: () async => twoBooks,
        chapters: (book) async => book.name == '第一本'
            ? const <BookChapter>[]
            : [BookChapter(url: 'https://site.example/2/1.html', title: '一')],
      );
      final (result, checked) = await _check(service);

      expect(result.isHealthy, isTrue);
      expect(checked.isQuarantined, isFalse);
      expect(service.tocRequests, ['第一本', '第二本']);
    });

    test('a second book that also fails quarantines the source', () async {
      final service = _FakeBookSourceService(
        search: () async => twoBooks,
        chapters: (_) async => const <BookChapter>[],
      );
      final (_, checked) = await _check(service);

      expect(checked.groupTags, contains(tocBrokenSourceGroupTag));
      expect(checked.isQuarantined, isTrue);
      expect(service.tocRequests, ['第一本', '第二本']);
    });

    test('a book needing login is not a reason to try another', () async {
      final service = _FakeBookSourceService(
        search: () async => twoBooks,
        content: (_) async => throw LoginCheckException('正文需要登入後閱讀'),
      );
      final (_, checked) = await _check(service);

      expect(checked.groupTags, contains(loginRequiredSourceGroupTag));
      expect(service.tocRequests, ['第一本']);
    });
  });

  test('a diagnosis lists the requests and what the site answered', () async {
    final service = _FakeBookSourceService(
      chapters: (_) async {
        final uri = Uri.parse('https://mirror.example/api/toc');
        recordRequestUrl('GET', uri);
        recordResponse(
          Response<dynamic>(
            requestOptions: RequestOptions(path: uri.toString()),
            statusCode: 200,
            data: '',
            headers: Headers.fromMap({
              Headers.contentTypeHeader: ['application/json'],
            }),
          ),
        );
        return const <BookChapter>[];
      },
    );
    final (result, _) = await _check(service);

    expect(
      result.diagnostics.single,
      allOf(
        contains('https://mirror.example/api/toc'),
        contains('← https://mirror.example/api/toc 200 application/json，0 字'),
      ),
    );
  });

  test('an unsupported source is filtered before any request', () async {
    final service = _FakeBookSourceService(
      search: () => fail('unsupported sources should not be searched'),
    );
    final (_, checked) = await _check(
      service,
      source: _source(name: '某某影視')..bookSourceType = SourceType.video,
    );

    expect(checked.groupTags, contains(nonNovelSourceGroupTag));
    expect(checked.isCleanupCandidate, isTrue);
  });

  group('the chapter content decides the kind', () {
    const pictures =
        '　　<img src="https://img.example/1.jpg">\n'
        '　　<img src="https://img.example/2.jpg">\n'
        '　　<img src="https://img.example/3.jpg">';
    final prose = '　　${'夜色很深，' * 60}';

    test('a text source whose chapters are pictures becomes a comic '
        'source', () async {
      final (result, checked) = await _check(
        _FakeBookSourceService(content: (_) async => pictures),
      );

      expect(result.isHealthy, isTrue);
      expect(checked.sourceKind, BookSourceKind.comic);
      expect(checked.isCleanupCandidate, isFalse);
      expect(result.logs.join('\n'), contains('改寫書源類型'));
    });

    test(
      'a comic source is checked like any other and stays a comic',
      () async {
        final service = _FakeBookSourceService(content: (_) async => pictures);
        final (result, checked) = await _check(
          service,
          source: _source(name: '某某漫畫')..bookSourceType = 2,
        );

        expect(result.isHealthy, isTrue);
        expect(service.contentRequests, isNotEmpty);
        expect(checked.bookSourceType, 2);
      },
    );

    test('an aggregate source keeps its type whatever its chapters are; '
        'its book decides an unclear chapter', () async {
      // 聚合源切在漫畫模式：正文是圖片，書源類型照作者寫的 0。
      final aggregate = _source(name: '聚合')
        ..ruleToc = TocRule(chapterList: '<js>book.type = 64; result</js>');
      final (result, checked) = await _check(
        _FakeBookSourceService(content: (_) async => pictures),
        source: aggregate,
      );

      expect(result.isHealthy, isTrue);
      expect(checked.bookSourceType, SourceType.book);
      expect(result.logs.join('\n'), isNot(contains('改寫書源類型')));
    });

    test('a comic source whose chapters are prose becomes a novel', () async {
      final (_, checked) = await _check(
        _FakeBookSourceService(content: (_) async => prose),
        source: _source(name: '漫畫小說網')..bookSourceType = 2,
      );

      expect(checked.sourceKind, BookSourceKind.novel);
    });

    test('an unclear chapter keeps the type', () async {
      final (result, checked) = await _check(
        _FakeBookSourceService(
          content: (_) async => '<img src="https://img.example/1.jpg">',
        ),
        source: _source()..bookSourceType = 2,
      );

      expect(result.isHealthy, isTrue);
      expect(checked.bookSourceType, 2);
    });

    test('a comic source without pictures has broken content', () async {
      final (_, checked) = await _check(
        _FakeBookSourceService(content: (_) async => ''),
        source: _source()..bookSourceType = 2,
      );

      expect(checked.groupTags, contains(contentBrokenSourceGroupTag));
      expect(checked.bookSourceType, 2);
    });
  });
}
