import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/navigation/expand_route.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

void main() {
  const button = Rect.fromLTWH(700, 500, 64, 64);

  testWidgets('the page grows out of the button and shrinks back into it', (
    tester,
  ) async {
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) {
            home = context;
            return const Scaffold(body: Text('主頁'));
          },
        ),
      ),
    );

    Navigator.push(
      home,
      ExpandFromRectRoute<void>(
        sourceRect: button,
        builder: (_) => const Scaffold(body: Center(child: Text('搜尋頁'))),
      ),
    );

    Rect clip() => tester
        .widget<ClipRRect>(
          find.ancestor(of: find.text('搜尋頁'), matching: find.byType(ClipRRect)),
        )
        .clipper!
        .getClip(const Size(800, 600))
        .outerRect;

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // 展開中：範圍比整頁小、包住按鈕。
    final growing = clip();
    expect(growing.width, lessThan(800));
    expect(growing.contains(button.center), isTrue);

    await tester.pumpAndSettle();
    expect(find.text('搜尋頁'), findsOneWidget);
    expect(find.text('主頁'), findsNothing);

    // 返回鍵：縮回按鈕後回到主頁。
    Navigator.pop(tester.element(find.text('搜尋頁')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(clip().width, lessThan(800));
    await tester.pumpAndSettle();
    expect(find.text('搜尋頁'), findsNothing);
    expect(find.text('主頁'), findsOneWidget);
  });
}
