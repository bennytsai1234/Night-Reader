import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/models/source/book_source.dart';
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

void main() {
  group('detectImportContentKind', () {
    test('源倉庫的漫畫書源是書源', () {
      expect(
        detectImportContentKind(_comicSource),
        ImportContentKind.bookSource,
      );
    });

    test('單一物件、帶 BOM 與前後空白的書源也是書源', () {
      expect(
        detectImportContentKind(
          '﻿ \n{"bookSourceUrl":"https://a.com","bookSourceName":"A"}\n',
        ),
        ImportContentKind.bookSource,
      );
    });

    test('訂閱源、替換規則、主題照 Legado 的欄位分辨', () {
      expect(detectImportContentKind(_rssSource), ImportContentKind.rssSource);
      expect(
        detectImportContentKind('[{"name":"去廣告","pattern":"廣告"}]'),
        ImportContentKind.replaceRule,
      );
      expect(
        detectImportContentKind('{"themeName":"夜","isNightTheme":true}'),
        ImportContentKind.theme,
      );
    });

    test('替換規則的 regex 別名也是替換規則', () {
      expect(
        detectImportContentKind('[{"name":"去廣告","regex":"廣告"}]'),
        ImportContentKind.replaceRule,
      );
    });

    test('陣列前面的空項目略過，看第一個認得的', () {
      const source = '{"bookSourceName":"A","bookSourceUrl":"https://a.com"}';
      expect(
        detectImportContentKind('[null,$source]'),
        ImportContentKind.bookSource,
      );
      expect(
        detectImportContentKind('[{},$source]'),
        ImportContentKind.bookSource,
      );
    });

    test('夜讀的書架匯出與書籍陣列是書架資料', () {
      expect(
        detectImportContentKind(
          '{"kind":"night_reader.bookshelf","version":1,"books":[]}',
        ),
        ImportContentKind.bookshelf,
      );
      expect(
        detectImportContentKind('[{"bookUrl":"https://a.com/1","name":"書"}]'),
        ImportContentKind.bookshelf,
      ); // Legado 匯出的書架：只有書名、作者、簡介。
      expect(
        detectImportContentKind('[{"name":"書","author":"某人","intro":""}]'),
        ImportContentKind.bookshelf,
      );
    });

    test('網頁、空內容、認不出的 JSON 回 null', () {
      expect(detectImportContentKind('<!DOCTYPE html><html></html>'), isNull);
      expect(detectImportContentKind(''), isNull);
      expect(detectImportContentKind('[]'), isNull);
      expect(detectImportContentKind('[1,2]'), isNull);
      expect(detectImportContentKind('{"foo":1}'), isNull);
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

    testWidgets('加入書架的連結跳出匯入書架的確認框', (tester) async {
      final context = await pumpHost(tester);
      service.handleUri(
        context,
        Uri.parse(
          'legado://import/addToBookshelf?src='
          'https%3A%2F%2Fexample.com%2Fbooks.json',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('外部匯入'), findsOneWidget);
      expect(find.text('匯入書架'), findsOneWidget);
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
