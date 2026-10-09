import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/source_group_manage_page.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late BookSourceDao dao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(dao);
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
      await tester.pumpAndSettle();
    }
  }

  testWidgets('a new group is created from the sources picked for it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 2; i++) {
        await dao.upsert(
          BookSource(
            bookSourceUrl: 'https://s$i.example',
            bookSourceName: '書源$i',
            customOrder: i,
          ),
        );
      }
    });
    final provider = SourceManagerProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<SourceManagerProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: const SourceGroupManagePage(),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('新增分組').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '🔥 精選');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();

    expect(find.text('加入「🔥 精選」'), findsOneWidget);
    await tester.tap(find.text('書源1'));
    await tester.pump();
    await tester.tap(find.text('完成（1）'));
    await settle(tester);

    final saved = await tester.runAsync(
      () => dao.getByUrl('https://s1.example'),
    );
    expect(saved!.groupTags, {'🔥 精選'});
    expect(provider.allGroups, ['🔥 精選']);
    expect(find.text('🔥 精選'), findsOneWidget);
  });
}
