import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/core/background_work/reading_fetches.dart';
import 'package:night_reader/features/search/background_search.dart';
import 'package:night_reader/features/search/models/search_scope.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePlatform implements BackgroundWorkPlatform {
  final List<BackgroundWorkStatus> shown = [];
  int hides = 0;

  @override
  Future<bool> show(BackgroundWorkStatus status) async {
    shown.add(status);
    return true;
  }

  @override
  Future<void> hide() async => hides++;

  @override
  set onAction(void Function(String action)? handler) {}
}

class _OtherJob implements BackgroundJob {
  @override
  void pauseFromSystem() {}
  @override
  void endFromSystem() {}
  @override
  void openFromNotification() {}
}

/// 向書源搜尋的那一步：每個書源送出時記下，等測試決定回什麼；取消時照
/// Dio 丟出取消。
/// 存搜尋紀錄要等 [gate]：新的一次搜尋停在開始前那段空檔。
class _GatedKeywordDao extends SearchKeywordDao {
  _GatedKeywordDao(super.db);

  Completer<void> gate = Completer<void>();

  @override
  Future<void> saveKeyword(String word) async {
    await gate.future;
    return super.saveKeyword(word);
  }
}

class _Loader {
  /// 這些書源不理會取消（網站卡住、規則跑不完），要測試回了才回。
  final Set<String> ignoresCancel = {};
  final List<String> sent = [];
  final List<String> cancelled = [];
  final Map<String, Completer<List<SearchBook>>> _pending = {};

  Future<List<SearchBook>> call(
    BookSource source,
    String key, {
    CancelToken? cancelToken,
  }) {
    final name = source.bookSourceName;
    sent.add(name);
    final completer = Completer<List<SearchBook>>();
    _pending[name] = completer;
    cancelToken?.whenCancel.then((error) {
      cancelled.add(name);
      if (ignoresCancel.contains(name)) return;
      if (!completer.isCompleted) completer.completeError(error);
    });
    return completer.future;
  }

  /// [name] 這個書源回一本「[name]書」（[empty] 時回零本）。
  void answer(String name, {bool empty = false}) {
    _pending.remove(name)!.complete([
      if (!empty)
        SearchBook(
          bookUrl: 'https://$name.example/book',
          name: '$name書',
          author: '作者',
          origin: 'https://$name.example',
          originName: name,
        ),
    ]);
  }

  void fail(String name) =>
      _pending.remove(name)!.completeError(StateError('網站壞了'));
}

/// 讓搜尋與結果檔的寫入往前跑完（寫檔要真的等一下）。
/// 等到 [done]（第一次搜尋要等繁簡字典載入）。
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await settle();
  }
}

