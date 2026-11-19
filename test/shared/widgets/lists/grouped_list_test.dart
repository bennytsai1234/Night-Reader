import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
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
                              translateHeader: false,
                              header: '書名',
                              children: [GroupedRow(title: '書籤')],
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
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(GroupedListSkeleton), findsOneWidget);
      expect(find.text('風格'), findsNothing, reason: '進場中不建列');

      await tester.pumpAndSettle();
      expect(find.text('風格'), findsOneWidget);
      expect(find.byType(GroupedListSkeleton), findsNothing, reason: '換好就拿掉');
    });
  });
}
