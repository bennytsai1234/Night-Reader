import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/sync/replace_rule_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_page.dart';
import 'package:night_reader/shared/widgets/lists/grouped_row.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

void main() {
  late AppDatabase db;
  late ReplaceRuleDao dao;

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = ReplaceRuleDao(db);
    GetIt.instance.registerSingleton<ReplaceRuleDao>(dao);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('開著的替換規則頁收到別台的規則後更新，不用重進', (tester) async {
    await tester.runAsync(
      () => dao.upsert(ReplaceRule(id: 1, name: '去廣告', pattern: 'ad')),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const ReaderReplaceRulePage(),
      ),
    );
    await settle(tester);
    expect(find.text('去廣告'), findsOneWidget);

    final sync = ReplaceRuleSync(dao: dao);
    await tester.runAsync(
      () => sync.apply({
        '2': ReplaceRuleSync.recordOf(
          ReplaceRule(id: 2, name: '別台新增', pattern: 'x'),
        ),
        '1': const SyncRecord(time: 0, data: {}, deleted: true),
      }),
    );
    await settle(tester);

    expect(find.text('別台新增'), findsOneWidget);
    expect(find.text('去廣告'), findsNothing);
  });

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const ReaderReplaceRulePage(),
      ),
    );
  }

  testWidgets('刪過規則之後新增的規則排在最後', (tester) async {
    // 號碼 0、1、2、3 刪掉中間兩條後留下 0 與 3。
    await tester.runAsync(() async {
      await dao.upsert(ReplaceRule(id: 1, name: '第一條', pattern: 'a'));
      await dao.upsert(ReplaceRule(id: 4, name: '第四條', pattern: 'd', order: 3));
    });
    await openPage(tester);
    await settle(tester);

    await tester.tap(find.byTooltip('新增規則'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '新規則');
    await tester.enterText(fields.at(3), 'x');
    await tester.tap(find.text('儲存'));
    await settle(tester);
    await tester.pumpAndSettle();

    final rules = (await tester.runAsync(dao.getAll))!;
    expect(rules.last.name, '新規則');
    expect(rules.last.order, greaterThan(3));
  });

  testWidgets('規則頁打開時畫骨架、切換規則時清單一直在，不放置中轉圈', (tester) async {
    await tester.runAsync(
      () => dao.upsert(ReplaceRule(id: 1, name: '去廣告', pattern: 'ad')),
    );
    await openPage(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await settle(tester);
    expect(find.text('去廣告'), findsOneWidget);

    await tester.tap(find.byType(GroupedSwitch).first);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('去廣告'), findsOneWidget);
    }
    await settle(tester);
    final rules = (await tester.runAsync(dao.getAll))!;
    expect(rules.single.isEnabled, isFalse);
  });
}
