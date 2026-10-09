import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    GetIt.instance.registerSingleton<BookSourceDao>(BookSourceDao(db));
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    final dao = GetIt.instance<BookSourceDao>();
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        await dao.upsert(
          BookSource(
            bookSourceUrl: 'https://s$i.example',
            bookSourceName: '書源$i',
            searchUrl: '/s?q={{key}}',
            customOrder: i,
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.dark),
        home: const SourceManagerPage(),
      ),
    );
    // 讓 DAO 查詢在真實事件迴圈上完成，再把結果畫出來。
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('lists every source row', (tester) async {
    await pumpPage(tester);

    for (var i = 0; i < 3; i++) {
      expect(find.text('書源$i'), findsOneWidget);
      expect(find.text('https://s$i.example'), findsOneWidget);
    }
  });

  testWidgets('rows stay laid out in selection mode', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.bySemanticsLabel('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選取書源'));
    await tester.pumpAndSettle();

    expect(find.text('選取書源'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      expect(find.text('書源$i'), findsOneWidget);
    }
  });
}
