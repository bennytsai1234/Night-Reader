import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_link_service.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/features/association/association_handler_service.dart';
import 'package:night_reader/features/association/import_content.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

// 源倉庫（yckceo.com）各個「3.x一键导入」按鈕給的連結與內容格式（2026-11-10）：
//   書源        yuedu://booksource/importonline?src=…/shuyuan/json/id/<id>.json
//   書源合集    yuedu://booksource/importonline?src=…/shuyuans/json/id/<id>.json（302 到 jsDelivr）
//   訂閱源      legado://import/auto?src=…/rss/json/id/<id>.json
//   訂閱源合集  legado://import/rssSource?src=…/rsss/json/id/<id>.json（302 到 jsDelivr）
const _comicSource =
    '[{"bookSourceGroup":"漫画书源","bookSourceName":"🌟卡拉漫画",'
    '"bookSourceType":2,"bookSourceUrl":"https:\\/\\/www.kalamanhua.com",'
    '"enabled":true,"lastUpdateTime":"1792825494301"}]';
const _rssSource =
    '[{"sourceName":"某訂閱","sourceUrl":"https://example.com",'
    '"enabled":true,"singleUrl":true}]';
const _bookSourceLink =
    'yuedu://booksource/importonline?src='
    'https://www.yckceo.com/yuedu/shuyuan/json/id/7720.json';

/// 書的詳情：書名「夜航」；抓完時 [fetched] 完成。網址有 `/hang/` 的開始抓就
/// 完成 [started]，一直等到被取消，[cancelled] 記下有沒有被取消；有 `/gated/`
/// 的等 [gate] 完成才抓完。
class _Details extends BookSourceService {
  Completer<void> fetched = Completer<void>();
  Completer<void> started = Completer<void>();
  Completer<void> gate = Completer<void>();
  bool cancelled = false;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async {
    if (book.bookUrl.contains('/hang/')) {
      if (!started.isCompleted) started.complete();
      await cancelToken!.whenCancel;
      cancelled = true;
      throw cancelToken.cancelError!;
    }
    if (book.bookUrl.contains('/gated/')) await gate.future;
    if (!fetched.isCompleted) fetched.complete();
    return book.copyWith(name: '夜航', author: '某人');
  }
}

