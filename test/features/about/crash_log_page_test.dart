import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/features/about/crash_log_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../../support/crash_logs.dart';

/// 畫面上排過版的每一段字有幾個字。
List<int> _laidOutTextLengths(WidgetTester tester) => [
  for (final element in find.byType(RichText).evaluate())
    (element.renderObject! as RenderParagraph).text.toPlainText().length,
  for (final element in find.byType(EditableText).evaluate())
    (element.widget as EditableText).controller.text.length,
];

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('crash_log_page');
    CrashHandler.logDirectoryForTesting = () async => directory;
  });

  tearDown(() async {
    CrashHandler.resetLogDirectoryForTesting();
    await directory.delete(recursive: true);
  });

  Future<void> openPage(
    WidgetTester tester, {
    Future<void> Function(String text)? writeClipboard,
  }) async {
    // 頁面一掛上就開始讀檔：在真實時間裡掛上，讀檔才跑得完。
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: CrashLogPage(writeClipboard: writeClipboard),
        ),
      ),
    );
    for (var i = 0; i < 200; i++) {
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump();
  }

  testWidgets('a full folder of crash logs is laid out a little at a time, '
      'and copying still takes every log', (tester) async {
    await tester.runAsync(() => seedFullCrashLogs(directory));
    String? copied;
    await openPage(tester, writeClipboard: (text) async => copied = text);

    // 最新的一份在最上面。
    expect(find.textContaining('錯誤 #49'), findsOneWidget);
    // 一次排版的字有上限：50 份約 100 萬字放在同一段字裡，排一次要好幾秒。
    final lengths = _laidOutTextLengths(tester);
    expect(lengths, isNotEmpty);
    expect(lengths.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(2000));

    await tester.tap(find.byTooltip('複製日誌'));
    await tester.pump();
    expect(copied, contains('錯誤 #49'));
    expect(copied, contains('錯誤 #0\n'));
    expect(
      copied!.indexOf('錯誤 #49'),
      lessThan(copied!.indexOf('錯誤 #0\n')),
      reason: '從新到舊',
    );
  });
}
