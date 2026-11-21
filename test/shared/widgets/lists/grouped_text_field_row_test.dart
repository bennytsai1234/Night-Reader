import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';

void main() {
  Future<void> pumpRow(
    WidgetTester tester,
    Widget row, {
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: Center(child: row)),
        ),
      ),
    );
  }

  Rect rowRect(WidgetTester tester) =>
      tester.getRect(find.byType(GroupedTextFieldRow));

  /// 列裡某個元件的範圍，以列的左上角為原點。
  Rect local(WidgetTester tester, Finder finder) =>
      tester.getRect(finder).shift(-rowRect(tester).topLeft);

  /// 骨架裡左緣落在 [left]～[right] 之間的形狀（標籤欄、輸入欄、按鈕各一欄）。
  List<Rect> marksIn(GroupedItemShape shape, double left, double right) => [
    for (final mark in shape.marks)
      if (mark.rect.left >= left - 0.5 && mark.rect.left < right) mark.rect,
  ];

  GroupedItemShape skeletonOf(WidgetTester tester) {
    final element = tester.element(find.byType(GroupedTextFieldRow));
    return (element.widget as GroupedTextFieldRow).skeletonShape(
      element,
      width: rowRect(tester).width,
    );
  }

  GroupedTextFieldRow keyRow({String? errorText}) => GroupedTextFieldRow(
    label: '金鑰',
    controller: TextEditingController(text: 'sk-abcdef'),
    obscureText: true,
    errorText: errorText,
    suffix: PasswordRevealButton(revealed: false, onPressed: () {}),
  );

  testWidgets('單行輸入框被右側按鈕撐高時，標籤、字與按鈕都在列的中線上', (tester) async {
    await pumpRow(tester, keyRow());
    final row = rowRect(tester).height / 2;
    for (final part in [
      find.text('金鑰'),
      find.byType(EditableText),
      find.byType(Icon),
    ]) {
      expect(
        local(tester, part).center.dy,
        moreOrLessEquals(row, epsilon: 0.5),
      );
    }
  });

  testWidgets('單行輸入框列的骨架：標籤、字、按鈕各一欄，位置和內容一樣', (tester) async {
    await pumpRow(tester, keyRow());
    final shape = skeletonOf(tester);
    expect(
      shape.height,
      moreOrLessEquals(rowRect(tester).height, epsilon: 0.5),
    );
    final label = local(tester, find.text('金鑰'));
    final field = local(tester, find.byType(EditableText));
    final icon = local(tester, find.byType(Icon));
    const labelLeft = AppGrouped.rowPadding;
    const fieldLeft = AppGrouped.rowPadding + 96;
    final labelMarks = marksIn(shape, labelLeft, fieldLeft);
    final fieldMarks = marksIn(shape, fieldLeft, icon.left - 1);
    final iconMarks = marksIn(shape, icon.left - 1, double.infinity);
    expect(labelMarks, hasLength(1));
    expect(fieldMarks, hasLength(1));
    expect(iconMarks, hasLength(1));
    expect(
      labelMarks.single.center.dy,
      moreOrLessEquals(label.center.dy, epsilon: 0.5),
    );
    expect(
      fieldMarks.single.center.dy,
      moreOrLessEquals(field.center.dy, epsilon: 0.5),
    );
    expect(
      iconMarks.single.center.dy,
      moreOrLessEquals(icon.center.dy, epsilon: 0.5),
    );
  });

  testWidgets('單行輸入框出現錯誤訊息時，標籤仍和字同一條中線', (tester) async {
    await pumpRow(tester, keyRow(errorText: '金鑰格式不對'));
    final label = local(tester, find.text('金鑰'));
    final field = local(tester, find.byType(EditableText));
    expect(label.center.dy, moreOrLessEquals(field.center.dy, epsilon: 0.5));
    expect(find.text('金鑰格式不對'), findsOneWidget, reason: '錯誤訊息排在輸入框下面');
    expect(local(tester, find.text('金鑰格式不對')).top, greaterThan(field.bottom));
  });

  testWidgets('大字級時標籤換成兩行：骨架和內容一樣高，標籤與字都置中', (tester) async {
    await pumpRow(
      tester,
      GroupedTextFieldRow(
        label: '書源分組名稱',
        controller: TextEditingController(text: '分組'),
      ),
      textScale: 2,
    );
    final label = local(tester, find.text('書源分組名稱'));
    final field = local(tester, find.byType(EditableText));
    expect(label.height, greaterThan(field.height), reason: '這個情境要讓標籤換行、比輸入框高');
    final shape = skeletonOf(tester);
    final height = rowRect(tester).height;
    expect(shape.height, moreOrLessEquals(height, epsilon: 0.5));
    expect(label.center.dy, moreOrLessEquals(height / 2, epsilon: 0.5));
    expect(field.center.dy, moreOrLessEquals(height / 2, epsilon: 0.5));
  });

  testWidgets('沒有標籤的單行輸入框：骨架的字條和提示字同一條中線', (tester) async {
    await pumpRow(tester, const GroupedTextFieldRow(hintText: '搜尋書源'));
    final hint = local(tester, find.text('搜尋書源'));
    final shape = skeletonOf(tester);
    expect(
      shape.height,
      moreOrLessEquals(rowRect(tester).height, epsilon: 0.5),
    );
    expect(shape.marks, hasLength(1));
    expect(
      shape.marks.single.rect.center.dy,
      moreOrLessEquals(hint.center.dy, epsilon: 0.5),
    );
  });

  testWidgets('多行輸入框不帶左欄標籤：框從列的內距起撐滿，骨架和內容一樣高', (tester) async {
    await pumpRow(
      tester,
      GroupedTextFieldRow(
        controller: TextEditingController(text: '一\n二\n三'),
        minLines: 3,
        maxLines: 3,
      ),
    );
    final field = local(tester, find.byType(EditableText));
    expect(field.left, moreOrLessEquals(AppGrouped.rowPadding, epsilon: 0.5));
    expect(
      skeletonOf(tester).height,
      moreOrLessEquals(rowRect(tester).height, epsilon: 0.5),
    );
    expect(
      () => GroupedTextFieldRow(label: '備註', maxLines: 3),
      throwsAssertionError,
      reason: '多行框的欄位名放在上面單獨一列',
    );
  });
}
