import 'dart:async';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/search_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/glass_motion.dart';

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

  testWidgets('退出選取的每一幀都維持有效的列寬', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();
    final provider = Provider.of<SourceManagerProvider>(
      tester.element(find.text('書源0')),
      listen: false,
    );
    provider.toggleSelect('https://s0.example');
    await tester.pumpAndSettle();

    provider.clearSelection();
    await tester.pump();
    for (
      var elapsed = 0;
      elapsed <= AppMotion.spring.inMilliseconds;
      elapsed += 16
    ) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(SourceItemTile).first).width,
        greaterThan(0),
      );
    }
    expect(find.bySemanticsLabel('書源0 啟用'), findsOneWidget);
  });

  testWidgets('不在多選時看不到勾選圈', (tester) async {
    // 勾選圈在槽外溢出，看得到多寬取決於它和列之間的裁切。
    double visibleCircleWidth() {
      final tile = find.byType(SourceItemTile).first;
      final circle = tester.renderObject<RenderBox>(
        find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_SelectionCircle',
          ),
        ),
      );
      final tileBox = tester.renderObject(tile);
      var visible = circle.localToGlobal(Offset.zero) & circle.size;
      for (var node = circle.parent; node != null && node != tileBox;) {
        if (node is RenderClipRect) {
          visible = visible.intersect(
            node.localToGlobal(Offset.zero) & node.size,
          );
        }
        node = node.parent;
      }
      return math.max(0, visible.width);
    }

    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(visibleCircleWidth(), 0);

    final provider = Provider.of<SourceManagerProvider>(
      tester.element(find.text('書源0')),
      listen: false,
    );
    provider.toggleSelect('https://s0.example');
    await tester.pumpAndSettle();
    expect(visibleCircleWidth(), greaterThan(0));

    provider.clearSelection();
    await tester.pumpAndSettle();
    expect(visibleCircleWidth(), 0);
  });

  testWidgets('搜尋框只多空白時不重新建立相同的書源清單', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();
    final provider = Provider.of<SourceManagerProvider>(
      tester.element(find.text('書源0')),
      listen: false,
    );
    provider.setSearchQuery('書源');
    await tester.pumpAndSettle();
    var changes = 0;
    void onChanged() => changes++;
    provider.addListener(onChanged);

    provider.setSearchQuery('書源 ');

    expect(changes, 0);
    provider.removeListener(onChanged);
  });

  testWidgets('首次內容在骨架下面一幀只建立一列書源', (tester) async {
    gatedDao.gate = Completer<void>();
    await pumpPage(tester, sources: 30);
    final provider = Provider.of<SourceManagerProvider>(
      tester.element(find.byType(SourceListSkeleton)),
      listen: false,
    );
    final perFrame = <int>[];
    var rows = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is SourceItemTile) rows++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    gatedDao.gate!.complete();
    for (var frame = 0; frame < 180; frame++) {
      rows = 0;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 16));
      perFrame.add(rows);
      if (!provider.isLoading &&
          find.byType(SourceListSkeleton).evaluate().isEmpty) {
        break;
      }
    }
    debugOnRebuildDirtyWidget = previous;

    expect(provider.totalSourceCount, 30);
    expect(find.byType(SourceListSkeleton), findsNothing);
    expect(find.byType(SourceItemTile), findsWidgets);
    expect(
      perFrame.every((count) => count <= 1),
      isTrue,
      reason: '每一幀建立的書源列數：$perFrame',
    );
  });

  testWidgets('entering selection crossfades the title and morphs the glass', (
    tester,
  ) async {
    await pumpPage(tester);
    double trailingWidth() =>
        tester.getSize(find.byType(GlassMorph).last).width;
    final menuWidth = trailingWidth();

    await tester.tap(find.bySemanticsLabel('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選取書源'));
    await tester.pump();
    await tester.pump(AppMotion.fade ~/ 2);
    // 淡換途中新舊標題都在；玻璃按鈕不在淡入裡，寬度在半路。
    Finder header(String text) => find.descendant(
      of: find.byType(GlassNavHeader),
      matching: find.text(text),
    );
    expect(header('書源管理'), findsOneWidget);
    expect(header('選取書源'), findsOneWidget);
    expectNoGlassUnderFade(tester);
    final midway = trailingWidth();
    expect(midway, greaterThan(menuWidth));

    await tester.pumpAndSettle();
    expect(find.text('書源管理'), findsNothing);
    expect(trailingWidth(), greaterThan(midway));
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

  testWidgets('「沒有異常」只留下校驗沒標異常的書源', (tester) async {
    final dao = GetIt.instance<BookSourceDao>();
    await tester.runAsync(() async {
      await dao.upsert(
        BookSource(
          bookSourceUrl: 'https://broken.example',
          bookSourceName: '壞掉的書源',
          bookSourceGroup:
              '$abnormalSourceGroupTag,$searchBrokenSourceGroupTag',
          customOrder: 9,
        ),
      );
    });
    await pumpPage(tester);

    final provider = Provider.of<SourceManagerProvider>(
      tester.element(find.byType(SourceItemTile).first),
      listen: false,
    );
    expect(provider.checkResultTags, [
      abnormalSourceGroupTag,
      searchBrokenSourceGroupTag,
    ]);
    expect(provider.userGroups, isNot(contains(abnormalSourceGroupTag)));

    await tester.tap(find.bySemanticsLabel('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分組與篩選'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SourceManagerProvider.noAbnormalFilter));
    await tester.pumpAndSettle();
    expect(find.textContaining('壞掉的書源'), findsNothing);
    expect(find.textContaining('書源0'), findsOneWidget);
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

    for (final (label, record) in [('a string', 'bad'), ('negative', -3)]) {
      testWidgets('a damaged count record ($label) counts as no record', (
        tester,
      ) async {
        final prefs = GetIt.instance<SharedPreferences>();
        if (record is String) {
          await prefs.setString('source_manager_last_count', record);
        } else {
          await prefs.setInt('source_manager_last_count', record as int);
        }
        gatedDao.gate = Completer<void>();
        await pumpPage(tester);

        // 和沒有紀錄一樣：當作有書源，先畫骨架、留好搜尋框與工具列。
        expect(tester.takeException(), isNull);
        expect(skeletonRows(), findsWidgets);
        expect(find.byType(SearchField), findsOneWidget);
        expect(find.byType(SelectActionBar), findsOneWidget);

        gatedDao.gate!.complete();
        await settleQueries(tester);
        await tester.pumpAndSettle();
        expect(find.text('書源0'), findsOneWidget);
        expect(prefs.get('source_manager_last_count'), 3);
      });
    }

    testWidgets('the toolbar takes its shadow off screen before it goes', (
      tester,
    ) async {
      // 沒有紀錄時當作有書源，工具列先在；讀完發現沒有書源才收起。
      gatedDao.gate = Completer<void>();
      await pumpPage(tester, sources: 0);
      expect(find.byType(SelectActionBar), findsOneWidget);
      final screen = tester.getSize(find.byType(Scaffold)).height;
      final glass = find.descendant(
        of: find.byType(SelectActionBar),
        matching: find.byType(GlassSurface),
      );

      gatedDao.gate!.complete();
      await settleQueries(tester);
      // 每一幀陰影伸進畫面的距離（玻璃上緣再往上 [AppGlass.shadowReach]）。
      final intrusions = <double>[];
      while (glass.evaluate().isNotEmpty) {
        intrusions.add(
          screen - (tester.getTopLeft(glass).dy - AppGlass.shadowReach),
        );
        await tester.pump(const Duration(milliseconds: 1));
      }

      expect(intrusions.length, greaterThan(100));
      // 拿掉前最後一幀（還差 1ms），陰影只剩一點點在畫面內，跟著動畫收到
      // 底，不會留著整段陰影到拿掉時才一下消失。
      expect(intrusions.last, lessThan(4));
      for (var i = 1; i < intrusions.length; i++) {
        expect(intrusions[i], lessThanOrEqualTo(intrusions[i - 1]));
      }
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