void main() {
  group('detectImportContent', () {
    Future<ImportContentKind?> kindOf(String text) async =>
        (await detectImportContent(text))?.kind;

    test('源倉庫的漫畫書源是書源', () async {
      expect(await kindOf(_comicSource), ImportContentKind.bookSource);
    });

    test('單一物件、帶 BOM 與前後空白的書源也是書源', () async {
      expect(
        await kindOf(
          '﻿ \n{"bookSourceUrl":"https://a.com","bookSourceName":"A"}\n',
        ),
        ImportContentKind.bookSource,
      );
    });

    test('訂閱源、替換規則、主題照 Legado 的欄位分辨', () async {
      expect(await kindOf(_rssSource), ImportContentKind.rssSource);
      expect(
        await kindOf('[{"name":"去廣告","pattern":"廣告"}]'),
        ImportContentKind.replaceRule,
      );
      expect(
        await kindOf('{"themeName":"夜","isNightTheme":true}'),
        ImportContentKind.theme,
      );
    });

    test('替換規則的 regex 別名也是替換規則', () async {
      expect(
        await kindOf('[{"name":"去廣告","regex":"廣告"}]'),
        ImportContentKind.replaceRule,
      );
    });

    test('陣列前面的空項目略過，看第一個認得的', () async {
      const source = '{"bookSourceName":"A","bookSourceUrl":"https://a.com"}';
      expect(await kindOf('[null,$source]'), ImportContentKind.bookSource);
      expect(await kindOf('[{},$source]'), ImportContentKind.bookSource);
    });

    test('夜讀的書架匯出與 Legado 的書架是書架資料，交給書架匯入不用再解析', () async {
      expect(
        await kindOf(
          '{"kind":"night_reader.bookshelf","version":1,"books":[]}',
        ),
        ImportContentKind.bookshelf,
      );
      expect(
        await kindOf('[{"bookUrl":"https://a.com/1","name":"書","author":""}]'),
        ImportContentKind.bookshelf,
      );
      // Legado 匯出的書架：只有書名、作者、簡介。
      final legado = await detectImportContent(
        '[{"name":"書","author":"某人","intro":""}]',
      );
      expect(legado?.kind, ImportContentKind.bookshelf);
      expect(legado?.bookshelf?.legado, [(name: '書', author: '某人')]);
    });

    test('和書架匯入同一個判斷：缺作者、夾了別的東西的不是書架', () async {
      expect(
        await kindOf('[{"bookUrl":"https://a.com/1","name":"書"}]'),
        isNull,
      );
      expect(await kindOf('[{"name":"書","intro":""}]'), isNull);
      expect(await kindOf('[{"name":"書","author":"某人"},{"foo":1}]'), isNull);
    });

    test('網頁、空內容、認不出的 JSON 回 null', () async {
      expect(await kindOf('<!DOCTYPE html><html></html>'), isNull);
      expect(await kindOf(''), isNull);
      expect(await kindOf('[]'), isNull);
      expect(await kindOf('[1,2]'), isNull);
      expect(await kindOf('{"foo":1}'), isNull);
    });
  });

  group('外部匯入', () {
    final theme = buildAppTheme(AppStyle.paper, Brightness.light);
    final service = AssociationHandlerService();

    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return context;
    }

    testWidgets('點一次匯入連結只跳一個對話框（連結與分享兩條都收到時）', (tester) async {
      final context = await pumpHost(tester);
      final link = Uri.parse(_bookSourceLink);

      // Android 上同一個 ACTION_VIEW 會同時送到 app_links 與分享套件；分享套件
      // 把它回報成一筆 url。分享那條若把網址當檔案讀，讀檔要真的非同步才會
      // 失敗回來，所以放在 runAsync 裡。
      service.handleUri(context, link);
      await tester.runAsync(
        () => service.handleSharedMedia(context, [
          SharedMediaFile(path: _bookSourceLink, type: SharedMediaType.url),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('外部匯入'), findsOneWidget);
      expect(find.textContaining('辨識為書源資料'), findsOneWidget);
      expect(find.text('匯入書源'), findsOneWidget);
      expect(find.text('無法辨識'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('帶 text/plain 類型的匯入連結也只跳一個對話框', (tester) async {
      final context = await pumpHost(tester);
      // 指定夜讀、帶 MIME 的 ACTION_VIEW：分享套件把它當成文字分享，path 是
      // 連結的路徑部分。
      service.handleUri(context, Uri.parse(_bookSourceLink));
      await tester.runAsync(
        () => service.handleSharedMedia(context, [
          SharedMediaFile(
            path: '/importonline',
            type: SharedMediaType.text,
            mimeType: 'text/plain',
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('外部匯入'), findsOneWidget);
      expect(find.text('無法辨識'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    group('加入書架的連結（src 是一本書的網址）', () {
      late AppDatabase db;
      final details = _Details();
      final opened = <Book>[];

      setUp(() async {
        opened.clear();
        details
          ..cancelled = false
          ..started = Completer<void>()
          ..gate = Completer<void>();
        service.openBookDetail = (_, book) async => opened.add(book);
        db = AppDatabase.forTesting(NativeDatabase.memory());
        await BookSourceDao(db).upsert(
          BookSource(bookSourceUrl: 'https://a.example', bookSourceName: '甲站'),
        );
        service.bookLinks = () => BookLinkService(
          sourceDao: BookSourceDao(db),
          bookDao: BookDao(db),
          service: details,
        );
      });

      tearDown(() async {
        service.bookLinks = BookLinkService.new;
        service.openBookDetail = openBookDetailPage;
        await db.close();
      });

      Uri link(String url) => Uri.parse(
        'legado://import/addToBookshelf?src=${Uri.encodeComponent(url)}',
      );

      testWidgets('抓到詳情後直接開這本書的書籍詳情（同 Legado），不跳確認框', (tester) async {
        final context = await pumpHost(tester);
        service.handleUri(context, link('https://a.example/book/1'));
        await tester.runAsync(() => details.fetched.future);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(find.text('外部匯入'), findsNothing);
        expect(opened.map((book) => (book.name, book.origin)), [
          ('夜航', 'https://a.example'),
        ]);
        expect(
          await tester.runAsync(() => BookDao(db).getInBookshelf()),
          isEmpty,
          reason: '加不加入書架由讀者在書籍詳情決定',
        );
      });

      testWidgets('書架上已經有這本：只提示已在書架，不開詳情', (tester) async {
        await tester.runAsync(
          () => BookDao(db).upsert(
            Book(
              bookUrl: 'https://a.example/book/2',
              origin: 'https://a.example',
              name: '書架上的',
              isInBookshelf: true,
            ),
          ),
        );
        final context = await pumpHost(tester);
        service.handleUri(context, link('https://a.example/book/2'));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(opened, isEmpty);
        expect(find.text('《書架上的》已在書架'), findsOneWidget);
      });

      testWidgets('找書時開點外面關不掉的進度框，按取消停掉請求、不開詳情', (tester) async {
        final context = await pumpHost(tester);
        service.handleUri(context, link('https://a.example/hang/3'));
        await tester.runAsync(() => details.started.future);
        // 進度條一直在跑，等不到畫面靜止。
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('取消'), findsOneWidget);
        await tester.tapAt(const Offset(4, 4));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('取消'), findsOneWidget, reason: '點外面關不掉');

        await tester.tap(find.text('取消'));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(details.cancelled, isTrue);
        expect(find.text('取消'), findsNothing);
        expect(opened, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('按返回鍵收掉進度框也停掉請求', (tester) async {
        final context = await pumpHost(tester);
        service.handleUri(context, link('https://a.example/hang/5'));
        await tester.runAsync(() => details.started.future);
        await tester.pump(const Duration(milliseconds: 500));

        await tester.binding.handlePopRoute();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(details.cancelled, isTrue);
        expect(find.text('取消'), findsNothing);
        expect(opened, isEmpty);
      });

      testWidgets('又點了一條連結時，先找到的只收掉自己的進度框', (tester) async {
        final context = await pumpHost(tester);
        service.handleUri(context, link('https://a.example/gated/6'));
        await tester.pump(const Duration(milliseconds: 500));
        service.handleUri(context, link('https://a.example/hang/7'));
        await tester.runAsync(() => details.started.future);
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('取消'), findsNWidgets(2));

        details.gate.complete();
        await tester.runAsync(() => details.fetched.future);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(milliseconds: 500));

        expect(opened.map((book) => book.bookUrl), [
          'https://a.example/gated/6',
        ]);
        expect(find.text('取消'), findsOneWidget, reason: '第二條還在找');
        expect(details.cancelled, isFalse);
      });

      testWidgets('進度框被收掉（離開）時也停掉請求', (tester) async {
        final context = await pumpHost(tester);
        service.handleUri(context, link('https://a.example/hang/4'));
        await tester.runAsync(() => details.started.future);
        // 進度條一直在跑，等不到畫面靜止。
        await tester.pump(const Duration(milliseconds: 500));

        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();

        expect(details.cancelled, isTrue);
        expect(opened, isEmpty);
      });

      testWidgets('找不到書源時說原因，不跳確認框', (tester) async {
        final context = await pumpHost(tester);
        service.handleUri(context, link('https://b.example/book/1'));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();

        expect(find.text('外部匯入'), findsNothing);
        expect(find.text('加入書架失敗：找不到符合這個網址的書源'), findsOneWidget);
      });
    });

    testWidgets('沒帶 src 的連結不理（同 Legado）', (tester) async {
      final context = await pumpHost(tester);
      service.handleUri(
        context,
        Uri.parse(
          'legado://addBook?url=https%3A%2F%2Fexample.com%2Fbooks.json',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('外部匯入'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('訂閱源連結只告知不支援，沒有匯入按鈕', (tester) async {
      final context = await pumpHost(tester);
      service.handleUri(
        context,
        Uri.parse(
          'legado://import/rssSource?src='
          'https://www.yckceo.com/yuedu/rsss/json/id/205.json',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('這是訂閱源'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('匯入書源'), findsNothing);
    });

    testWidgets('分享的書源檔與分享的書源文字，照同一套內容判斷', (tester) async {
      final context = await pumpHost(tester);
      final dir = Directory.systemTemp.createTempSync('nr_external_import');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/7720.json')
        ..writeAsStringSync(_comicSource);

      await tester.runAsync(
        () => service.handleSharedMedia(context, [
          SharedMediaFile(
            path: file.path,
            type: SharedMediaType.file,
            mimeType: 'application/json',
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('7720.json'), findsOneWidget);
      expect(find.textContaining('辨識為書源資料'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.runAsync(
        () => service.handleSharedMedia(context, [
          SharedMediaFile(path: _comicSource, type: SharedMediaType.text),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('分享的文字'), findsOneWidget);
      expect(find.textContaining('辨識為書源資料'), findsOneWidget);
    });

    testWidgets('分享的書源先開匯入預覽：這台的比檔案新時預設不覆蓋', (tester) async {
      await GetIt.instance.reset();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      registerDatabase(db);
      addTearDown(() async {
        await db.close();
        await GetIt.instance.reset();
      });
      // 這台改過的那一版，比分享的檔案新。
      await tester.runAsync(
        () => GetIt.instance<BookSourceDao>().upsert(
          BookSource(
            bookSourceUrl: 'https://www.kalamanhua.com',
            bookSourceName: '改過的',
            bookSourceType: 2,
            lastUpdateTime: 1792825494301 + 1000,
          ),
        ),
      );
      final context = await pumpHost(tester);

      await tester.runAsync(
        () => service.handleSharedMedia(context, [
          SharedMediaFile(path: _comicSource, type: SharedMediaType.text),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('匯入書源'));
      final older = find.text('換成檔案裡較舊的 1 個');
      for (var i = 0; i < 40 && older.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(older, findsOneWidget);
      expect(find.text('匯入'), findsOneWidget);
    });

    testWidgets('分享的替換規則先開匯入預覽：這台已有的預設不勾，不被蓋掉', (tester) async {
      await GetIt.instance.reset();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      registerDatabase(db);
      addTearDown(() async {
        await db.close();
        await GetIt.instance.reset();
      });
      final dao = GetIt.instance<ReplaceRuleDao>();
      await tester.runAsync(
        () => dao.upsert(
          ReplaceRule(id: 1700000000005, name: '這台改過的', pattern: '甲'),
        ),
      );
      final context = await pumpHost(tester);
      // Legado 匯出的樣子：開關是 true／false。
      const shared =
          '[{"id":1700000000005,"name":"檔案裡的","pattern":"甲甲","isEnabled":true,'
          '"isRegex":false,"scopeTitle":false,"scopeContent":true},'
          '{"id":1700000000006,"name":"新規則","pattern":"乙","isEnabled":true,'
          '"isRegex":false,"scopeTitle":false,"scopeContent":true}]';

      await tester.runAsync(
        () => service.handleSharedMedia(context, [
          SharedMediaFile(path: shared, type: SharedMediaType.text),
        ]),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('匯入替換規則'));
      final sheet = find.text('匯入 2 個替換規則');
      for (var i = 0; i < 40 && sheet.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);

      await tester.tap(find.text('匯入 1 個'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final rules = (await tester.runAsync(dao.getAll))!;
      expect(
        {for (final r in rules) r.id: r.name},
        {1700000000005: '這台改過的', 1700000000006: '新規則'},
      );
      expect(find.text('成功匯入 1 個替換規則'), findsOneWidget);
    });

    testWidgets('認不出的分享檔案說明不是夜讀能匯入的格式', (tester) async {
      final context = await pumpHost(tester);
      final dir = Directory.systemTemp.createTempSync('nr_external_import');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/notes.json')
        ..writeAsStringSync('{"foo":1}');

      await tester.runAsync(
        () => service.handleSharedMedia(context, [
          SharedMediaFile(path: file.path, type: SharedMediaType.file),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('無法辨識'), findsOneWidget);
      // 提示框的說明照子句換行（ClauseText），比對內容時不看換行。
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data?.replaceAll('\n', '') == '「notes.json」不是夜讀能匯入的格式。',
        ),
        findsOneWidget,
      );
    });
  });
}
