import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/about/crash_log_page.dart';

void main() {
  testWidgets('loading 完成後顯示日誌並啟用複製', (tester) async {
    final readResult = Completer<String>();
    String? copiedText;

    await _pumpPage(
      tester,
      CrashLogPage(
        readLogs: () => readResult.future,
        writeClipboard: (text) async {
          copiedText = text;
        },
      ),
    );

    expect(find.bySemanticsLabel('正在載入崩潰日誌'), findsOneWidget);
    expect(_action(tester, '複製日誌').onPressed, isNull);
    expect(_action(tester, '清除日誌').onPressed, isNull);

    readResult.complete('stack trace');
    await tester.pump();

    expect(find.text('stack trace'), findsOneWidget);
    expect(_action(tester, '複製日誌').onPressed, isNotNull);

    await tester.tap(find.byTooltip('複製日誌'));
    await tester.pump();

    expect(copiedText, 'stack trace');
    expect(find.text('已複製至剪貼簿'), findsOneWidget);
  });

  testWidgets('空日誌顯示正式空狀態並停用操作', (tester) async {
    await _pumpPage(tester, CrashLogPage(readLogs: () async => '   '));
    await tester.pumpAndSettle();

    expect(find.text('目前沒有崩潰日誌'), findsOneWidget);
    expect(_action(tester, '複製日誌').onPressed, isNull);
    expect(_action(tester, '清除日誌').onPressed, isNull);
  });

  testWidgets('讀取失敗可重試並恢復為 loaded', (tester) async {
    var readCalls = 0;
    await _pumpPage(
      tester,
      CrashLogPage(
        readLogs: () async {
          if (readCalls++ == 0) throw StateError('read failed');
          return 'recovered log';
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('崩潰日誌載入失敗'), findsOneWidget);
    expect(find.textContaining('read failed'), findsOneWidget);

    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();

    expect(find.text('recovered log'), findsOneWidget);
    expect(_action(tester, '複製日誌').onPressed, isNotNull);
  });

  testWidgets('複製失敗提供回饋且不產生未處理例外', (tester) async {
    await _pumpPage(
      tester,
      CrashLogPage(
        readLogs: () async => 'stack trace',
        writeClipboard: (_) async => throw StateError('clipboard failed'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('複製日誌'));
    await tester.pump();

    expect(find.text('複製崩潰日誌失敗'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消清除不呼叫 clear，確認後重新載入空狀態', (tester) async {
    var logs = 'stack trace';
    var clearCalls = 0;
    await _pumpPage(
      tester,
      CrashLogPage(
        readLogs: () async => logs,
        clearLogs: () async {
          clearCalls++;
          logs = '';
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('清除日誌'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(clearCalls, 0);

    await tester.tap(find.byTooltip('清除日誌'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(clearCalls, 1);
    expect(find.text('目前沒有崩潰日誌'), findsOneWidget);
    expect(find.text('已清除崩潰日誌'), findsOneWidget);
  });

  testWidgets('清除失敗保留日誌並提供回饋', (tester) async {
    await _pumpPage(
      tester,
      CrashLogPage(
        readLogs: () async => 'stack trace',
        clearLogs: () async => throw StateError('clear failed'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('清除日誌'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清除'));
    await tester.pump();

    expect(find.text('stack trace'), findsOneWidget);
    expect(find.textContaining('清除崩潰日誌失敗'), findsOneWidget);
    expect(_action(tester, '清除日誌').onPressed, isNotNull);
  });

  testWidgets('讀取完成前離開頁面不再使用已 dispose 的 context', (tester) async {
    final readResult = Completer<String>();
    await _pumpPage(tester, CrashLogPage(readLogs: () => readResult.future));

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    readResult.complete('late log');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(WidgetTester tester, CrashLogPage page) {
  return tester.pumpWidget(MaterialApp(home: page));
}

IconButton _action(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == tooltip,
    ),
  );
}
