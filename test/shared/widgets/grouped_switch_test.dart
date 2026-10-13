import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('draws a 40x24 track inside a tap target of at least 44', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(GroupedSwitch(value: true, onChanged: (_) {})),
    );

    final target = tester.getSize(find.byType(GroupedSwitch));
    expect(target.width, greaterThanOrEqualTo(44));
    expect(target.height, greaterThanOrEqualTo(44));
    final track = tester.getSize(
      find.descendant(
        of: find.byType(GroupedSwitch),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(track, const Size(40, 24));
  });

  testWidgets('a tap anywhere in the target toggles it', (tester) async {
    bool? changed;
    await tester.pumpWidget(
      host(GroupedSwitch(value: false, onChanged: (v) => changed = v)),
    );

    final rect = tester.getRect(find.byType(GroupedSwitch));
    // 軌道靠右；點左緣多出來的點擊範圍也要有效。
    await tester.tapAt(rect.centerLeft + const Offset(1, 0));

    expect(changed, isTrue);
  });

  testWidgets('a disabled switch is announced as disabled', (tester) async {
    await tester.pumpWidget(host(const GroupedSwitch(value: false)));

    expect(
      tester.getSemantics(find.byType(GroupedSwitch)),
      matchesSemantics(hasToggledState: true, hasEnabledState: true),
    );
  });
}
