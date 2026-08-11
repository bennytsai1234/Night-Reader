import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/source_manager/widgets/rule_text_field.dart';

void main() {
  testWidgets('helper appends text when the controller has no selection', (
    tester,
  ) async {
    final controller = TextEditingController(text: '既有規則');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RuleTextField(controller: controller, label: '列表規則'),
        ),
      ),
    );

    expect(find.byTooltip('開啟列表規則小幫手'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('開啟列表規則小幫手')), const Size(48, 48));
    final semantics = tester.ensureSemantics();
    try {
      expect(
        find.semantics.byLabel('開啟列表規則小幫手'),
        isSemantics(label: '開啟列表規則小幫手', isButton: true, hasTapAction: true),
      );
    } finally {
      semantics.dispose();
    }
    await tester.tap(find.byTooltip('開啟列表規則小幫手'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CSS 選擇器 @css:'));
    await tester.pumpAndSettle();

    expect(controller.text, '既有規則@css:');
    expect(controller.selection.baseOffset, controller.text.length);
    expect(tester.takeException(), isNull);
  });
}
