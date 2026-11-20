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
