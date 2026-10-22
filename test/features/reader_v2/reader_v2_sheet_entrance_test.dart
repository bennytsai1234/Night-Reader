import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sleep_timer.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import '../../support/app_harness.dart';
import '../../support/glass_motion.dart';
import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';

/// 閱讀器的三個面板（外觀與排版、朗讀、替換規則）滑入時先只畫骨架，滑到位
/// 才在骨架底下逐列建立內容（ADR 0029）。骨架照真的內容的高度畫：從滑入
/// 第一幀到換成內容，面板的高度一格都不變。
///
/// 畫面比手機高（393×1200），三個面板都放得下、不會頂到最大高度，高度
/// 不對時面板真的會長高或縮短。換成內容時記下的樣子（`GroupedListLayouts`）
/// 留在記憶體裡：先跑的深色是第一次打開、照估的畫，淺色照記下的畫；放大
/// 字級與長段落的紀錄 key 不同，也是第一次打開。
void main() {
  const screen = Size(393, 1200);
  final sheet = find.byType(BottomSheet);
  final skeleton = find.descendant(
    of: sheet,
    matching: find.byType(SkeletonShapes),
  );

  /// 這本書目前讀到的第三章，第一段換成很長的一段：替換規則的即時測試框
  /// 會填進這一段，超過三行。
  final longParagraph = kParagraphs.take(5).join();

  Future<void> openReaderOn(
    WidgetTester tester, {
    Size size = screen,
    double textScale = 1,
    Brightness brightness = Brightness.light,
    bool longSample = false,
    ReplaceRuleDao Function(AppDatabase db)? replaceDao,
  }) async {
    setUpScreenshot(tester, size: size);
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.runAsync(() async {
      await setUpApp();
      if (replaceDao != null) {
        getIt
          ..unregister<ReplaceRuleDao>()
          ..registerSingleton<ReplaceRuleDao>(replaceDao(getIt<AppDatabase>()));
      }
      await seedLibrary();
      if (longSample) {
        final chapter = (await getIt<ChapterDao>().getByBook(kBookUrl))[2];
        await ReaderChapterContentStore(
          chapterDao: getIt<ChapterDao>(),
          contentDao: getIt<ReaderChapterContentDao>(),
        ).saveRawContent(
          book: Book(bookUrl: kBookUrl, origin: kOrigin, name: '夜雨聽書'),
          chapter: chapter,
          content: [longParagraph, ...kParagraphs].join('\n'),
          saveChapterMetadata: false,
        );
      }
    });
    await pumpApp(tester);
    await openReader(tester);
    await tester.tapAt(Offset(size.width / 2, size.height / 2));
    await settle(tester, const Duration(milliseconds: 800));
    await waitForText(tester);
  }

  /// 打開 [label] 面板：第一幀只有骨架、沒有最重的元件；之後每一幀的面板
  /// 高度都和第一幀一樣，直到骨架換完再多半秒；換完後內容沒有頂到面板的
  /// 最大高度（不必捲動）。
  Future<void> expectSteadyEntrance(WidgetTester tester, String label) async {
    // 各面板裡最重的元件：步進列、定時的分段控制、即時測試的輸入框。
    final heavy = switch (label) {
      '排版' => find.byType(NumberStepperRow),
      '朗讀' => find.byType(GlassSegmented<ReaderV2TtsSleepOption>),
      _ => find.byType(TextField),
    };
    await tester.tap(
      label == '替換規則' ? find.byTooltip(label) : find.text(label),
    );
    await tester.pump();
    expect(heavy, findsNothing, reason: '$label 滑入第一幀就建了內容');
    expect(skeleton, findsOneWidget, reason: '$label 滑入第一幀沒有骨架');
    final first = tester.getSize(sheet);

    var frames = 0;
    var tail = 0;
    while (tail < 30) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
      if (frames == 8) expectNoGlassUnderFade(tester);
      expect(
        tester.getSize(sheet),
        first,
        reason: '$label 第 $frames 幀的高度和滑入第一幀不同',
      );
      if (skeleton.evaluate().isEmpty) tail++;
      expect(frames, lessThan(600), reason: '$label 骨架一直沒換完');
    }
    expect(heavy, findsWidgets, reason: '$label 換場後沒有內容');
    final scrollable = find
        .descendant(
          of: find.byType(GroupedSheetContent),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      0,
      reason: '$label 頂到了面板的最大高度，量不出高度有沒有跳',
    );
  }

  Future<void> closePanel(WidgetTester tester) async {
    await goBack(tester);
    await rest(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tearDownApp(tester);
    await tester.runAsync(() => getIt<AppDatabase>().close());
  }

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('三種面板滑入第一幀只畫骨架，換成內容前後高度不變（$brightness）', (tester) async {
      await openReaderOn(tester, brightness: brightness);
      for (final label in ['排版', '朗讀', '替換規則']) {
        await expectSteadyEntrance(tester, label);

        // 骨架墊的底色就是面板本身的底色，關閉鈕維持原樣。
        final contentContext = tester.element(find.byType(GroupedSheetContent));
        final background = label == '替換規則'
            ? AppChrome.of(contentContext).groupedBackground
            : Theme.of(contentContext).colorScheme.surface;
        expect(
          tester
              .widget<GroupedSheetContent>(find.byType(GroupedSheetContent))
              .background,
          background,
        );
        expect(
          tester.widget<BottomSheet>(sheet).backgroundColor,
          label == '替換規則' ? background : Colors.transparent,
        );
        final closeGlass = find.descendant(
          of: find.byTooltip('關閉'),
          matching: find.byType(GlassSurface),
        );
        expect(closeGlass, label == '替換規則' ? findsOneWidget : findsNothing);

        if (label == '替換規則') {
          // 鍵盤出現時面板照舊墊高，輸入框捲得到鍵盤上方。
          final field = find.byType(TextField);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
          await tester.pump();
          await settle(tester, const Duration(milliseconds: 400));
          final body = find
              .descendant(
                of: find.byType(AppBottomSheet),
                matching: find.byType(SafeArea),
              )
              .first;
          expect(
            tester.getRect(body).bottom,
            lessThanOrEqualTo(screen.height - 300),
          );
          await tester.ensureVisible(field);
          await tester.pump();
          expect(
            tester.getRect(field).bottom,
            lessThanOrEqualTo(screen.height - 300),
          );
          tester.view.resetViewInsets();
          await tester.pump();
          await settle(tester, const Duration(milliseconds: 400));
        } else {
          expect(
            tester
                .widget<ReaderV2SheetScaffold>(
                  find.byType(ReaderV2SheetScaffold),
                )
                .maxHeightFactor,
            label == '排版' ? 0.6 : 0.9,
          );
        }
        await closePanel(tester);
      }
      await finish(tester);
    });
  }

  // 放大字級時標題會換行（2 倍時「本書套用替換規則」排成兩行），步進列與
  // 組標題也跟著變高；骨架照字與可用寬度真的排。
  for (final scale in [1.3, 2.0]) {
    testWidgets('系統字級 $scale 倍時三種面板換成內容前後高度不變', (tester) async {
      await openReaderOn(tester, textScale: scale);
      for (final label in ['排版', '朗讀', '替換規則']) {
        await expectSteadyEntrance(tester, label);
        await closePanel(tester);
      }
      await finish(tester);
    });
  }

  // 點下去面板就滑上來，原文是之後才讀到、填進測試框的；測試框固定三行高，
  // 長的原文在框內捲動，面板從第一幀到換完都一樣高。
  testWidgets('即時測試框之後才填進很長的一段，替換規則面板高度不變', (tester) async {
    await openReaderOn(tester, longSample: true);
    await expectSteadyEntrance(tester, '替換規則');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, longParagraph);
    expect((field.minLines, field.maxLines), (3, 3));
    await closePanel(tester);
    await finish(tester);
  });

  // 規則數是面板打開後才讀的：讀不到時「管理規則」換成「規則讀取失敗／
  // 重試」。窄畫面放大字級時「規則讀取失敗」放不下一行，這一列只排一行
  // （截斷），換成失敗那一列面板也不長高。
  testWidgets('讀不到啟用的規則時，換成失敗那一列面板高度也不變', (tester) async {
    late _FlakyReplaceRuleDao dao;
    await openReaderOn(
      tester,
      size: const Size(320, 1600),
      textScale: 2,
      replaceDao: (db) => dao = _FlakyReplaceRuleDao(db),
    );
    // 閱讀器開書時已經讀好、記住了規則；之後才讀不到，只影響面板自己的讀取。
    dao.failing = true;
    await expectSteadyEntrance(tester, '替換規則');
    expect(find.text('規則讀取失敗'), findsOneWidget);

    // 重試仍讀不到時留在失敗那一列，錯誤不外漏；讀得到了就換回規則數。
    await tester.tap(find.text('重試'));
    await settle(tester, const Duration(milliseconds: 300));
    expect(find.text('規則讀取失敗'), findsOneWidget);
    dao.failing = false;
    await tester.tap(find.text('重試'));
    await settle(tester, const Duration(milliseconds: 300));
    expect(find.text('管理規則'), findsOneWidget);
    await closePanel(tester);
    await finish(tester);
  });
}

/// [failing] 時讀不到這本書啟用的規則。
class _FlakyReplaceRuleDao extends ReplaceRuleDao {
  _FlakyReplaceRuleDao(super.attachedDatabase);

  bool failing = false;

  @override
  Future<List<ReplaceRule>> getEnabledForBook(
    String name,
    String origin,
  ) async {
    if (failing) throw StateError('資料庫讀不到');
    return super.getEnabledForBook(name, origin);
  }
}
