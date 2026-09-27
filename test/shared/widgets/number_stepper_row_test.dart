import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

void main() {
  group('NumberStepperRow.snap', () {
    test('aligns to step grid without floating point drift', () {
      expect(NumberStepperRow.snap(1.2 + 0.1, 1.2, 3.0, 0.1), 1.3);
      expect(NumberStepperRow.snap(17.38, 14, 40, 1), 17);
      expect(NumberStepperRow.snap(0.123, 0.02, 0.45, 0.01), 0.12);
    });

    test('clamps to range', () {
      expect(NumberStepperRow.snap(99, 14, 40, 1), 40);
      expect(NumberStepperRow.snap(-1, 0, 3, 0.1), 0);
      expect(NumberStepperRow.snap(double.nan, 0, 3, 0.1), 0);
    });
  });

  Future<List<double>> pumpRow(
    WidgetTester tester, {
    required double value,
    double min = 14,
    double max = 40,
    double step = 1,
    int fractionDigits = 0,
    double displayScale = 1,
    String unit = '',
  }) async {
    final changes = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder:
                (context, setState) => NumberStepperRow(
                  label: '字號',
                  value: value,
                  min: min,
                  max: max,
                  step: step,
                  fractionDigits: fractionDigits,
                  displayScale: displayScale,
                  unit: unit,
                  onChanged: (next) {
                    changes.add(next);
                    setState(() => value = next);
                  },
                ),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('plus and minus step by one unit', (tester) async {
    final changes = await pumpRow(tester, value: 18);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(find.text('19'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    expect(changes, [19, 18, 17]);
  });

  testWidgets('disables stepping at bounds', (tester) async {
    final changes = await pumpRow(tester, value: 40);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(changes, isEmpty);
    final plus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.add_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(plus.onPressed, isNull);
  });

  testWidgets('long press repeats until released', (tester) async {
    final changes = await pumpRow(tester, value: 18);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.add_rounded)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
    final countAfterRelease = changes.length;
    expect(countAfterRelease, greaterThan(2));
    expect(changes.first, 19);
    await tester.pump(const Duration(milliseconds: 500));
    expect(changes.length, countAfterRelease);
  });

  testWidgets('tapping the value accepts typed input', (tester) async {
    final changes = await pumpRow(tester, value: 18);
    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '24');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(changes, [24]);
    expect(find.text('24'), findsOneWidget);
  });

  testWidgets('typed input outside range shows error and keeps dialog', (
    tester,
  ) async {
    final changes = await pumpRow(tester, value: 18);
    await tester.tap(find.text('18'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '99');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text('超出範圍 14–40'), findsOneWidget);
  });

  testWidgets('percent display converts typed value back to storage unit', (
    tester,
  ) async {
    final changes = await pumpRow(
      tester,
      value: 0.12,
      min: 0.02,
      max: 0.45,
      step: 0.01,
      displayScale: 100,
      unit: '%',
    );
    expect(find.text('12%'), findsOneWidget);
    await tester.tap(find.text('12%'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '45');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(changes, [0.45]);
  });
}
