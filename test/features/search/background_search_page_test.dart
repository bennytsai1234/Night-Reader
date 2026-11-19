import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/database/dao/search_keyword_dao.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/background_work/background_work.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/features/search/background_search.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/search/search_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OtherJob implements BackgroundJob {
  @override
  void pauseFromSystem() {}
  @override
  void endFromSystem() {}
  @override
  void openFromNotification() {}
}

void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() async {
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
    dir = Directory.systemTemp.createTempSync('background-search-page');
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // 還在寫的結果檔：留給系統清。
    }
  });

  PlainTextAction action(WidgetTester tester, String label) => tester
      .widget<PlainTextAction>(find.widgetWithText(PlainTextAction, label));

  testWidgets('the progress row moves a search to the background, then '
      'pauses it and offers to resume', (tester) async {
    await tester.runAsync(
      () => GetIt.instance<BookSourceDao>().upsert(
        BookSource(bookSourceUrl: 'https://s.example', bookSourceName: '書源'),
      ),
    );
    final sent = <String>[];
    Future<List<SearchBook>> loader(
      BookSource source,
      String key, {
      CancelToken? cancelToken,
    }) {
      sent.add(source.bookSourceName);
      final completer = Completer<List<SearchBook>>();
      cancelToken?.whenCancel.then(completer.completeError);
      return completer.future;
    }

    final work = BackgroundWork();
    final searches = BackgroundSearches(work: work, directory: () async => dir);
    late SearchProvider provider;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: ChangeNotifierProvider(
          create: (_) => provider = SearchProvider(
            entrance: Future<void>.value(),
            searchLoader: loader,
            backgroundSearches: searches,
          ),
          child: const SearchView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      unawaited(provider.search('夜讀'));
      for (var i = 0; i < 100 && sent.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('放到背景'), findsOneWidget);

    // 別的背景工作在跑時灰掉。
    final other = _OtherJob();
    work.begin(other, const BackgroundWorkStatus(title: '校驗書源', text: ''));
    await tester.pump();
    expect(action(tester, '放到背景').onPressed, isNull);
    work.end(other);
    await tester.pump();

    await tester.tap(find.text('放到背景'));
    await tester.pump();
    expect(find.text('放到背景'), findsNothing);
    expect(find.text('暫停'), findsOneWidget);

    await tester.tap(find.text('暫停'));
    // 停好要等結果檔寫完（真的寫檔）。
    for (var i = 0; i < 50 && find.text('已暫停 0/1').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('已暫停 0/1'), findsOneWidget);
    expect(action(tester, '繼續').onPressed, isNotNull);
    // 還沒搜完：頁首照樣是「結束」。
    expect(find.text('結束'), findsOneWidget);

    work.begin(other, const BackgroundWorkStatus(title: '校驗書源', text: ''));
    await tester.pump();
    expect(action(tester, '繼續').onPressed, isNull);
    work.end(other);

    await tester.tap(find.text('結束'));
    for (var i = 0; i < 50 && find.text('已暫停 0/1').evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('已暫停 0/1'), findsNothing);
  });
}
