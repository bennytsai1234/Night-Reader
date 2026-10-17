import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/source_manager/widgets/source_batch_toolbar.dart';
import 'package:night_reader/features/source_manager/widgets/source_item_tile.dart';
import 'package:night_reader/features/source_manager/widgets/source_list_skeleton.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/search_field.dart';
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

  /// 讓 DAO 查詢在真實事件迴圈上完成，再把結果畫出來。
  Future<void> settleQueries(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    gatedDao = _GatedSourceDao(db);
    GetIt.instance.registerSingleton<BookSourceDao>(gatedDao);
    GetIt.instance.registerLazySingleton<CheckSourceService>(
      CheckSourceService.new,
    );
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<void> pumpPage(WidgetTester tester, {int sources = 3}) async {
    final dao = GetIt.instance<BookSourceDao>();
    await tester.runAsync(() async {
      for (var i = 0; i < sources; i++) {
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
    await settleQueries(tester);
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

  testWidgets('the group menu lists check marks and filters by them', (
    tester,
  ) async {
    // 手機尺寸、狀態列高度帶小數：選單比螢幕高時要能捲動，不能整個崩掉。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    tester.view.padding = const FakeViewPadding(top: 130, bottom: 66);
    addTearDown(tester.view.reset);
    final dao = GetIt.instance<BookSourceDao>();
    await tester.runAsync(() async {
      await dao.upsert(
        BookSource(
          bookSourceUrl: 'https://broken.example',
          bookSourceName: '壞掉的書源',
          bookSourceGroup: '精選,${sourceRuntimeStatusTags.join(',')}',
          customOrder: 9,
        ),
      );
      for (var i = 0; i < 12; i++) {
        await dao.upsert(
          BookSource(
            bookSourceUrl: 'https://g$i.example',
            bookSourceName: '分組書源$i',
            bookSourceGroup: '自訂分組$i',
            customOrder: 10 + i,
          ),
        );
      }
    });
    await pumpPage(tester);

    // 分組與篩選在「更多」選單的第一層，點了接著開出第二層。
    await tester.tap(find.bySemanticsLabel('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分組與篩選'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(abnormalSourceGroupTag), findsOneWidget);

    await tester.tap(find.text(abnormalSourceGroupTag));
    await tester.pumpAndSettle();
    expect(find.textContaining('壞掉的書源'), findsOneWidget);
    expect(find.textContaining('書源0'), findsNothing);

    // 篩出校驗失敗的書源後，用底部工作列全選刪除。
    await tester.tap(find.text('全選'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刪除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定刪除'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    final remaining = await tester.runAsync(dao.getAll);
    expect(
      remaining!.map((s) => s.bookSourceUrl),
      isNot(contains('https://broken.example')),
    );
    expect(remaining, hasLength(15));
  });

  testWidgets('the batch toolbar stays at the bottom outside selection mode', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('全選'), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);

    await tester.tap(find.text('全選'));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);
    expect(find.text('已選 3 項'), findsOneWidget);
    expect(find.text('反選'), findsOneWidget);
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

  testWidgets('the text area widens continuously when the switch fades out', (
    tester,
  ) async {
    await pumpPage(tester);
    // 篩選中沒有排序把手：進入選取時列尾從開關換成空的，文字區要多出
    // 整個開關的寬度。
    await tester.enterText(find.byType(TextField), 'example');
    await tester.pumpAndSettle();
    final textArea = find
        .ancestor(
          of: find.text('https://s0.example'),
          matching: find.byType(Column),
        )
        .first;
    final restWidth = tester.getSize(textArea).width;

    await tester.tap(find.text('全選'));
    await tester.pump();
    final widths = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      widths.add(tester.getSize(textArea).width);
    }
    await tester.pumpAndSettle();
    final settled = tester.getSize(textArea).width;

    expect(find.byType(GroupedSwitch), findsNothing);
    // 勾選圈佔掉的比開關讓出的少，文字區最後比原本寬。
    expect(settled, greaterThan(restWidth + 10));
    var previous = restWidth;
    for (final width in widths) {
      expect(
        (width - previous).abs(),
        lessThan(12),
        reason: '文字區每一幀只變一點，不在淡換結束時一口氣跳寬',
      );
      previous = width;
    }
    expect(widths.last, moreOrLessEquals(settled, epsilon: 0.01));
  });

  group('first open', () {
    Finder skeletonRows() => find.descendant(
      of: find.byType(SourceListSkeleton),
      matching: find.byType(GroupedSliceItem),
    );

    testWidgets('draws row skeletons with the search box and toolbar placed', (
      tester,
    ) async {
      gatedDao.gate = Completer<void>();
      await pumpPage(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(skeletonRows(), findsWidgets);
      expect(find.byType(SearchField), findsOneWidget);
      expect(find.byType(SelectActionBar), findsOneWidget);
      final skeletonTop = tester.getTopLeft(skeletonRows().first).dy;
      final headerHeight = tester.getSize(find.byType(GlassNavHeader)).height;

      gatedDao.gate!.complete();
      await settleQueries(tester);
      await tester.pumpAndSettle();

      expect(find.byType(SourceListSkeleton), findsNothing);
      // 清單從骨架的位置出現，頁首沒有長高把它推開。
      expect(
        tester.getTopLeft(find.byType(SourceItemTile).first).dy,
        skeletonTop,
      );
      expect(tester.getSize(find.byType(GlassNavHeader)).height, headerHeight);
    });

    testWidgets('remembers how many sources there were', (tester) async {
      await pumpPage(tester);
      await tester.pumpWidget(const SizedBox());

      gatedDao.gate = Completer<void>();
      await pumpPage(tester, sources: 0);
      // 上次讀到 3 個書源，骨架就畫 3 列。
      expect(skeletonRows(), findsNWidgets(3));
      gatedDao.gate!.complete();
      await settleQueries(tester);
    });

    testWidgets('no sources last time: no search box, then the empty page', (
      tester,
    ) async {
      await GetIt.instance<SharedPreferences>().setInt(
        'source_manager_last_count',
        0,
      );
      gatedDao.gate = Completer<void>();
      await pumpPage(tester, sources: 0);

      expect(skeletonRows(), findsNothing);
      expect(find.byType(SearchField), findsNothing);
      expect(find.byType(SelectActionBar), findsNothing);
      expect(find.text('尚未加入書源'), findsNothing);

      gatedDao.gate!.complete();
      await settleQueries(tester);
      await tester.pumpAndSettle();
      expect(find.text('尚未加入書源'), findsOneWidget);
      expect(find.byType(SearchField), findsNothing);
    });

    testWidgets('search box grows in when the record was wrong', (
      tester,
    ) async {
      await GetIt.instance<SharedPreferences>().setInt(
        'source_manager_last_count',
        0,
      );
      gatedDao.gate = Completer<void>();
      await pumpPage(tester);
      final before = tester.getSize(find.byType(GlassNavHeader)).height;

      gatedDao.gate!.complete();
      await settleQueries(tester);
      await tester.pump(const Duration(milliseconds: 60));
      final mid = tester.getSize(find.byType(GlassNavHeader)).height;
      await tester.pumpAndSettle();
      final after = tester.getSize(find.byType(GlassNavHeader)).height;

      expect(after, greaterThan(before));
      expect(mid, greaterThan(before));
      expect(mid, lessThan(after));
      expect(find.byType(SearchField), findsOneWidget);
      expect(find.byType(SelectActionBar), findsOneWidget);
    });
  });
}