Future<void> settle() async {
  await pumpEventQueue();
  await Future<void>.delayed(const Duration(milliseconds: 30));
  await pumpEventQueue();
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late _FakePlatform platform;
  late BackgroundWork work;

  BackgroundSearches searches([_Loader? loader, ReadingFetches? fetches]) =>
      BackgroundSearches(
        work: work,
        directory: () async => dir,
        loader: loader?.call,
        readingFetches: fetches ?? ReadingFetches(),
      );

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      )
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<SearchBookDao>(SearchBookDao(db))
      ..registerSingleton<SearchKeywordDao>(SearchKeywordDao(db))
      ..registerSingleton<AiFindDao>(AiFindDao(db));
    await getIt<BookSourceDao>().upsertAll([
      for (final (i, name) in ['甲', '乙', '丙'].indexed)
        BookSource(
          bookSourceUrl: 'https://$name.example',
          bookSourceName: name,
          customOrder: i,
        ),
    ]);
    dir = Directory.systemTemp.createTempSync('background-search');
    platform = _FakePlatform();
    work = BackgroundWork(platform: platform);
  });

  tearDown(() async {
    await settle();
    await db.close();
    await GetIt.instance.reset();
    dir.deleteSync(recursive: true);
  });

  Future<SearchProvider> page(
    BackgroundSearches searches,
    _Loader loader, {
    bool resume = false,
  }) async {
    final provider = SearchProvider(
      entrance: Future<void>.value(),
      searchLoader: loader.call,
      backgroundSearches: searches,
      resumeBackground: resume,
    );
    await provider.ready;
    return provider;
  }

  List<String> names(SearchProvider provider) =>
      provider.results.map((book) => book.name).toList();

  test('a search moved to the background finishes after its page closes, '
      'and a blank search page shows the same results', () async {
    final background = searches();
    final loader = _Loader();
    final first = await page(background, loader);
    unawaited(first.search('night'));
    await until(() => loader.sent.length == 3);
    expect(loader.sent, ['甲', '乙', '丙']);
    loader.answer('甲');
    await settle();

    expect(first.canMoveToBackground, isTrue);
    first.moveToBackground();
    expect(first.canMoveToBackground, isFalse);
    expect(work.isBusy, isTrue);
    first.dispose();

    loader
      ..answer('乙', empty: true)
      ..answer('丙');
    final run = background.current!;
    await until(() => run.isFinished);
    expect(run.isFinished, isTrue);
    expect(work.isBusy, isFalse);
    expect(platform.shown.first.title, '搜尋書籍 · night');

    final again = await page(background, loader, resume: true);
    expect(again.lastSearchKey, 'night');
    expect(again.isSearching, isFalse);
    expect(names(again), unorderedEquals(['甲書', '丙書']));
    // 搜過的書源不重送。
    expect(loader.sent, ['甲', '乙', '丙']);

    // 看過、離開搜尋頁之後就收掉，下次打開是空白的。
    again.dispose();
    await until(() => background.current == null);
    expect(background.current, isNull);
    final blank = await page(background, loader, resume: true);
    addTearDown(blank.dispose);
    expect(blank.lastSearchKey, isEmpty);
  });

  test('a search left on its page stops when the page closes', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    provider.dispose();
    await until(() => background.current == null);
    expect(background.current, isNull);
    expect(work.isBusy, isFalse);
  });

  test('a paused search is read back after the app restarts and resumes '
      'only the sources it had not finished', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    loader.answer('甲');
    loader.fail('乙');
    await settle();
    provider.moveToBackground();
    provider.pauseBackground();
    await until(() => background.current?.isPaused ?? false);
    expect(background.current!.isPaused, isTrue);
    expect(work.isBusy, isFalse);
    provider.dispose();

    // 夜讀被收掉、重新打開。
    final loader2 = _Loader();
    final restarted = searches(loader2);
    await restarted.restore();
    final run = restarted.current!;
    expect(run.isPaused, isTrue);

    final reopened = await page(restarted, loader2, resume: true);
    addTearDown(reopened.dispose);
    await settle();
    expect(reopened.lastSearchKey, 'night');
    expect(names(reopened), ['甲書']);
    expect(reopened.completedSources, 2);
    expect(reopened.totalSources, 3);
    expect(reopened.failedSources, 1);
    expect(reopened.isBackgroundPaused, isTrue);

    await reopened.resumeBackground();
    await settle();
    expect(loader2.sent, ['丙']);
    loader2.answer('丙');
    await until(() => run.isFinished);
    expect(run.isFinished, isTrue);
    expect(names(reopened), unorderedEquals(['甲書', '丙書']));
    expect(reopened.completedSources, 3);
    expect(reopened.sourceFailures.single.source.bookSourceName, '乙');
  });

  test('a finished search not yet looked at survives a restart', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    provider.moveToBackground();
    provider.dispose();
    for (final name in ['甲', '乙', '丙']) {
      loader.answer(name);
    }
    await settle();

    await until(() => background.current!.isFinished);
    final restarted = searches();
    await restarted.restore();
    expect(restarted.current!.isFinished, isTrue);
    final reopened = await page(restarted, _Loader(), resume: true);
    addTearDown(reopened.dispose);
    await settle();
    expect(names(reopened), hasLength(3));
    expect(reopened.isBackgroundPaused, isFalse);
  });

  test('ending a background search keeps what it found', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    loader.answer('甲');
    await settle();
    provider.moveToBackground();
    provider.stopSearch();
    await until(() => background.current!.isFinished);
    expect(background.current!.isFinished, isTrue);
    expect(names(provider), ['甲書']);
    expect(provider.isSearching, isFalse);
  });

  test('a new search on a resumed page ends the background one', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    provider.moveToBackground();
    provider.dispose();

    final reopened = await page(background, loader, resume: true);
    addTearDown(reopened.dispose);
    unawaited(reopened.search('other'));
    await until(() => background.current == null);
    expect(background.current, isNull);
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty);
    expect(reopened.lastSearchKey, 'other');
    expect(reopened.canMoveToBackground, isTrue);
  });

  test('another background job greys out moving to the background', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    work.begin(
      _OtherJob(),
      const BackgroundWorkStatus(title: '校驗書源', text: ''),
    );
    expect(provider.canMoveToBackground, isFalse);
    provider.moveToBackground();
    expect(background.current, isNull);
  });

  test('a background search sends its next source only after the reader '
      'has its chapter', () async {
    await GetIt.instance<SharedPreferences>().setInt(PreferKey.threadCount, 1);
    final fetches = ReadingFetches();
    final background = searches(null, fetches);
    final loader = _Loader();
    final provider = await page(background, loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    expect(loader.sent, ['甲']);
    provider.moveToBackground();

    final chapter = Completer<String>();
    final reading = fetches.track(() => chapter.future);
    loader.answer('甲');
    await settle();
    expect(loader.sent, ['甲']);

    chapter.complete('正文');
    await reading;
    await settle();
    expect(loader.sent, ['甲', '乙']);
  });

  test('pausing while it waits for the reader settles at once', () async {
    await GetIt.instance<SharedPreferences>().setInt(PreferKey.threadCount, 1);
    final fetches = ReadingFetches();
    final background = searches(null, fetches);
    final loader = _Loader();
    final provider = await page(background, loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    provider.moveToBackground();
    final chapter = Completer<String>();
    unawaited(fetches.track(() => chapter.future));
    loader.answer('甲');
    await settle();

    provider.pauseBackground();
    await until(() => background.current!.isPaused);
    expect(background.current!.isPaused, isTrue);
    expect(loader.sent, ['甲']);
    chapter.complete('正文');
  });

  test('a search paused before it has sent anything sends nothing until it '
      'resumes', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    addTearDown(provider.dispose);
    // 還在存搜尋紀錄就放到背景、按暫停。
    unawaited(provider.search('night'));
    provider.moveToBackground();
    provider.pauseBackground();
    await until(() => background.current!.isPaused);
    await settle();
    expect(loader.sent, isEmpty);

    await provider.resumeBackground();
    await until(() => loader.sent.length == 3);
    expect(loader.sent, ['甲', '乙', '丙']);
  });

  test('ending while it is still pausing ends it', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    provider.moveToBackground();
    provider.pauseBackground();
    provider.stopSearch();
    await until(() => background.current!.isFinished);
    expect(background.current!.isFinished, isTrue);
    expect(provider.isBackgroundPaused, isFalse);
  });

  test('ending while the pause waits for the results file ends it', () async {
    final hold = Completer<void>();
    var holding = false;
    final background = BackgroundSearches(
      work: work,
      directory: () async {
        if (holding) await hold.future;
        return dir;
      },
      readingFetches: ReadingFetches(),
    );
    final loader = _Loader();
    final provider = await page(background, loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    provider.moveToBackground();
    await settle();
    // 一個書源回來了，它那一行卡在寫檔：暫停停好之前要等它。
    holding = true;
    loader.answer(loader.sent.first);
    await settle();
    provider.pauseBackground();
    final run = background.current!;
    await until(() => run.search.running == null);
    expect(run.isPaused, isFalse, reason: '還在等結果檔寫完');

    provider.stopSearch();
    hold.complete();
    await until(() => !run.isRunning);
    expect(run.isFinished, isTrue, reason: '結束蓋過暫停');
    expect(run.isPaused, isFalse);
  });

  test('pausing keeps a source that has just come back', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    provider.moveToBackground();
    loader.answer('甲');
    // 還沒到合併結果的 100 ms 就暫停。
    await pumpEventQueue();
    provider.pauseBackground();
    await until(() => background.current!.isPaused);
    expect(names(provider), ['甲書']);
  });

  test(
    'a page closed before its results showed does not count as seen',
    () async {
      final background = searches();
      final loader = _Loader();
      final provider = await page(background, loader);
      unawaited(provider.search('night'));
      await until(() => loader.sent.isNotEmpty);
      provider.moveToBackground();
      provider.dispose();
      for (final name in ['甲', '乙', '丙']) {
        loader.answer(name);
      }
      await until(() => background.current!.isFinished);

      // 換頁還沒播完就返回。
      final sliding = SearchProvider(
        entrance: Completer<void>().future,
        searchLoader: loader.call,
        backgroundSearches: background,
        resumeBackground: true,
      );
      sliding.dispose();
      await settle();
      expect(background.current, isNotNull);
      expect(background.resumable, isNotNull);
    },
  );

  test('two pages on one background search: a new search on one leaves the '
      'other showing its results', () async {
    final background = searches();
    final loader = _Loader();
    final first = await page(background, loader);
    unawaited(first.search('night'));
    await until(() => loader.sent.isNotEmpty);
    loader.answer('甲');
    await settle();
    first.moveToBackground();
    final second = await page(background, loader, resume: true);
    addTearDown(second.dispose);

    unawaited(second.search('other'));
    await settle();
    expect(names(first), ['甲書']);
    expect(background.current, isNotNull);
    first.dispose();
    await until(() => background.current == null);
    expect(background.current, isNull);
  });

  test('a resumed page keeps the kind that search was made in', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    provider.moveToBackground();
    provider.dispose();
    for (final name in ['甲', '乙', '丙']) {
      loader.answer(name);
    }
    await until(() => background.current!.isFinished);
    final resumed = await page(background, loader, resume: true);
    addTearDown(resumed.dispose);
    expect(resumed.kind, BookSourceKind.novel);
    expect(names(resumed), hasLength(3));
  });

  group('changing the conditions on a resumed page searches with the new '
      'ones', () {
    final comic = BookSource(
      bookSourceUrl: 'https://丁.example',
      bookSourceName: '丁',
      bookSourceType: SourceType.image,
      customOrder: 3,
    );

    /// 搜小說、放到背景、搜完，再從沒帶關鍵字的入口接回。
    Future<(SearchProvider, _Loader)> resumed() async {
      await GetIt.instance<BookSourceDao>().upsert(comic);
      final background = searches();
      final loader = _Loader();
      final provider = await page(background, loader);
      unawaited(provider.search('night'));
      await until(() => loader.sent.length == 3);
      provider.moveToBackground();
      provider.dispose();
      for (final name in ['甲', '乙', '丙']) {
        loader.answer(name);
      }
      await until(() => background.current!.isFinished);
      final reopened = await page(background, loader, resume: true);
      addTearDown(reopened.dispose);
      expect(reopened.kind, BookSourceKind.novel);
      loader.sent.clear();
      return (reopened, loader);
    }

    test('another kind', () async {
      final (provider, loader) = await resumed();
      provider.setKind(BookSourceKind.comic);
      expect(provider.kind, BookSourceKind.comic);
      await until(() => loader.sent.isNotEmpty);
      expect(loader.sent, ['丁']);
      expect(provider.kind, BookSourceKind.comic);
    });

    test('one source of another kind', () async {
      final (provider, loader) = await resumed();
      await provider.updateSearchScope(SearchScope.fromSource(comic));
      await until(() => loader.sent.isNotEmpty);
      expect(loader.sent, ['丁']);
      expect(provider.kind, BookSourceKind.comic);
    });
  });

  test('retrying failed sources after a background search is an ordinary '
      'search', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.length == 3);
    provider.moveToBackground();
    provider.dispose();
    loader
      ..answer('甲')
      ..fail('乙')
      ..answer('丙');
    await until(() => background.current!.isFinished);

    final resumed = await page(background, loader, resume: true);
    addTearDown(resumed.dispose);
    unawaited(resumed.retryFailedSources());
    await until(() => background.current == null);
    expect(background.current, isNull);
    await until(() => loader.sent.length == 4);
    expect(loader.sent.last, '乙');
    expect(names(resumed), unorderedEquals(['甲書', '丙書']));
    expect(resumed.showsMoveToBackground, isTrue);
  });

  Future<void> disable(String name) async {
    final dao = GetIt.instance<BookSourceDao>();
    final source = (await dao.getByUrl('https://$name.example'))!;
    await dao.upsert(source..enabled = false);
  }

  test('retrying keeps showing what that search found after its kind lost '
      'its other sources', () async {
    final dao = GetIt.instance<BookSourceDao>();
    await dao.upsertAll([
      // 漫畫類的聚合源：搜小說時也送（ADR 0056）。
      BookSource(
        bookSourceUrl: 'https://乙.example',
        bookSourceName: '乙',
        bookSourceType: SourceType.image,
        jsLib: 'function m(){ book.type = 64; }',
        customOrder: 1,
      ),
      BookSource(
        bookSourceUrl: 'https://戊.example',
        bookSourceName: '戊',
        bookSourceType: SourceType.audio,
        customOrder: 4,
      ),
    ]);
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.length == 3);
    expect(loader.sent, ['甲', '乙', '丙']);
    provider.moveToBackground();
    provider.dispose();
    loader
      ..answer('甲')
      ..fail('乙')
      ..answer('丙');
    await until(() => background.current!.isFinished);
    await disable('甲');
    await disable('丙');

    final resumed = await page(background, loader, resume: true);
    addTearDown(resumed.dispose);
    expect(names(resumed), unorderedEquals(['甲書', '丙書']));
    unawaited(resumed.retryFailedSources());
    await until(() => loader.sent.length == 4);
    expect(loader.sent.last, '乙');
    expect(resumed.kind, BookSourceKind.novel);
    expect(names(resumed), unorderedEquals(['甲書', '丙書']));
  });

  test('a new search stops the one before it while it is still saving its '
      'keyword', () async {
    final keywords = _GatedKeywordDao(db);
    GetIt.instance
      ..unregister<SearchKeywordDao>()
      ..registerSingleton<SearchKeywordDao>(keywords);
    final loader = _Loader();
    final provider = await page(searches(), loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    keywords.gate.complete();
    await until(() => loader.sent.length == 3);

    keywords.gate = Completer<void>();
    unawaited(provider.search('other'));
    await settle();
    // 舊的那次已經取消：之後才回來的結果與範圍進不到新的這次。
    expect(loader.cancelled, ['甲', '乙', '丙']);
    keywords.gate.complete();
    await until(() => loader.sent.length == 6);
  });

  test('ending a search while it saves its keyword sends nothing', () async {
    final keywords = _GatedKeywordDao(db);
    GetIt.instance
      ..unregister<SearchKeywordDao>()
      ..registerSingleton<SearchKeywordDao>(keywords);
    final loader = _Loader();
    final provider = await page(searches(), loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    expect(provider.isSearching, isTrue);
    provider.stopSearch();
    expect(provider.isSearching, isFalse);
    keywords.gate.complete();
    await settle();
    expect(loader.sent, isEmpty);
    expect(provider.isSearching, isFalse);
  });

  test('retrying keeps the number of sources the whole search asked', () async {
    final loader = _Loader();
    final provider = await page(searches(), loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.length == 3);
    loader
      ..answer('甲')
      ..fail('乙')
      ..answer('丙');
    await until(() => !provider.isSearching);
    expect(provider.failedSources, 1);
    expect(provider.searchedSourceCount, 3);

    unawaited(provider.retryFailedSources());
    await until(() => loader.sent.length == 4);
    expect(provider.isSearching, isTrue);
    expect(provider.searchedSourceCount, 3);
    loader.fail('乙');
    await until(() => !provider.isSearching);
    expect(provider.failedSources, 1);
    expect(provider.searchedSourceCount, 3);
  });

  test('a new search started while a retry has not come back counts its own '
      'sources', () async {
    final loader = _Loader();
    final provider = await page(searches(), loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.length == 3);
    loader
      ..answer('甲')
      ..fail('乙')
      ..answer('丙');
    await until(() => !provider.isSearching);
    expect(provider.searchedSourceCount, 3);

    // 重試的乙卡住、不理會取消，這時改搜甲一個書源。
    loader.ignoresCancel.add('乙');
    unawaited(provider.retryFailedSources());
    await until(() => loader.sent.length == 4);
    final source = (await GetIt.instance<BookSourceDao>().getByUrl(
      'https://甲.example',
    ))!;
    unawaited(provider.searchInSource(source, 'other'));
    await until(() => loader.sent.length == 5);
    loader.fail('甲');
    await until(() => !provider.isSearching);
    expect(provider.failedSources, 1);
    expect(provider.searchedSourceCount, 1);
  });

  test('a search whose failed sources were all disabled since leaves nothing '
      'to retry', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.length == 3);
    provider.moveToBackground();
    loader
      ..answer('甲')
      ..fail('乙')
      ..answer('丙');
    await until(() => background.current!.isFinished);
    await disable('乙');

    await provider.retryFailedSources();
    expect(provider.sourceFailures, isEmpty);
    expect(loader.sent, hasLength(3));
    // 沒有書源可重試：背景那件不收掉。
    expect(background.current, isNotNull);
    provider.dispose();
  });

  test('a retry moved to the background keeps the failures of sources '
      'disabled since out of its results file', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.length == 3);
    loader
      ..answer('甲')
      ..fail('乙')
      ..fail('丙');
    await until(() => !provider.isSearching);
    await disable('乙');
    unawaited(provider.retryFailedSources());
    await until(() => loader.sent.length == 4);
    expect(loader.sent.last, '丙');
    provider.moveToBackground();
    provider.dispose();
    loader.answer('丙');
    await until(() => background.current!.isFinished);

    final restarted = searches();
    await restarted.restore();
    final reopened = await page(restarted, _Loader(), resume: true);
    addTearDown(reopened.dispose);
    await settle();
    expect(names(reopened), unorderedEquals(['甲書', '丙書']));
    expect(reopened.sourceFailures, isEmpty);
  });

  test('retrying skips failed sources disabled since', () async {
    final loader = _Loader();
    final provider = await page(searches(), loader);
    addTearDown(provider.dispose);
    unawaited(provider.search('night'));
    await until(() => loader.sent.length == 3);
    loader
      ..answer('甲')
      ..fail('乙')
      ..fail('丙');
    await until(() => !provider.isSearching);
    await disable('乙');
    loader.sent.clear();

    unawaited(provider.retryFailedSources());
    await until(() => loader.sent.isNotEmpty);
    await settle();
    expect(loader.sent, ['丙']);
  });

  group('a group with nothing left to search', () {
    Future<void> group(String name, String group) async {
      final dao = GetIt.instance<BookSourceDao>();
      final source = (await dao.getByUrl('https://$name.example'))!;
      await dao.upsert(source..bookSourceGroup = group);
    }

    test('searches everything and says so', () async {
      await group('甲', '甲組');
      final loader = _Loader();
      final provider = await page(searches(), loader);
      addTearDown(provider.dispose);
      await provider.updateSearchScope(SearchScope('甲組'));
      await disable('甲');

      unawaited(provider.search('night'));
      await until(() => loader.sent.length == 2);
      expect(loader.sent, ['乙', '丙']);
      expect(provider.searchScope.isAll, isTrue);

      // 頁首寫的是全部：分組又有書源了，下一次照樣搜全部（同 Legado 改掉範圍）。
      final dao = GetIt.instance<BookSourceDao>();
      await dao.upsert(
        (await dao.getByUrl('https://甲.example'))!..enabled = true,
      );
      loader.sent.clear();
      unawaited(provider.search('other'));
      await until(() => loader.sent.length == 3);
      expect(loader.sent, unorderedEquals(['甲', '乙', '丙']));
      expect(provider.searchScope.isAll, isTrue);
    });

    test('is dropped from the groups searched', () async {
      await group('甲', '甲組');
      await group('乙', '乙組');
      final loader = _Loader();
      final provider = await page(searches(), loader);
      addTearDown(provider.dispose);
      await provider.updateSearchScope(SearchScope('甲組,乙組'));
      await disable('甲');

      unawaited(provider.search('night'));
      await until(() => loader.sent.isNotEmpty);
      await settle();
      expect(loader.sent, ['乙']);
      expect(provider.searchScope.toString(), '乙組');
    });
  });

  test('a results file cut off mid-line is read back up to the last whole '
      'line and stays readable after resuming', () async {
    final background = searches();
    final loader = _Loader();
    final provider = await page(background, loader);
    unawaited(provider.search('night'));
    await until(() => loader.sent.isNotEmpty);
    loader.answer('甲');
    await settle();
    provider.moveToBackground();
    provider.pauseBackground();
    await until(() => background.current!.isPaused);
    provider.dispose();
    // 寫到一半被收掉：最後一行切在中文字中間。
    final file = dir.listSync().whereType<File>().single;
    final half = utf8.encode('{"url":"https://乙.example","name":"乙');
    file.writeAsBytesSync(
      half.sublist(0, half.length - 1),
      mode: FileMode.append,
    );

    final loader2 = _Loader();
    final restarted = searches(loader2);
    await restarted.restore();
    final reopened = await page(restarted, loader2, resume: true);
    expect(reopened.isBackgroundPaused, isTrue);
    expect(names(reopened), ['甲書']);
    await reopened.resumeBackground();
    await until(() => loader2.sent.length == 2);
    // 沒看到做完就離開：下次開 App 還要讀得回來。
    reopened.dispose();
    loader2
      ..answer('乙')
      ..answer('丙');
    await until(() => restarted.current!.isFinished);

    final again = searches();
    await again.restore();
    expect(again.current!.isFinished, isTrue);
    final last = await page(again, _Loader(), resume: true);
    addTearDown(last.dispose);
    expect(names(last), unorderedEquals(['甲書', '乙書', '丙書']));
  });
}
