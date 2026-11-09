import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:night_reader/features/source_manager/ai_repair/ai_repair_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

const _service = (baseUrl: 'https://ai.example/v1', apiKey: 'k', model: 'm');

SourceCheckIsolateResult _checked(BookSource source) {
  final healthy = source.ruleContent?.content == 'class.txt@text';
  return SourceCheckIsolateResult(
    stage: healthy ? 'done' : 'content',
    message: healthy ? '校驗成功' : '正文為空',
    isHealthy: healthy,
    updatedSourceJson: source.toJson(),
    logs: const [],
  );
}

const _probe = SourceProbeReport(
  logs: [(40, '︽正文頁解析完成 (內容長度: 3214)'), (1000, '︽解析完成')],
  requests: ['  ← https://site.example/c/1 200：…'],
);

/// 頁上有轉圈時 pumpAndSettle 等不完，改成推進一段時間。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  Future<void> pumpPage(WidgetTester tester, AiRepairSession session) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: AiRepairPage(session: session),
      ),
    );
  }

  testWidgets('steps fill in as the repair goes, then 完成', (tester) async {
    final reply = Completer<String>();
    final session = AiRepairSession(
      sources: [
        BookSource(
          bookSourceUrl: 'https://site.example',
          bookSourceName: '筆趣閣',
          ruleContent: ContentRule(content: 'id.old@text'),
        ),
      ],
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (_, _) async => _probe,
      ask: (_, _) => reply.future,
      apply: (_, _) async {},
      secrets: (_) async => const {},
      backups: AiRepairBackups(),
    );

    await pumpPage(tester, session);
    await _settle(tester);

    expect(find.text('AI 修復 · 筆趣閣'), findsOneWidget);
    expect(find.text('校驗原本的書源'), findsOneWidget);
    expect(find.text('第 1 輪'), findsOneWidget);
    expect(find.text('AI 回覆中…'), findsOneWidget);
    expect(find.text('停止'), findsOneWidget);
    expect(find.text('送到 ai.example · m'), findsOneWidget);

    reply.complete(
      jsonEncode({
        'action': 'submit',
        'source': {
          'ruleContent': {'content': 'class.txt@text'},
        },
        'note': '正文在 div.txt',
      }),
    );
    await _settle(tester);

    expect(find.text('校驗修好的書源'), findsOneWidget);
    expect(find.text('修好了'), findsOneWidget);
    expect(find.text('AI：正文在 div.txt'), findsOneWidget);
    expect(find.text('還原改前的版本'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('停止'), findsNothing);
  });

  testWidgets('the clipboard way waits for a paste on the same page', (
    tester,
  ) async {
    final copied = <String>[];
    final session = AiRepairSession(
      sources: [
        BookSource(
          bookSourceUrl: 'https://site.example',
          bookSourceName: '筆趣閣',
          ruleContent: ContentRule(content: 'id.old@text'),
        ),
      ],
      service: null,
      check: (source, _) async => _checked(source),
      probe: (_, _) async => _probe,
      apply: (_, _) async {},
      secrets: (_) async => const {},
      copy: (text) async => copied.add(text),
      backups: AiRepairBackups(),
    );

    await pumpPage(tester, session);
    await _settle(tester);

    expect(find.text('已複製給 AI'), findsOneWidget);
    expect(copied, hasLength(1));
    await tester.enterText(
      find.byType(TextField),
      '{"bookSourceUrl":"x","ruleContent":{"content":"class.txt@text"}}',
    );
    await tester.tap(find.text('校驗並套用'));
    await _settle(tester);

    expect(find.text('修好了'), findsOneWidget);
    expect(find.text('校驗通過，已套用。'), findsOneWidget);
  });
}
