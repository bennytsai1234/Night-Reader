import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_sheet.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

void main() {
  late AppDatabase db;
  late ReplaceRuleDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = ReplaceRuleDao(db);
  });

  tearDown(() => db.close());

  /// 讀資料庫與試跑的 isolate 都是真的非同步，和假時鐘輪流推進。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: ReaderV2ReplaceRuleSheet(
            book: Book(bookUrl: 'https://b.test/1', origin: 'https://b.test'),
            bookDao: BookDao(db),
            replaceDao: dao,
            onReload: () async {},
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('執行測試照這本書啟用的規則依序套用', (tester) async {
    await tester.runAsync(() async {
      await dao.upsert(
        ReplaceRule(id: 1, name: '去廣告', pattern: r'junk\d+', order: 0),
      );
      await dao.upsert(
        ReplaceRule(
          id: 2,
          name: '改字',
          pattern: '內容',
          replacement: '正文',
          isRegex: false,
          order: 1,
        ),
      );
    });
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), '包含 junk123 內容');
    await tester.tap(find.text('執行測試'));
    await settle(tester);

    expect(find.text('包含  正文'), findsOneWidget);
  });

  testWidgets('回溯很久的規則跑到期限就停，面板照常可以操作', (tester) async {
    await tester.runAsync(
      () => dao.upsert(
        ReplaceRule(
          id: 1,
          name: '回溯',
          pattern: r'^(a+)+$',
          replacement: 'x',
          timeoutMillisecond: 200,
        ),
      ),
    );
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), '${'a' * 30}!');
    await tester.tap(find.text('執行測試'));
    await settle(tester);
    expect(find.text('測試中…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('規則「回溯」執行超過 200 毫秒，已停止'), findsOneWidget);
    expect(find.text('執行測試'), findsOneWidget);
  });
}
