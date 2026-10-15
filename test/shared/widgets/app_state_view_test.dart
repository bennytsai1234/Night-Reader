import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';

void main() {
  testWidgets('a two-line description splits evenly instead of leaving one '
      'character on the last line', (tester) async {
    // 測試字型每個字一樣寬（字級 14 就是 14 寬）；說明 15 個字，照最大寬度排
    // 會是 14 + 1。
    const description = '開始閱讀一本書之後這裡會顯示時間';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 14 * 14 + 2 * 32,
              child: AppStateView(
                icon: Icons.history,
                title: '尚無閱讀紀錄',
                description: description,
                primaryAction: AppStateAction(label: '重試', onPressed: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(description),
    );
    final lines = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: description.length),
    );
    final rows = <double, double>{};
    for (final box in lines) {
      rows.update(
        box.top,
        (w) => w + box.right - box.left,
        ifAbsent: () => box.right - box.left,
      );
    }
    expect(rows, hasLength(2));
    final widths = rows.values.toList()..sort();
    expect(widths.first, greaterThanOrEqualTo(widths.last - 14));
  });

  testWidgets('the primary action is a filled button in every tone', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppStateView(
            icon: Icons.explore,
            title: '沒有書源',
            primaryAction: AppStateAction(label: '匯入', onPressed: () {}),
            secondaryAction: AppStateAction(label: '說明', onPressed: () {}),
          ),
        ),
      ),
    );
    expect(find.widgetWithText(FilledButton, '匯入'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '說明'), findsOneWidget);
  });
}
