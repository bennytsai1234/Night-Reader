import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('is a 40x24 track', (tester) async {
    await tester.pumpWidget(
      host(GroupedSwitch(value: true, onChanged: (_) {})),
    );

    expect(tester.getSize(find.byType(GroupedSwitch)), const Size(40, 24));
  });

  testWidgets('a tap toggles it', (tester) async {
    bool? changed;
    await tester.pumpWidget(
      host(GroupedSwitch(value: false, onChanged: (v) => changed = v)),
    );

    await tester.tap(find.byType(GroupedSwitch));

    expect(changed, isTrue);
  });

  testWidgets('a disabled switch is announced as disabled', (tester) async {
    await tester.pumpWidget(host(const GroupedSwitch(value: false)));

    expect(
      tester.getSemantics(find.byType(GroupedSwitch)),
      matchesSemantics(hasToggledState: true, hasEnabledState: true),
    );
  });

  testWidgets('a switch row is as tall as a plain row', (tester) async {
    await tester.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GroupedRow(title: '一般列'),
            GroupedSwitchRow(title: '開關列', value: true, onChanged: (_) {}),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(GroupedSwitchRow)).height,
      tester.getSize(find.byType(GroupedRow).first).height,
    );
  });
}
