import 'dart:io' as io;
import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/cookie_store.dart';
import 'package:night_reader/features/source_login/source_browser_page.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import '../../support/fake_webview.dart';
import '../../test_helper.dart';

void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registerDatabase(db);
    dao = getIt<BookSourceDao>();
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  const url = 'https://login.example';
  final source = BookSource(
    bookSourceUrl: url,
    bookSourceName: '要登入的書源',
    bookSourceGroup: '小說,$loginRequiredSourceGroupTag',
    loginUrl: '@js: function login() {}',
    loginUi: '''[
      {name: "帳號", type: "text"},
      {name: "切換線路", type: "button", action: "line()",
        style: {layout_flexGrow: 1, layout_flexBasisPercent: 1}},
    ]''',
  );

  /// 從起始頁開登入，傳回 [openSourceLogin] 的結果（關掉、存好之後才有）。
  Future<Future<bool>> openLogin(
    WidgetTester tester, {
    BookSource? login,
    VoidCallback? onLoggedIn,
  }) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: BackdropGroup(
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => result = openSourceLogin(
                  context,
                  login ?? source,
                  onLoggedIn: onLoggedIn,
                ),
                child: const Text('開啟'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    // 開頁前先讀已存的表單內容（資料庫）。
    for (var i = 0; i < 20 && find.text('帳號').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return result;
  }

  /// 等 [openSourceLogin] 存好、比完傳回。存檔與比對在測試的假時間裡排，
  /// 資料庫要真的時間，所以兩邊輪流推進。
  Future<bool> settle(WidgetTester tester, Future<bool> result) async {
    bool? changed;
    unawaited(result.then((value) => changed = value));
    for (var i = 0; i < 100 && changed == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    return changed!;
  }

  /// 關掉登入頁，等 [openSourceLogin] 傳回。
  Future<bool> close(WidgetTester tester, Future<bool> result) async {
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    return settle(tester, result);
  }

  testWidgets('shows the saved form, saves edits on leaving and clears the '
      'login-required mark', (tester) async {
    setupTestDI();
    await tester.runAsync(() async {
      await dao.upsert(source);
      await source.putLoginInfo('{"帳號":"舊帳號","token":"keep"}');
    });

    final closed = await openLogin(tester);

    expect(find.text('登入 · 要登入的書源'), findsOneWidget);
    expect(find.text('切換線路'), findsOneWidget);
    expect(find.widgetWithText(TextField, '舊帳號'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '新帳號');

    expect(await close(tester, closed), isTrue);
    final saved = await tester.runAsync(() => source.getLoginInfo());
    expect(jsonDecode(saved!), {'帳號': '新帳號', 'token': 'keep'});
    final stored = await tester.runAsync(() => dao.getByUrl(url));
    expect(stored!.groupTags, isNot(contains(loginRequiredSourceGroupTag)));
    expect(stored.groupTags, contains('小說'));
  });

  testWidgets('leaving without edits changes nothing', (tester) async {
    setupTestDI();
    await tester.runAsync(() => dao.upsert(source));

    final closed = await openLogin(tester);

    expect(await close(tester, closed), isFalse);
    final stored = await tester.runAsync(() => dao.getByUrl(url));
    expect(stored!.groupTags, contains(loginRequiredSourceGroupTag));
  });

  group('a cookie the website set in the cookie jar', () {
    Future<void> useCookieJar(WidgetTester tester) async {
      await tester.runAsync(() => NetworkService().init(ephemeral: true));
      addTearDown(
        () => tester.runAsync(
          () => NetworkService().cookieJar.delete(Uri.parse(url), true),
        ),
      );
    }

    // 網頁登入時網站的回應設了工作階段 Cookie（存在 Cookie 檔，不在表單、
    // 登入標頭與夜讀自己存的 Cookie 裡）：照樣算登入資料變了，讓呼叫端
    // 重抓。登入網頁在子路徑，回應沒寫 Path 的 Cookie 只屬於那一層。
    testWidgets('counts as changed after logging in on the website', (
      tester,
    ) async {
      setupTestDI();
      final webView = FakeWebViewPlatform();
      final previousPlatform = WebViewPlatform.instance;
      WebViewPlatform.instance = webView;
      addTearDown(() {
        if (previousPlatform != null) {
          WebViewPlatform.instance = previousPlatform;
        }
      });
      final web = BookSource(
        bookSourceUrl: url,
        bookSourceName: '網頁登入的書源',
        loginUrl: '/account/login',
      );
      await useCookieJar(tester);
      await tester.runAsync(() => dao.upsert(web));

      late Future<bool> result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: BackdropGroup(
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => result = openSourceLogin(context, web),
                  child: const Text('開啟'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開啟'));
      for (
        var i = 0;
        i < 20 && find.byType(SourceBrowserPage).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(SourceBrowserPage), findsOneWidget);

      await tester.runAsync(
        () => NetworkService().cookieJar.saveFromResponse(
          Uri.parse('$url/account/login'),
          [io.Cookie('sid', 'fresh-session')],
        ),
      );

      expect(await close(tester, result), isTrue);
    });

    // 表單頁開著時網站的回應也會換 Cookie（例如按了表單上的其他按鈕）；
    // 沒按登入就不算。
    testWidgets('does not count when leaving the form without logging in', (
      tester,
    ) async {
      setupTestDI();
      await useCookieJar(tester);
      await tester.runAsync(() => dao.upsert(source));

      final closed = await openLogin(tester);
      await tester.runAsync(
        () => NetworkService().cookieJar.saveFromResponse(Uri.parse(url), [
          io.Cookie('sid', 'other-session'),
        ]),
      );

      expect(await close(tester, closed), isFalse);
    });
  });

  group('tells the caller it logged in', () {
    testWidgets('when the login data changed', (tester) async {
      setupTestDI();
      await tester.runAsync(() => dao.upsert(source));
      var loggedIn = 0;

      // 前面的測試存的帳號會留在 App 共用的快取裡，每個測試填不同的。
      final closed = await openLogin(tester, onLoggedIn: () => loggedIn++);
      await tester.enterText(find.byType(TextField), '要校驗的帳號');

      expect(await close(tester, closed), isTrue);
      expect(loggedIn, 1);
    });

    testWidgets('not when leaving without logging in', (tester) async {
      setupTestDI();
      await tester.runAsync(() => dao.upsert(source));
      var loggedIn = 0;

      final closed = await openLogin(tester, onLoggedIn: () => loggedIn++);

      expect(await close(tester, closed), isFalse);
      expect(loggedIn, 0);
    });
  });

  group('log in on the website', () {
    // 頁首右邊只有打勾，「在網站登入」在表單最下面的卡片
    // （docs/design/components.md「左右各一顆」）。
    Future<void> showActions(WidgetTester tester) async {
      await tester.ensureVisible(find.text('在網站登入'));
      await tester.pumpAndSettle();
    }

    testWidgets('replaces the form, so going back lands where login was '
        'opened', (tester) async {
      setupTestDI();
      final webView = FakeWebViewPlatform();
      final previousPlatform = WebViewPlatform.instance;
      WebViewPlatform.instance = webView;
      addTearDown(() {
        if (previousPlatform != null) {
          WebViewPlatform.instance = previousPlatform;
        }
      });
      await tester.runAsync(() => dao.upsert(source));
      var loggedIn = 0;

      final result = await openLogin(tester, onLoggedIn: () => loggedIn++);
      await tester.enterText(find.byType(TextField), '網站登入前填的帳號');
      await showActions(tester);
      await tester.tap(find.text('在網站登入'));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBrowserPage), findsOneWidget);
      expect(find.byType(SourceLoginPage), findsNothing);
      expect(webView.loaded, [Uri.parse(url)]);

      // 離開前先存 Cookie（真的非同步），存完才開始返回。
      await tester.tap(find.byTooltip('返回'));
      for (var i = 0; i < 50 && find.text('開啟').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 返回途中露出的是打開登入的地方，不是表單。
      expect(find.byType(SourceBrowserPage), findsOneWidget);
      expect(find.text('開啟'), findsOneWidget);
      expect(find.byType(SourceLoginPage), findsNothing);

      expect(await settle(tester, result), isTrue);
      expect(loggedIn, 1);
      expect(find.byType(SourceBrowserPage), findsNothing);
      // 換成瀏覽器時表單頁照樣把填的內容存好。
      final saved = await tester.runAsync(() => source.getLoginInfoMap());
      expect(saved?['帳號'], '網站登入前填的帳號');
    });

    testWidgets('stays under a form that cannot be read', (tester) async {
      setupTestDI();
      final broken = BookSource.fromJson({
        ...source.toJson(),
        'loginUi': '[{name: "帳號", type: ',
      });
      await tester.runAsync(() => dao.upsert(broken));

      await openLogin(tester, login: broken);

      expect(find.text('登入表單讀不出來'), findsOneWidget);
      // 表單壞了還能改在網站登入、看標頭、清掉舊資料。
      for (final title in ['在網站登入', '登入標頭', '清除登入資料']) {
        final row = tester.widget<GroupedRow>(
          find.widgetWithText(GroupedRow, title),
        );
        expect(row.enabled, isTrue, reason: title);
      }
    });

    testWidgets('is greyed out when the source URL is a name', (tester) async {
      setupTestDI();
      final named = BookSource.fromJson({
        ...source.toJson(),
        'bookSourceUrl': '聚合書源',
      });
      await tester.runAsync(() => dao.upsert(named));

      await openLogin(tester, login: named);
      await showActions(tester);

      expect(find.text('登入標頭'), findsOneWidget);
      // 一律畫出、灰掉（ADR 0059）。
      final row = tester.widget<GroupedRow>(
        find.widgetWithText(GroupedRow, '在網站登入'),
      );
      expect(row.enabled, isFalse);
    });

    testWidgets('刪除登入標頭只刪標頭，表單內容與 Cookie 留著', (tester) async {
      setupTestDI();
      await tester.runAsync(() async {
        await dao.upsert(source);
        // 前面的測試留下的，先換成本次要看的。
        await source.putLoginInfo('{"帳號":"舊帳號"}');
        await source.putLoginHeader('{"Authorization":"Bearer keep"}');
        await CookieStore().setCookie(url, 'sid=keep');
      });
      await openLogin(tester);
      await tester.ensureVisible(find.text('刪除登入標頭'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('刪除登入標頭'));
      for (var i = 0; i < 80 && find.text('已刪除登入標頭').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(await tester.runAsync(() => source.getLoginHeader()), isNull);
      expect(
        await tester.runAsync(() => source.getLoginInfo()),
        '{"帳號":"舊帳號"}',
      );
      expect(
        await tester.runAsync(() => CookieStore().getCookie(url)),
        'sid=keep',
      );
      expect(find.widgetWithText(TextField, '舊帳號'), findsOneWidget);
    });

    test('opens the login URL when it is a URL, else the source URL', () {
      BookSource withLogin(String? loginUrl, [String sourceUrl = url]) =>
          BookSource(
            bookSourceUrl: sourceUrl,
            bookSourceName: '書源',
            loginUrl: loginUrl,
          );

      expect(sourceWebsiteLoginUrl(withLogin('@js: login()')), url);
      expect(sourceWebsiteLoginUrl(withLogin('function login() {}')), url);
      expect(sourceWebsiteLoginUrl(withLogin(null)), url);
      expect(
        sourceWebsiteLoginUrl(withLogin('/user/login')),
        'https://login.example/user/login',
      );
      expect(
        sourceWebsiteLoginUrl(withLogin('https://passport.example/login')),
        'https://passport.example/login',
      );
      expect(
        sourceWebsiteLoginUrl(withLogin('HTTPS://passport.example/login')),
        'https://passport.example/login',
      );
      expect(sourceWebsiteLoginUrl(withLogin('user/login')), url);
      expect(sourceWebsiteLoginUrl(withLogin('/login', '聚合書源')), isNull);
    });
  });
}
