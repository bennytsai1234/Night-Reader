import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/about/licenses_page.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

void main() {
  testWidgets('lists the packages in order and opens a license', (
    tester,
  ) async {
    final licenses = StreamController<LicenseEntry>();
    await tester.pumpWidget(
      MaterialApp(home: LicensesPage(licenses: licenses.stream)),
    );
    await tester.pump();

    // 還在讀：骨架，不放轉圈。
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('正在載入開源許可證'), findsOneWidget);

    licenses
      ..add(const LicenseEntryWithLineBreaks(['zeta'], 'Zeta license'))
      ..add(
        const LicenseEntryWithLineBreaks([
          'Alpha',
          'zeta',
        ], 'Alpha license\n\nSecond paragraph'),
      );
    await licenses.close();
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<GroupedRow>(find.byType(GroupedRow))
        .map((row) => row.title)
        .toList();
    expect(titles, ['Alpha', 'zeta']);

    await tester.tap(find.text('zeta'));
    await tester.pumpAndSettle();

    expect(find.text('Zeta license'), findsOneWidget);
    expect(find.text('Alpha license\n\nSecond paragraph'), findsOneWidget);
  });
}
