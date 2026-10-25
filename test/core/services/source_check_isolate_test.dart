import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:night_reader/core/services/source_validation_context.dart';

const _readable = '這是一段足夠長的正文內容，用來確認校驗會把它當成可以閱讀的章節。';

/// 各階段回傳什麼由測試指定；沒指定的階段給一本正常的書。
class _FakeBookSourceService extends BookSourceService {
  _FakeBookSourceService({this.search, this.info, this.chapters, this.content});

  final Future<List<SearchBook>> Function()? search;
  final Future<Book> Function(Book book)? info;
  final Future<List<BookChapter>> Function()? chapters;
  final Future<String> Function(BookChapter chapter)? content;

  final List<String> contentRequests = <String>[];

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
    final chapters = this.chapters;
    if (chapters != null) return chapters();
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

  test(
    'a rule asking for interactive verification quarantines the source',
    () async {
      final (_, checked) = await _check(
        _FakeBookSourceService(
          info: (_) => Future.error(
            const SourceInteractionBlockedException('批量校驗不執行互動驗證'),
          ),
        ),
      );

      expect(checked.groupTags, contains(quarantineSourceGroupTag));
      expect(checked.isQuarantined, isTrue);
    },
  );

  test('VIP text in the content marks the source as needing login', () async {
    final (_, checked) = await _check(
      _FakeBookSourceService(content: (_) async => '本章為VIP章節，請登入後閱讀全文內容。'),
    );

    expect(checked.groupTags, contains(loginRequiredSourceGroupTag));
    expect(checked.isCleanupCandidate, isTrue);
  });

  test(
    'a locked chapter in the TOC marks the source as needing login',
    () async {
      final service = _FakeBookSourceService(
        chapters: () async => [
          BookChapter(url: 'https://site.example/1.html', title: '第一章'),
          BookChapter(
            url: 'https://site.example/2.html',
            title: '第二章',
            isVip: true,
          ),
        ],
      );
      final (result, checked) = await _check(service);

      expect(checked.groupTags, contains(loginRequiredSourceGroupTag));
      expect(result.message, contains('第二章'));
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
      _FakeBookSourceService(chapters: () async => const <BookChapter>[]),
    );

    expect(checked.groupTags, contains(tocBrokenSourceGroupTag));
    expect(checked.isQuarantined, isTrue);
  });

  test('a non-novel source is filtered before any request', () async {
    final service = _FakeBookSourceService(
      search: () => fail('non-novel sources should not be searched'),
    );
    final (_, checked) = await _check(service, source: _source(name: '某某漫畫'));

    expect(checked.groupTags, contains(nonNovelSourceGroupTag));
    expect(checked.isCleanupCandidate, isTrue);
  });
}
