import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_page.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_select_bar.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
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

  Future<List<String>> namesInOrder(WidgetTester tester) async {
    final rules = (await tester.runAsync(dao.getAll))!;
    return [for (final rule in rules) rule.name];
  }

  Future<void> addRules(WidgetTester tester) async {
    await tester.runAsync(() async {
      await dao.upsert(
        ReplaceRule(id: 1, name: '去廣告', pattern: 'ad', order: 0),
      );
      await dao.upsert(ReplaceRule(id: 2, name: '修標點', pattern: ',', order: 1));
      await dao.upsert(
        ReplaceRule(id: 3, name: '去空白', pattern: r'\s+', order: 2),
      );
    });
  }

  testWidgets('長按選單可以把一條規則置頂或置底', (tester) async {
    await addRules(tester);
    await openPage(tester);
    await settle(tester);

    await tester.longPress(find.text('去空白'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置頂'));
    await settle(tester);
    expect(await namesInOrder(tester), ['去空白', '去廣告', '修標點']);

    await tester.longPress(find.text('去廣告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置底'));
    await settle(tester);
    expect(await namesInOrder(tester), ['去空白', '修標點', '去廣告']);
  });

  testWidgets('搜尋框比對規則名稱與分組，找不到時可以清除', (tester) async {
    await tester.runAsync(() async {
      await dao.upsert(
        ReplaceRule(id: 1, name: '去廣告', group: '廣告', pattern: 'ad', order: 0),
      );
      await dao.upsert(
        ReplaceRule(id: 2, name: '修標點', group: '標點修復', pattern: ',', order: 1),
      );
      await dao.upsert(
        ReplaceRule(id: 3, name: '去空白', pattern: r'\s+', order: 2),
      );
    });
    await openPage(tester);
    await settle(tester);

    await tester.enterText(find.byType(TextField), '廣告');
    await settle(tester);
    expect(find.text('去廣告'), findsOneWidget);
    expect(find.text('修標點'), findsNothing);
    expect(find.text('去空白'), findsNothing);

    await tester.enterText(find.byType(TextField), '修復');
    await settle(tester);
    expect(find.text('去廣告'), findsNothing);
    expect(find.text('修標點'), findsOneWidget);
    expect(find.text('去空白'), findsNothing);

    await tester.enterText(find.byType(TextField), '沒有這條');
    await settle(tester);
    expect(find.text('找不到符合條件的規則'), findsOneWidget);

    await tester.tap(find.text('清除搜尋'));
    await settle(tester);
    expect(find.text('去廣告'), findsOneWidget);
    expect(find.text('修標點'), findsOneWidget);
    expect(find.text('去空白'), findsOneWidget);
  });

  testWidgets('多選工具列從畫面外滑進，離開時滑出去', (tester) async {
    await addRules(tester);
    await openPage(tester);
    await settle(tester);
    expect(find.byType(ReaderReplaceRuleSelectBar), findsNothing);

    await tester.longPress(find.text('去廣告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選取'));
    await tester.pump();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final start = tester.getRect(find.byType(ReaderReplaceRuleSelectBar));
    expect(start.top, greaterThanOrEqualTo(screenHeight), reason: '第一幀還在畫面外');

    await tester.pump(AppMotion.menu * 0.5);
    final midway = tester.getRect(find.byType(ReaderReplaceRuleSelectBar));
    expect(midway.top, lessThan(start.top));
    expect(midway.top, greaterThan(0));

    await tester.pump(AppMotion.menu);
    final resting = tester.getRect(find.byType(ReaderReplaceRuleSelectBar));
    expect(resting.top, lessThan(midway.top));
    expect(resting.bottom, lessThanOrEqualTo(screenHeight));
    expect(resting.bottom, greaterThan(screenHeight - 100));

    await tester.tap(find.text('完成'));
    await tester.pump();
    final leavingStart = tester.getRect(
      find.byType(ReaderReplaceRuleSelectBar),
    );
    expect(leavingStart.top, greaterThanOrEqualTo(resting.top));

    await tester.pump(AppMotion.menu * 0.5);
    final leaving = tester.getRect(find.byType(ReaderReplaceRuleSelectBar));
    expect(leaving.top, greaterThan(resting.top));

    await tester.pumpAndSettle();
    expect(find.byType(ReaderReplaceRuleSelectBar), findsNothing);
  });

  testWidgets('多選後一起停用選中的規則', (tester) async {
    await addRules(tester);
    await openPage(tester);
    await settle(tester);

    await tester.longPress(find.text('去廣告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    expect(find.text('已選 1 項'), findsOneWidget);

    await tester.tap(find.text('去空白'));
    await settle(tester);
    expect(find.text('已選 2 項'), findsOneWidget);
    expect(find.text('編輯規則'), findsNothing);

    await tester.tap(find.text('停用'));
    await settle(tester);

    final rules = (await tester.runAsync(dao.getAll))!;
    expect(
      {for (final rule in rules) rule.name: rule.isEnabled},
      {'去廣告': false, '修標點': true, '去空白': false},
    );

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('已選 2 項'), findsNothing);
    expect(find.text('替換規則'), findsOneWidget);
  });

  testWidgets('多選後一起刪除選中的規則，先確認', (tester) async {
    await addRules(tester);
    await openPage(tester);
    await settle(tester);

    await tester.longPress(find.text('修標點'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去廣告'));
    await settle(tester);

    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    expect(find.text('刪除 2 個規則？'), findsOneWidget);
    expect(find.text('無法復原'), findsOneWidget);

    await tester.tap(find.text('刪除').last);
    await tester.pumpAndSettle();

    expect(await namesInOrder(tester), ['去空白']);
    expect(find.text('已選 2 項'), findsNothing);
    expect(find.text('選取規則'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('替換規則'), findsOneWidget);
  });
  testWidgets('多選後匯出選中的規則：照套用順序複製成 Legado 讀得懂的 JSON', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
    await addRules(tester);
    await openPage(tester);
    await settle(tester);

    await tester.longPress(find.text('去空白'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選取'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去廣告'));
    await settle(tester);

    await tester.tap(find.text('匯出'));
    await tester.pumpAndSettle();
    expect(find.text('分享選中'), findsOneWidget);
    await tester.tap(find.text('匯出選中'));
    await settle(tester);

    final exported = jsonDecode(copied!) as List<dynamic>;
    expect(
      [for (final rule in exported) (rule as Map)['name']],
      ['去廣告', '去空白'],
    );
    expect((exported.first as Map)['isEnabled'], isTrue);
    expect((exported.first as Map)['isRegex'], isTrue);
    expect(find.text('已複製至剪貼簿'), findsOneWidget);
  });
}
