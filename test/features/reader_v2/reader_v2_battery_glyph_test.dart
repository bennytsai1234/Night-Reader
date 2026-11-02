import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_battery_glyph.dart';

/// 頁首頁尾的電池：大小照資訊列的字級，數字在電池裡時外框包住數字，
/// 充電中多一個閃電。
void main() {
  Future<void> pump(WidgetTester tester, Widget glyph) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 11),
          child: glyph,
        ),
      ),
    ),
  );

  testWidgets('the battery grows with the info font size', (tester) async {
    Future<Size> sizeAt(double fontSize) async {
      await pump(
        tester,
        ReaderV2BatteryGlyph(
          key: const Key('battery'),
          percent: 82,
          charging: false,
          color: Colors.black,
          fontSize: fontSize,
        ),
      );
      return tester.getSize(find.byKey(const Key('battery')));
    }

    final small = await sizeAt(11);
    final large = await sizeAt(16);
    expect(large.width / small.width, closeTo(16 / 11, 0.01));
    expect(large.height / small.height, closeTo(16 / 11, 0.01));
    // 預設字級時放得進頁尾那一列（高 16）。
    expect(small.height, lessThanOrEqualTo(16));
    expect(find.byIcon(Icons.bolt), findsNothing);
  });

  testWidgets('the number sits inside the battery outline', (tester) async {
    await pump(
      tester,
      const ReaderV2BatteryGlyph(
        key: Key('battery'),
        percent: 82,
        charging: false,
        color: Colors.black,
        fontSize: 11,
        label: '82',
      ),
    );
    final outline = tester.getRect(find.byKey(const Key('battery')));
    final number = tester.getRect(find.text('82'));
    expect(outline.contains(number.topLeft), isTrue);
    expect(outline.contains(number.bottomRight), isTrue);
    // 預設字級時放得進頁尾那一列（高 16）。
    expect(outline.height, lessThanOrEqualTo(16));
  });

  testWidgets('charging adds a bolt next to the battery', (tester) async {
    await pump(
      tester,
      const ReaderV2BatteryGlyph(
        percent: 100,
        charging: true,
        color: Colors.black,
        fontSize: 11,
        label: '100',
      ),
    );
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });
}
