import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

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
    bool checkAfter = false,
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
                  checkAfter: checkAfter,
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

  /// 關掉登入頁，等它存好、[openSourceLogin] 比完傳回。存檔與比對在測試的
  /// 假時間裡排，資料庫要真的時間，所以兩邊輪流推進。
  Future<bool> close(WidgetTester tester, Future<bool> result) async {
    bool? changed;
    unawaited(result.then((value) => changed = value));
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    for (var i = 0; i < 100 && changed == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    return changed!;
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

  group('checks the source after logging in', () {
    late _RecordingCheckService checks;

    setUp(() {
      checks = _RecordingCheckService();
      getIt.registerSingleton<CheckSourceService>(checks);
    });

    testWidgets('when the login data changed', (tester) async {
      setupTestDI();
      await tester.runAsync(() => dao.upsert(source));

      // 前面的測試存的帳號會留在 App 共用的快取裡，每個測試填不同的。
      final closed = await openLogin(tester, checkAfter: true);
      await tester.enterText(find.byType(TextField), '要校驗的帳號');

      expect(await close(tester, closed), isTrue);
      expect(checks.checked, [
        [url],
      ]);
    });

    testWidgets('not when leaving without logging in', (tester) async {
      setupTestDI();
      await tester.runAsync(() => dao.upsert(source));

      final closed = await openLogin(tester, checkAfter: true);

      expect(await close(tester, closed), isFalse);
      expect(checks.checked, isEmpty);
    });

    testWidgets('not when opened from where it failed', (tester) async {
      setupTestDI();
      await tester.runAsync(() => dao.upsert(source));

      final closed = await openLogin(tester);
      await tester.enterText(find.byType(TextField), '不校驗的帳號');

      expect(await close(tester, closed), isTrue);
      expect(checks.checked, isEmpty);
    });
  });

  group('log in on the website', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byType(GlassMenuButton<String>));
      await tester.pumpAndSettle();
    }

    testWidgets('is in the form menu of a website source', (tester) async {
      setupTestDI();
      await tester.runAsync(() => dao.upsert(source));

      await openLogin(tester);
      await openMenu(tester);

      expect(find.text('在網站登入'), findsOneWidget);
    });

    testWidgets('is not offered when the source URL is a name', (tester) async {
      setupTestDI();
      final named = BookSource.fromJson({
        ...source.toJson(),
        'bookSourceUrl': '聚合書源',
      });
      await tester.runAsync(() => dao.upsert(named));

      await openLogin(tester, login: named);
      await openMenu(tester);

      expect(find.text('登入標頭'), findsOneWidget);
      expect(find.text('在網站登入'), findsNothing);
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
      expect(sourceWebsiteLoginUrl(withLogin('/login', '聚合書源')), isNull);
    });
  });
}

/// 只記下要校驗哪些書源，不真的校驗。
class _RecordingCheckService extends CheckSourceService {
  final List<List<String>> checked = [];

  @override
  Future<SourceCheckReport> check(List<String> urls) async {
    checked.add(urls);
    return SourceCheckReport.empty;
  }
}
