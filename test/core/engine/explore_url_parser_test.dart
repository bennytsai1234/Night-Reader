import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/explore_url_parser.dart';
import 'package:night_reader/core/models/book_source.dart';
import '../../test_helper.dart';

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  group('ExploreUrlParser', () {
    JavascriptRuntime? runtime;
    Object? runtimeError;

    setUp(() {
      runtimeError = null;
      try {
        runtime = getJavascriptRuntime();
      } catch (error) {
        runtime = null;
        runtimeError = error;
      }
    });

    tearDown(() {
      runtime?.dispose();
      runtime = null;
    });

    test('parseAsync caches js explore results per source', () async {
      const exploreRule = '''
        <js>
        JSON.stringify([
          {"title":"最新","url":"https://example.com/new"}
        ])
        </js>
      ''';
      final source = BookSource(
        bookSourceUrl: 'https://cache.example.com',
        bookSourceName: '快取測試源',
        exploreUrl: exploreRule,
      );
      await ExploreUrlParser.clearCache(source, exploreUrl: exploreRule);
      addTearDown(
        () => ExploreUrlParser.clearCache(source, exploreUrl: exploreRule),
      );

      var jsCalls = 0;
      final first = await ExploreUrlParser.parseAsync(
        exploreRule,
        source: source,
        jsExecutor: (_) async {
          jsCalls++;
          return '[{"title":"最新","url":"https://example.com/new"}]';
        },
      );

      final second = await ExploreUrlParser.parseAsync(
        exploreRule,
        source: source,
        jsExecutor: (_) async {
          jsCalls++;
          return '[{"title":"熱門","url":"https://example.com/hot"}]';
        },
      );

      expect(jsCalls, 1);
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(second.first.title, '最新');
      expect(second.first.url, 'https://example.com/new');
    });

    test('parseAsync supports static explore definitions', () async {
      final kinds = await ExploreUrlParser.parseAsync('''
        最新::https://example.com/new
        熱門::https://example.com/hot
        無連結分類
      ''');

      expect(kinds, hasLength(3));
      expect(kinds[0].title, '最新');
      expect(kinds[0].url, 'https://example.com/new');
      expect(kinds[1].title, '熱門');
      expect(kinds[1].url, 'https://example.com/hot');
      expect(kinds[2].title, '無連結分類');
      expect(kinds[2].url, isNull);
    });

    test('parseAsync awaits js explore definitions', () async {
      final source = BookSource(
        bookSourceUrl: 'https://bbxxxx.com',
        bookSourceName: 'BB成人小说',
      );

      final kinds = await ExploreUrlParser.parseAsync(
        '''
        <js>
        let html = java.ajax("https://bbxxxx.com/");
        JSON.stringify([
          {"title":"最新","url":"https://bbxxxx.com/rank/new/{{page}}.html"},
          {"title":"熱門","url":"https://bbxxxx.com/rank/hot/{{page}}.html"}
        ])
        </js>
        ''',
        source: source,
        jsExecutor: (jsSource) async {
          expect(jsSource, contains('java.ajax("https://bbxxxx.com/")'));
          return '''
          [
            {"title":"最新","url":"https://bbxxxx.com/rank/new/{{page}}.html"},
            {"title":"熱門","url":"https://bbxxxx.com/rank/hot/{{page}}.html"}
          ]
          ''';
        },
      );

      expect(kinds, hasLength(2));
      expect(kinds[0].title, '最新');
      expect(kinds[0].url, 'https://bbxxxx.com/rank/new/{{page}}.html');
      expect(kinds[1].title, '熱門');
      expect(kinds[1].url, 'https://bbxxxx.com/rank/hot/{{page}}.html');
    });

    test('parseAsync parses JSON object strings returned by js rules', () async {
      final kinds = await ExploreUrlParser.parseAsync(
        '@js: JSON.stringify({"title":"推薦","url":"https://example.com/recommend"})',
        jsExecutor:
            (_) async => '{"title":"推薦","url":"https://example.com/recommend"}',
      );

      expect(kinds, hasLength(1));
      expect(kinds.first.title, '推薦');
      expect(kinds.first.url, 'https://example.com/recommend');
    });

    test('parseAsync accepts trailing commas in JSON arrays', () async {
      final kinds = await ExploreUrlParser.parseAsync('''
        [
          {"title":"推薦","url":"https://example.com/recommend"},
        ]
        ''');

      expect(kinds, hasLength(1));
      expect(kinds.first.title, '推薦');
      expect(kinds.first.url, 'https://example.com/recommend');
    });

    test('parseAsync preserves Legado explore kind flex style', () async {
      final kinds = await ExploreUrlParser.parseAsync('''
        [
          {
            "title": "排行",
            "url": "https://example.com/rank",
            "style": {
              "layout_flexGrow": 1,
              "layout_flexShrink": 1,
              "layout_alignSelf": "center",
              "layout_flexBasisPercent": 0.5,
              "layout_wrapBefore": true
            }
          }
        ]
        ''');

      expect(kinds, hasLength(1));
      expect(kinds.first.title, '排行');
      expect(kinds.first.style?.layoutFlexGrow, 1);
      expect(kinds.first.style?.layoutAlignSelf, 'center');
      expect(kinds.first.style?.layoutFlexBasisPercent, 0.5);
      expect(kinds.first.style?.layoutWrapBefore, isTrue);
    });

    test('parseAsync flattens mixed lists returned by js rules', () async {
      final kinds = await ExploreUrlParser.parseAsync(
        '@js: ""',
        jsExecutor:
            (_) async => <dynamic>[
              {'title': '最新', 'url': 'https://example.com/new'},
              '{"title":"排行","url":"https://example.com/rank"}',
            ],
      );

      expect(kinds, hasLength(2));
      expect(kinds[0].title, '最新');
      expect(kinds[1].title, '排行');
    });

    test('parseAsync surfaces js runtime errors as error kinds', () async {
      final kinds = await ExploreUrlParser.parseAsync(
        '@js: java.ajax("https://example.com/explore")',
        source: BookSource(
          bookSourceUrl: 'https://error.example.com',
          bookSourceName: '錯誤源',
        ),
        jsExecutor: (_) async => 'JS_ERROR: Library not available',
      );

      expect(kinds, hasLength(1));
      expect(kinds.first.title, startsWith('ERROR:'));
      expect(kinds.first.url, contains('JS_ERROR:'));
    });

    test(
      'parseAsync does not retry sync fallback after async js failure',
      () async {
        const exploreRule =
            '@js: JSON.stringify([{"title":"推薦","url":"https://example.com/recommend"}])';
        final source = BookSource(
          bookSourceUrl: 'https://no-fallback.example.com',
          bookSourceName: '禁止重跑源',
          exploreUrl: exploreRule,
        );
        await ExploreUrlParser.clearCache(source, exploreUrl: exploreRule);
        addTearDown(
          () => ExploreUrlParser.clearCache(source, exploreUrl: exploreRule),
        );

        final kinds = await ExploreUrlParser.parseAsync(
          exploreRule,
          source: source,
          jsExecutor: (_) async => throw StateError('async failed'),
        );

        expect(kinds, hasLength(1));
        expect(kinds.first.title, startsWith('ERROR:'));
        expect(kinds.first.url, contains('async failed'));
      },
    );

    test('parseAsync serializes js explore execution to reduce overlap', () async {
      const firstRule =
          '@js: JSON.stringify([{"title":"第一個","url":"https://example.com/one"}])';
      const secondRule =
          '@js: JSON.stringify([{"title":"第二個","url":"https://example.com/two"}])';
      final firstSource = BookSource(
        bookSourceUrl: 'https://serial-one.example.com',
        bookSourceName: '序列源一',
        exploreUrl: firstRule,
      );
      final secondSource = BookSource(
        bookSourceUrl: 'https://serial-two.example.com',
        bookSourceName: '序列源二',
        exploreUrl: secondRule,
      );
      await ExploreUrlParser.clearCache(firstSource, exploreUrl: firstRule);
      await ExploreUrlParser.clearCache(secondSource, exploreUrl: secondRule);
      addTearDown(() async {
        await ExploreUrlParser.clearCache(firstSource, exploreUrl: firstRule);
        await ExploreUrlParser.clearCache(secondSource, exploreUrl: secondRule);
      });

      var activeExecutions = 0;
      var maxActiveExecutions = 0;

      Future<String> runExecutor(String payload) async {
        activeExecutions++;
        if (activeExecutions > maxActiveExecutions) {
          maxActiveExecutions = activeExecutions;
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
        activeExecutions--;
        return payload;
      }

      final results = await Future.wait([
        ExploreUrlParser.parseAsync(
          firstRule,
          source: firstSource,
          jsExecutor:
              (_) => runExecutor(
                '[{"title":"第一個","url":"https://example.com/one"}]',
              ),
        ),
        ExploreUrlParser.parseAsync(
          secondRule,
          source: secondSource,
          jsExecutor:
              (_) => runExecutor(
                '[{"title":"第二個","url":"https://example.com/two"}]',
              ),
        ),
      ]);

      expect(maxActiveExecutions, 1);
      expect(results[0].first.title, '第一個');
      expect(results[1].first.title, '第二個');
    });

    test('parseAsync supports legacy sync IIFE with async helpers', () async {
      if (runtime == null) {
        expect(runtimeError, isNotNull);
        return;
      }

      final source = BookSource(
        bookSourceUrl: 'https://example.com',
        bookSourceName: '同步 IIFE 測試源',
      );

      final kinds = await ExploreUrlParser.parseAsync('''
        <js>
        (() => {
          cookie.get('session');
          return JSON.stringify([
            {"title":"推薦","url":"https://example.com/recommend"}
          ]);
        })()
        </js>
        ''', source: source);

      expect(kinds, hasLength(1));
      expect(kinds.first.title, '推薦');
      expect(kinds.first.url, 'https://example.com/recommend');
    }, skip: quickJsSkip);

    test(
      'parseAsync normalizes legacy bare destructuring arrow params',
      () async {
        if (runtime == null) {
          expect(runtimeError, isNotNull);
          return;
        }

        final kinds = await ExploreUrlParser.parseAsync(
          '''
        @js:
        sort = [];
        push = (title, url) => sort.push({title: title, url: url});
        [["推薦", "https://example.com/recommend"]].map([title, url]=>{
          push(title, url);
        });
        JSON.stringify(sort)
        ''',
          source: BookSource(
            bookSourceUrl: 'https://example.com',
            bookSourceName: '解構參數測試源',
          ),
        );

        expect(kinds, hasLength(1));
        expect(kinds.first.title, '推薦');
        expect(kinds.first.url, 'https://example.com/recommend');
      },
      skip: quickJsSkip,
    );
  });
}
