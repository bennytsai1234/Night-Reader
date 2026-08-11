import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';

void main() {
  testWidgets('header scales without overflow and close action is labelled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      const title = '這是一個用來驗證大字體與尾端操作排列的長標題';

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: AppBottomSheet(
                title: title,
                trailing: TextButton(onPressed: null, child: Text('完成')),
                children: const [Text('內容')],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('關閉'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel(title)),
        matchesSemantics(label: title, isHeader: true),
      );
    } finally {
      semantics.dispose();
    }
  });
}
