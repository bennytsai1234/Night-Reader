import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

void main() {
  /// 記下送到平台的觸感回饋種類。
  List<String> recordHaptics(WidgetTester tester) {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    return haptics;
  }

  const selection = 'HapticFeedbackType.selectionClick';

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );

  testWidgets('切換開關與點整列開關列都會喀一聲', (tester) async {
    final haptics = recordHaptics(tester);
    await tester.pumpWidget(
      host(
        Column(
          children: [
            GroupedSwitch(value: false, onChanged: (_) {}),
            GroupedSwitchRow(title: '自動翻頁', value: false, onChanged: (_) {}),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(GroupedSwitch).first);
    await tester.tap(find.text('自動翻頁'));

    expect(haptics, [selection, selection]);
  });

  testWidgets('分段只在選項改變時喀一聲', (tester) async {
    final haptics = recordHaptics(tester);
    var selected = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => GlassSegmented<int>(
            segments: const [GlassSegment(0, '一'), GlassSegment(1, '二')],
            selected: selected,
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
    );

    await tester.tap(find.text('一'));
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);

    await tester.tap(find.text('二'));
    await tester.pumpAndSettle();
    expect(haptics, [selection]);
  });

  Future<List<double>> pumpStepper(WidgetTester tester, double value) async {
    final changes = <double>[];
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => NumberStepperRow(
            label: '字號',
            value: value,
            min: 14,
            max: 40,
            step: 1,
            onChanged: (next) {
              changes.add(next);
              setState(() => value = next);
            },
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('步進鈕每點一下喀一聲，到上限後不再回饋', (tester) async {
    final haptics = recordHaptics(tester);
    await pumpStepper(tester, 39);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();

    expect(haptics, [selection]);
  });

  testWidgets('長按連續步進只在開始與碰到上限時各喀一聲', (tester) async {
    final haptics = recordHaptics(tester);
    final changes = await pumpStepper(tester, 30);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.add_rounded)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 300));
    // 走到一半：只有開始那一聲。
    expect(changes.length, greaterThan(2));
    expect(haptics, [selection]);

    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();

    expect(changes.last, 40);
    expect(haptics, [selection, selection]);
  });
}
