import 'dart:convert';
import 'dart:io' as io;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/cookie_store.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/features/source_manager/views/source_edit_basic.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 改網址時書、搜尋結果、正文與快取都跟著搬，整個資料庫都要在。
    registerDatabase(db);
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    dao = GetIt.instance<BookSourceDao>();
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  BookSource sampleSource({String url = 'https://a.example'}) => BookSource(
    bookSourceUrl: url,
    bookSourceName: '甲書源',
    ruleToc: TocRule(chapterList: '.list li', formatJs: 'formatJs()'),
    ruleContent: ContentRule(content: '#content', webJs: 'webJs()'),
  );

  /// 從一個起始頁推入編輯器，才能檢查返回行為。
  Future<void> pumpEditor(
    WidgetTester tester,
    BookSource? source, {
    ValueChanged<String>? onSaved,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SourceEditorPage(source: source, onSaved: onSaved),
                ),
              ),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();
  }

  Finder field(int index) => find.byType(TextField).at(index);

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
  }

  /// 等非同步的存檔、開啟頁面做完：資料庫與剪貼簿要真的時間，畫面照假時間推。
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 80 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  /// 按「更多」裡的 [label]，等動作做完。
  Future<void> choose(WidgetTester tester, String label) async {
    await openMenu(tester);
    await tester.tap(find.text(label));
    await tester.pump();
  }

  /// 按儲存，等存檔做完：存好會關掉編輯頁，失敗會留在編輯頁並跳出提示。
  Future<void> save(WidgetTester tester) async {
    await choose(tester, '儲存');
    await waitFor(
      tester,
      () =>
          find.byType(SourceEditorPage).evaluate().isEmpty ||
          find.byType(SnackBar).evaluate().isNotEmpty,
    );
  }

  // 同 Legado：從書源編輯進除錯時先問關鍵字，預先填書源的校驗關鍵字。
  testWidgets('debugging from the editor asks for the keyword first', (
    tester,
  ) async {
    final source = sampleSource()..ruleSearch = SearchRule(checkKeyWord: '斗羅');
    await tester.runAsync(() => dao.upsert(source));
    await pumpEditor(tester, source);

    await tester.dragUntilVisible(
      find.text('除錯書源'),
      find.byType(SourceEditBasic),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('除錯書源'));
    await tester.pumpAndSettle();

    expect(find.text('輸入除錯關鍵字'), findsOneWidget);
    expect(find.widgetWithText(TextField, '斗羅'), findsOneWidget);
  });

  testWidgets('saving keeps rules the editor does not show', (tester) async {
    await tester.runAsync(() => dao.upsert(sampleSource()));
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    await pumpEditor(tester, stored);

    await tester.enterText(field(0), '乙書源');
    await save(tester);

    final saved = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    expect(saved!.bookSourceName, '乙書源');
    expect(saved.ruleToc?.chapterList, '.list li');
    expect(saved.ruleToc?.formatJs, 'formatJs()');
    expect(saved.ruleContent?.webJs, 'webJs()');
  });

  // 匯入另一台時靠更新時間認出新的一版（同 Legado 的編輯器）。
  testWidgets('saving an edit records when it was changed; saving without '
      'one keeps the time', (tester) async {
    await tester.runAsync(
      () => dao.upsert(sampleSource()..lastUpdateTime = 1000),
    );
    Future<BookSource> stored() async => (await tester.runAsync<BookSource?>(
      () => dao.getByUrl('https://a.example'),
    ))!;

    await pumpEditor(tester, await stored());
    await save(tester);
    expect((await stored()).lastUpdateTime, 1000);

    await pumpEditor(tester, await stored());
    await tester.enterText(field(0), '乙書源');
    await save(tester);
    expect((await stored()).lastUpdateTime, greaterThan(1000));
  });

  testWidgets('changing the url moves the source instead of copying it', (
    tester,
  ) async {
    await tester.runAsync(() => dao.upsert(sampleSource()));
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    await pumpEditor(tester, stored);

    await tester.enterText(field(1), 'https://a.example.net');
    await save(tester);

    final all = await tester.runAsync(() => dao.getAll());
    expect(all!.map((s) => s.bookSourceUrl), ['https://a.example.net']);
    expect(all.single.ruleContent?.webJs, 'webJs()');
  });

  testWidgets('a url used by another source asks before overwriting', (
    tester,
  ) async {
    await tester.runAsync(() => dao.upsert(sampleSource()));
    await pumpEditor(tester, null);

    await tester.enterText(field(0), '新書源');
    await tester.enterText(field(1), 'https://a.example');
    await save(tester);

    expect(find.text('覆蓋「甲書源」？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final kept = await tester.runAsync(() => dao.getByUrl('https://a.example'));
    expect(kept!.bookSourceName, '甲書源');
    expect(find.byType(SourceEditorPage), findsOneWidget);
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    await pumpEditor(tester, sampleSource());

    // 沒有修改時直接離開。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SourceEditorPage), findsNothing);

    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();
    await tester.enterText(field(0), '改過的名稱');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放棄這次的修改？'), findsOneWidget);

    await tester.tap(find.text('放棄'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceEditorPage), findsNothing);
  });

  testWidgets('the header menu holds save and the source actions', (
    tester,
  ) async {
    await pumpEditor(tester, sampleSource());
    await openMenu(tester);

    for (final label in ['儲存', '登入', '在此書源中搜尋', '清除 Cookie', '複製書源', '貼上書源']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // 沒有登入網址的書源，登入灰掉、留在原位（ADR 0059）。
    final login = tester.widget<InkWell>(
      find.ancestor(of: find.text('登入'), matching: find.byType(InkWell)),
    );
    expect(login.onTap, isNull);
  });

  testWidgets('登入 saves the edit first and opens the login page', (
    tester,
  ) async {
    final loginSource = BookSource(
      bookSourceUrl: 'https://login.example',
      bookSourceName: '要登入的書源',
      loginUrl: '@js: function login() {}',
      loginUi: '[{name: "帳號", type: "text"}]',
    );
    await tester.runAsync(() => dao.upsert(loginSource));
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://login.example'),
    );
    var savedCalls = 0;
    await pumpEditor(tester, stored, onSaved: (_) => savedCalls++);

    await tester.enterText(field(0), '改過的書源');
    await choose(tester, '登入');
    await waitFor(
      tester,
      () => find.byType(SourceLoginPage).evaluate().isNotEmpty,
    );

    expect(find.byType(SourceLoginPage), findsOneWidget);
    expect(find.text('登入 · 改過的書源'), findsOneWidget);
    expect(savedCalls, 1);
    final saved = await tester.runAsync(
      () => dao.getByUrl('https://login.example'),
    );
    expect(saved!.bookSourceName, '改過的書源');

    // 登入前先存好了，關掉登入頁再離開編輯頁不會問要不要放棄。
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放棄這次的修改？'), findsNothing);
    expect(find.byType(SourceEditorPage), findsNothing);
  });

  testWidgets('在此書源中搜尋 saves first and opens the search page', (tester) async {
    final searchSource = BookSource(
      bookSourceUrl: 'https://search.example',
      bookSourceName: '要搜尋的書源',
      searchUrl: '/s?q={{key}}',
      ruleSearch: SearchRule(bookList: '.book', name: '.name'),
    );
    await tester.runAsync(() => dao.upsert(searchSource));
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://search.example'),
    );
    await pumpEditor(tester, stored);

    await tester.enterText(field(0), '改過的書源');
    await choose(tester, '在此書源中搜尋');
    await waitFor(tester, () => find.byType(SearchPage).evaluate().isNotEmpty);

    expect(find.byType(SearchPage), findsOneWidget);
    final saved = await tester.runAsync(
      () => dao.getByUrl('https://search.example'),
    );
    expect(saved!.bookSourceName, '改過的書源');
  });

  testWidgets('清除 Cookie only clears the cookies and keeps the login data', (
    tester,
  ) async {
    final cookieSource = BookSource(
      bookSourceUrl: 'https://cookie.example',
      bookSourceName: '沒有登入網址的書源',
    );
    await tester.runAsync(() async {
      await NetworkService().init(ephemeral: true);
      await dao.upsert(cookieSource);
      await cookieSource.putLoginInfo('{"帳號":"留著"}');
      await cookieSource.putLoginHeader('{"Authorization":"Bearer keep"}');
      await CookieStore().setCookie(cookieSource.bookSourceUrl, 'sid=clear');
      await NetworkService().cookieJar.saveFromResponse(
        Uri.parse(cookieSource.bookSourceUrl),
        [io.Cookie('sid', 'clear')],
      );
    });
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://cookie.example'),
    );
    await pumpEditor(tester, stored);

    await choose(tester, '清除 Cookie');
    await waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);

    expect(
      await tester.runAsync(
        () => CookieStore().getCookie(cookieSource.bookSourceUrl),
      ),
      isEmpty,
    );
    expect(
      await tester.runAsync(
        () => NetworkService().cookieJar.loadForRequest(
          Uri.parse(cookieSource.bookSourceUrl),
        ),
      ),
      isEmpty,
    );
    expect(
      await tester.runAsync(() => cookieSource.getLoginInfo()),
      '{"帳號":"留著"}',
    );
    expect(
      await tester.runAsync(() => cookieSource.getLoginHeader()),
      '{"Authorization":"Bearer keep"}',
    );
  });

  testWidgets('複製書源 copies the edited content as JSON', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.runAsync(() => dao.upsert(sampleSource()));
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    await pumpEditor(tester, stored);

    await tester.enterText(field(0), '複製的名字');
    await choose(tester, '複製書源');
    await waitFor(tester, () => copied != null);

    expect(jsonDecode(copied!), containsPair('bookSourceName', '複製的名字'));
  });

  testWidgets('貼上書源 fills the form without saving', (tester) async {
    final pasted = sampleSource()..bookSourceName = '貼上的書源';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': jsonEncode(pasted.toJson())};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.runAsync(() => dao.upsert(sampleSource()));
    final stored = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    await pumpEditor(tester, stored);

    await choose(tester, '貼上書源');
    await waitFor(
      tester,
      () => tester.widget<TextField>(field(0)).controller!.text == '貼上的書源',
    );

    expect(tester.widget<TextField>(field(0)).controller!.text, '貼上的書源');
    // 只是填進表單，還沒存；離開會問要不要放棄。
    final stillStored = await tester.runAsync(
      () => dao.getByUrl('https://a.example'),
    );
    expect(stillStored!.bookSourceName, '甲書源');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放棄這次的修改？'), findsOneWidget);
  });
}
