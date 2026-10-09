import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可以把書源讀取卡住的 DAO，用來觀察「重新載入中」的畫面。
class _GatedSourceDao extends BookSourceDao {
  _GatedSourceDao(super.db);

  Completer<void>? gate;

  @override
  Future<List<BookSource>> getAllPart() async {
    await gate?.future;
    return super.getAllPart();
  }

  @override
  Future<void> updateEnabledByUrl(String url, bool enabled) async {
    await gate?.future;
    return super.updateEnabledByUrl(url, enabled);
  }
}

void main() {
  late AppDatabase db;
  late _GatedSourceDao gatedDao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gatedDao = _GatedSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(gatedDao);
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

  testWidgets('reloading keeps the list instead of a full-page spinner', (
    tester,
  ) async {
    await pumpPage(tester);
    final provider = Provider.of<SourceManagerProvider>(
      tester.element(find.text('書源0')),
      listen: false,
    );

    gatedDao.gate = Completer<void>();
    final reload = provider.loadSources();
    await tester.pump();
    expect(provider.isLoading, isTrue);
    expect(find.text('書源0'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gatedDao.gate!.complete();
    await tester.runAsync(() => reload);
  });

  testWidgets('toggling one source leaves the other rows usable', (
    tester,
  ) async {
    await pumpPage(tester);

    // 卡住寫入，畫面停在「第一列修改中」。
    gatedDao.gate = Completer<void>();
    await tester.tap(find.byType(GroupedSwitch).first);
    await tester.pump();

    final switches = tester
        .widgetList<GroupedSwitch>(find.byType(GroupedSwitch))
        .toList();
    expect(switches.first.onChanged, isNull);
    expect(switches.skip(1).every((s) => s.onChanged != null), isTrue);

    gatedDao.gate!.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  });
}
