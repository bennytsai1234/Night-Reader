import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';

void main() {
  setUpAll(
    () =>
        ChineseUtils.initializeFromDictionaryData(['', '', '', '書\t书\n籤\t签\n']),
  );

  testWidgets('推入頁面的進場照組本身的設定畫組標題：書名不跟介面語言轉換', (tester) async {
    await tester.pumpWidget(
      UiLanguageScope(
        locale: const Locale('zh', 'CN'),
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: GroupedListView(
                          children: [
                            GroupedSection(
                              children: [
                                GroupedRow(
                                  title: '書名',
                                  heading: true,
                                  translateTitle: false,
                                ),
                                GroupedRow(title: '書籤'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('開啟'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();

    expect(find.text('书签'), findsOneWidget);
    expect(find.text('書名'), findsOneWidget);
    expect(find.text('书名'), findsNothing);
  });

  group('進場的三段', () {
    Widget list() => const GroupedListView(
      children: [
        GroupedSection(
          header: '外觀',
          children: [GroupedRow(title: '風格')],
        ),
      ],
    );

    testWidgets('不是在進場中掛上的清單第一格就是內容，沒有骨架', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Scaffold(body: list()),
        ),
      );
      expect(find.text('風格'), findsOneWidget);
      expect(find.byType(GroupedListSkeleton), findsNothing);
    });

    testWidgets('推入的頁面進場中只畫骨架、不建任何一列；進場播完才換成內容，之後骨架拿掉', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(body: list()),
                    ),
                  ),
                  child: const Text('開啟'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開啟'));
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byType(GroupedListView, skipOffstage: false)),
      )!;
      var frames = 0;
      while (!route.animation!.isCompleted) {
        expect(
          find.byType(GroupedListSkeleton, skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text('風格', skipOffstage: false),
          findsNothing,
          reason: '進場第 $frames 格不建列',
        );
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      expect(frames, greaterThan(5), reason: '進場要播一段');

      // 進場播完後才在骨架底下建好，換場途中骨架與內容都在。
      var overlapped = false;
      for (var i = 0; i < 120 && !overlapped; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        overlapped =
            find.text('風格').evaluate().isNotEmpty &&
            find.byType(GroupedListSkeleton).evaluate().isNotEmpty;
      }
      expect(overlapped, isTrue, reason: '照骨架換場換成內容');

      await tester.pumpAndSettle();
      expect(find.text('風格'), findsOneWidget);
      expect(find.byType(GroupedListSkeleton), findsNothing, reason: '換好就拿掉');
    });
  });

  group('換場後先建畫面外的列', () {
    // 八組各五列，比一個畫面長、在畫面加下面三個畫面以內。
    const sections = 8;
    const rowsPerSection = 5;
    String title(int s, int r) => '第$s組第$r列';

    int builtRows() => find
        .textContaining('組第', skipOffstage: false, findRichText: true)
        .evaluate()
        .length;

    Future<void> open(WidgetTester tester, {required Widget page}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => page)),
                  child: const Text('開啟'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開啟'));
      await tester.pump();
    }

    Widget page({List<Widget> extra = const []}) => Scaffold(
      body: GroupedListView(
        children: [
          for (var s = 0; s < sections; s++)
            GroupedSection(
              children: [
                for (var r = 0; r < rowsPerSection; r++)
                  GroupedRow(title: title(s, r)),
                if (s == 0) ...extra,
              ],
            ),
        ],
      ),
    );

    /// 推到換場播完：骨架拿掉的那一格。
    Future<void> reveal(WidgetTester tester) async {
      bool skeleton() => find
          .byType(GroupedListSkeleton, skipOffstage: false)
          .evaluate()
          .isNotEmpty;
      expect(skeleton(), isTrue, reason: '推入的頁面先畫骨架');
      for (var i = 0; i < 300 && skeleton(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(skeleton(), isFalse);
    }

    testWidgets('換場播完的下一格一次建好畫面外的列，之後捲到底再捲回來不再建列、也不拆掉', (tester) async {
      await open(tester, page: page());
      await reveal(tester);
      expect(
        builtRows(),
        lessThan(sections * rowsPerSection),
        reason: '整組在畫面外的列換場不等它們',
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(builtRows(), sections * rowsPerSection, reason: '換場播完的下一格都建好');

      // 手指捲到底再捲回來，每一格都沒有新建或拆掉的列。
      final gesture = await tester.startGesture(const Offset(400, 500));
      for (var i = 0; i < 120; i++) {
        await gesture.moveBy(Offset(0, i < 60 ? -40 : 40));
        await tester.pump(const Duration(milliseconds: 16));
        expect(builtRows(), sections * rowsPerSection, reason: '捲動第 $i 格');
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(builtRows(), sections * rowsPerSection);
    });

    testWidgets('換場後清單高度變了（鍵盤升降），建好的列不拆掉重建', (tester) async {
      addTearDown(tester.view.reset);
      await open(tester, page: page());
      await reveal(tester);
      await tester.pump(const Duration(milliseconds: 16));
      final before = [
        for (var s = 0; s < 2; s++)
          for (var r = 0; r < rowsPerSection; r++)
            tester.element(
              find.text(title(s, r), skipOffstage: false, findRichText: true),
            ),
      ];
      tester.view.physicalSize = tester.view.physicalSize / 2;
      await tester.pump();
      tester.view.resetPhysicalSize();
      await tester.pump();
      final after = [
        for (var s = 0; s < 2; s++)
          for (var r = 0; r < rowsPerSection; r++)
            tester.element(
              find.text(title(s, r), skipOffstage: false, findRichText: true),
            ),
      ];
      for (final (i, element) in after.indexed) {
        expect(identical(element, before[i]), isTrue, reason: '第 $i 列被重建');
      }
    });

    testWidgets('換場後才多出來的列（打開開關多出的）直接建，不排隊', (tester) async {
      final extra = ValueNotifier<bool>(false);
      addTearDown(extra.dispose);
      await open(
        tester,
        page: ValueListenableBuilder<bool>(
          valueListenable: extra,
          builder: (context, shown, _) =>
              page(extra: [if (shown) const GroupedRow(title: '多出來的列')]),
        ),
      );
      await tester.pumpAndSettle();
      extra.value = true;
      await tester.pump();
      expect(find.text('多出來的列', findRichText: true), findsOneWidget);
    });
  });

  group('第一項的位置', () {
    Future<double> topUnder(
      WidgetTester tester, {
      PreferredSizeWidget? appBar,
      bool extend = true,
    }) async {
      late double top;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 32)),
            child: Scaffold(
              extendBodyBehindAppBar: extend,
              appBar: appBar,
              body: Builder(
                builder: (context) {
                  top = GroupedListView.topOf(context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      return top;
    }

    testWidgets('內容延伸到玻璃頁首底下：接在頁首的淡出下面', (tester) async {
      final top = await topUnder(
        tester,
        appBar: const GlassNavHeader(title: '標題'),
      );
      expect(
        top,
        32 + AppGlass.headerToolbarHeight + AppGlass.headerFadeHeight,
      );
    });

    testWidgets('一般頁首、沒延伸到頁首底下、沒有頁首：照系統留的內距，不會是負的', (tester) async {
      expect(
        await topUnder(tester, appBar: AppBar(title: const Text('標題'))),
        32 + kToolbarHeight,
      );
      expect(
        await topUnder(
          tester,
          appBar: const GlassNavHeader(title: '標題'),
          extend: false,
        ),
        0,
      );
      expect(await topUnder(tester), 32);
    });

    test('只有第一項是一組時換成上方間距 0，其他項照舊', () {
      const second = GroupedSection(children: []);
      final items = GroupedListView.itemsOf(const [
        GroupedSection(children: []),
        second,
      ]);
      expect((items[0] as GroupedSection).topGap, 0);
      expect(identical(items[1], second), isTrue);
      final padded = GroupedListView.itemsOf(const [
        Padding(padding: EdgeInsets.only(top: 4), child: SizedBox()),
      ]);
      expect(padded.single, isA<Padding>());
    });
  });
}
