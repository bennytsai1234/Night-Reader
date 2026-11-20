import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass/header_scroll_fade.dart';

void main() {
  testWidgets('a title fades as it scrolls into the header and is gone '
      '${HeaderScrollFade.distance} past its bottom edge', (tester) async {
    const status = 24.0;
    // 頁首下緣：狀態列、工具列再加漸隱帶；清單從這裡開始。
    const start =
        status + AppGlass.headerToolbarHeight + AppGlass.headerFadeHeight;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: status),
            viewPadding: EdgeInsets.only(top: status),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.only(top: start),
            children: const [
              HeaderScrollFade(child: SizedBox(height: 40, child: Text('書名'))),
              SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    double opacity() => tester.widget<Opacity>(find.byType(Opacity)).opacity;

    expect(opacity(), 1);
    controller.jumpTo(HeaderScrollFade.distance / 2);
    await tester.pump();
    expect(opacity(), closeTo(0.5, 0.001));
    controller.jumpTo(HeaderScrollFade.distance);
    await tester.pump();
    expect(opacity(), 0);
    controller.jumpTo(0);
    await tester.pump();
    expect(opacity(), 1);
  });
}
