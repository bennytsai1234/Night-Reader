import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/features/about/crash_log_page.dart';
import 'package:night_reader/features/about/log_page.dart';
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
    Future<void> Function(String path)? shareFile,
  }) async {
    // 頁面一掛上就開始讀檔：在真實時間裡掛上，讀檔才跑得完。
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: CrashLogPage(
            writeClipboard: writeClipboard,
            shareFile: shareFile,
          ),
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

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('複製日誌'));
    await tester.pump();
    expect(copied!.length, greaterThanOrEqualTo(fullCrashLogsMinChars));
    expect(copied, contains('錯誤 #49'));
    expect(copied, contains('錯誤 #0\n'));
    expect(
      copied!.indexOf('錯誤 #49'),
      lessThan(copied!.indexOf('錯誤 #0\n')),
      reason: '從新到舊',
    );
  });

  testWidgets('sharing writes every log into one text file', (tester) async {
    await tester.runAsync(() => seedFullCrashLogs(directory, count: 3));
    String? shared;
    await openPage(
      tester,
      shareFile: (path) async => shared = File(path).readAsStringSync(),
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享日誌檔'));
    for (var i = 0; i < 100 && shared == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(shared, isNotNull);
    expect(shared, contains('錯誤 #2'));
    expect(shared, contains('錯誤 #0\n'));
    expect(
      shared,
      (await tester.runAsync(CrashHandler.readLogs))!.join(),
      reason: '和頁面上的整份一樣',
    );
  });

  testWidgets('leaving while the file is being written does not share it', (
    tester,
  ) async {
    await tester.runAsync(() => seedFullCrashLogs(directory, count: 3));
    var shared = 0;
    await openPage(tester, shareFile: (_) async => shared++);

    // 選單在真實時間裡打開、點選：分享接著寫檔，寫檔才會真的跑完，看得到
    // 寫完之後還分不分享。
    await tester.runAsync(() => tester.tap(find.byTooltip('更多')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('分享日誌檔')));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(shared, 0);
  });

  testWidgets('copying a selection across pieces keeps their line breaks', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
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
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const Scaffold(
          body: LogTextView(chunks: ['alpha\n', '\nbeta\n', 'gamma']),
        ),
      ),
    );
    // 片尾的換行不畫成多出來的一行。
    expect(find.byType(RichText), findsNWidgets(3));
    expect(
      tester.getSize(find.text('alpha')).height,
      tester.getSize(find.text('gamma')).height,
    );

    await tester.tap(find.text('alpha'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    expect(copied, 'alpha\n\nbeta\ngamma');
  });

  testWidgets('logs already in hand still wait for the page to finish '
      'sliding in', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: const Scaffold(),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CrashLogPage(readLogs: () => SynchronousFuture(const ['現成的日誌'])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('現成的日誌'), findsNothing, reason: '換頁還在播');
    await tester.pumpAndSettle();
    expect(find.text('現成的日誌'), findsOneWidget);
  });
}
