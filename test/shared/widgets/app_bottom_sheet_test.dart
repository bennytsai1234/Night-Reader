import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';

void main() {
  testWidgets('a bottom sheet sits above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AppBottomSheet.show<void>(
                context: context,
                title: '面板',
                children: [
                  for (var i = 0; i < 12; i++)
                    TextField(key: ValueKey(i), decoration: null),
                ],
              ),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pumpAndSettle();

    // 面板內容（外框不含墊高的鍵盤內距）整個在鍵盤上方。
    final content = tester.getRect(
      find
          .descendant(
            of: find.byType(AppBottomSheet),
            matching: find.byType(SafeArea),
          )
          .first,
    );
    expect(content.bottom, lessThanOrEqualTo(800 - 320));

    // 最後一個輸入框捲進可視範圍後，整個在鍵盤上方。
    await tester.ensureVisible(find.byKey(const ValueKey(11)));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey(11))).bottom,
      lessThanOrEqualTo(800 - 320),
    );
  });

  testWidgets('a long source name does not squeeze out the chapter title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.dark),
        home: Scaffold(
          body: Stack(
            children: [
              ReaderV2TopMenu(
                controlsVisible: true,
                bookName: '書名',
                chapterTitle: '第一章 開始',
                chapterUrl: 'https://s.example/1',
                originName: '🔥 筆趣閣（優+發現）[2024.05 更新] 精品書源合集',
                showReadTitleAddition: true,
                onBack: () {},
                onMore: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('第一章 開始')).width, greaterThan(40));
  });
}
