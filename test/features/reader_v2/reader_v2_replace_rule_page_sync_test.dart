import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/sync/replace_rule_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';
import 'package:night_reader/features/reader_v2/features/replace_rule/reader_v2_replace_rule_page.dart';
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
        home: const ReaderV2ReplaceRulePage(),
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
}
