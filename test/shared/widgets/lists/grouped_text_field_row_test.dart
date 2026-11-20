import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';

void main() {
  Future<GroupedTextFieldRow> pumpRow(
    WidgetTester tester,
    GroupedTextFieldRow row,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(body: Center(child: row)),
      ),
    );
    return row;
  }

  double centerY(WidgetTester tester, Finder finder) =>
      tester.getRect(finder).center.dy;

  testWidgets('單行輸入框被右側按鈕撐高時，標籤、字與按鈕都在列的中線上', (tester) async {
    await pumpRow(
      tester,
      GroupedTextFieldRow(
        label: '金鑰',
        controller: TextEditingController(text: 'sk-abcdef'),
        obscureText: true,
        suffix: PasswordRevealButton(revealed: false, onPressed: () {}),
      ),
    );
    final row = centerY(tester, find.byType(GroupedTextFieldRow));
    expect(
      centerY(tester, find.text('金鑰')),
      moreOrLessEquals(row, epsilon: 0.5),
    );
    expect(
      centerY(tester, find.byType(EditableText)),
      moreOrLessEquals(row, epsilon: 0.5),
    );
    expect(
      centerY(tester, find.byType(Icon)),
      moreOrLessEquals(row, epsilon: 0.5),
    );
  });

  testWidgets('單行輸入框列的骨架和內容一樣：標籤與字的位置對得上', (tester) async {
    final row = await pumpRow(
      tester,
      GroupedTextFieldRow(
        label: '金鑰',
        controller: TextEditingController(text: 'sk-abcdef'),
        obscureText: true,
        suffix: PasswordRevealButton(revealed: false, onPressed: () {}),
      ),
    );
    final box = tester.getRect(find.byType(GroupedTextFieldRow));
    final shape = row.skeletonShape(
      tester.element(find.byType(GroupedTextFieldRow)),
      width: box.width,
    );
    expect(shape.height, moreOrLessEquals(box.height, epsilon: 0.5));
    final label = tester.getRect(find.text('金鑰')).shift(-box.topLeft);
    final field = tester.getRect(find.byType(EditableText)).shift(-box.topLeft);
    final markCenters = [for (final mark in shape.marks) mark.rect.center.dy];
    expect(
      markCenters.any((y) => (y - label.center.dy).abs() < 0.5),
      isTrue,
      reason: '骨架裡沒有和標籤同一條中線的字條：$markCenters／標籤 ${label.center.dy}',
    );
    expect(
      markCenters.any((y) => (y - field.center.dy).abs() < 0.5),
      isTrue,
      reason: '骨架裡沒有和輸入框的字同一條中線的字條：$markCenters／字 ${field.center.dy}',
    );
  });

  testWidgets('多行輸入框的標籤對齊第一行', (tester) async {
    await pumpRow(
      tester,
      GroupedTextFieldRow(
        label: '備註',
        controller: TextEditingController(text: '一\n二\n三'),
        maxLines: null,
      ),
    );
    final label = tester.getRect(find.text('備註'));
    final field = tester.getRect(find.byType(EditableText));
    expect(label.top, moreOrLessEquals(field.top, epsilon: 0.5));
  });
}
