import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/features/reader/features/replace_rule/reader_replace_rule_editor_sheet.dart';

void main() {
  testWidgets('a rule filled in from the selection opens as a new rule with '
      'the text and the paragraph to test on; saving keeps it plain text for '
      'every book', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    ReplaceRule? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ReaderReplaceRuleEditorSheet.show(
                context,
                rule: ReplaceRule(
                  name: '城門',
                  group: '選字替換',
                  pattern: '城門',
                  isRegex: false,
                ),
                testSample: '天色漸暗，城門即將關閉。',
                onSave: (rule) async => saved = rule,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('新增規則'), findsOneWidget);
    expect(find.text('天色漸暗，城門即將關閉。'), findsOneWidget);
    final replacement = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.controller?.text == '' &&
          widget.enabled != false,
    );
    expect(replacement, findsWidgets);

    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(saved?.pattern, '城門');
    expect(saved?.group, '選字替換');
    expect(saved?.isRegex, isFalse);
    expect(saved?.scope ?? '', isEmpty, reason: '套用到所有書');
  });

  testWidgets('a rule that backtracks for a long time is stopped at its time '
      'limit without freezing the sheet, and the next edit replaces the '
      'result', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final sample = '${'a' * 30}!';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ReaderReplaceRuleEditorSheet.show(
                context,
                rule: ReplaceRule(
                  name: '回溯',
                  pattern: r'^(a+)+$',
                  replacement: 'x',
                  timeoutMillisecond: 200,
                ),
                testSample: sample,
                onSave: (_) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 試跑在另一個 isolate：等它開始套用規則，再讓期限到。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('規則「回溯」執行超過 200 毫秒，已停止'), findsOneWidget);

    // 改逾時：還在跑的那次作廢，照新的期限重跑。
    final timeout = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == '200',
    );
    await tester.enterText(timeout, '100');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('規則「回溯」執行超過 100 毫秒，已停止'), findsOneWidget);

    final input = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == sample,
    );
    await tester.enterText(input, 'aaa');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    // 替換內容的輸入框也是 x，只看結果區的字。
    expect(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == 'x'),
      findsOneWidget,
    );
    expect(find.text('規則「回溯」執行超過 200 毫秒，已停止'), findsNothing);
  });

  testWidgets('按了儲存、還沒存好就關掉編輯畫面：存好之後呼叫的一方才收到結果', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final writing = Completer<void>();
    var saved = false;
    bool? savedWhenClosed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                // 同閱讀器的「新增規則」：關掉之後看存了沒，存了才重載正文。
                await ReaderReplaceRuleEditorSheet.show(
                  context,
                  rule: ReplaceRule(name: '城門', pattern: '城門', isRegex: false),
                  onSave: (rule) async {
                    await writing.future;
                    saved = true;
                  },
                );
                savedWhenClosed = saved;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('儲存'));
    await tester.pump();

    // 資料庫還在寫：按返回關掉編輯畫面。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('新增規則'), findsNothing);
    expect(savedWhenClosed, isNull, reason: '還沒存好，呼叫的一方還在等');

    writing.complete();
    await tester.pumpAndSettle();
    expect(savedWhenClosed, isTrue);
  });
}
