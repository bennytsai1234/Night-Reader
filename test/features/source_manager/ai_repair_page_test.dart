import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_repair_backups.dart';
import 'package:night_reader/core/ai_repair/ai_create_prompt.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/site_check.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:night_reader/features/source_manager/ai_repair/ai_repair_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';

import '../../support/fake_ai.dart';

const _service = (
  baseUrl: 'https://ai.example/v1',
  apiKey: 'k',
  model: 'm',
  effort: '',
);

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
  contentUsable: true,
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

  testWidgets('the four stages fill in as the repair goes, the AI rounds '
      'fold under 經過, then 完成', (tester) async {
    final reply = Completer<AiReply>();
    final session = AiRepairSession(
      source: BookSource(
        bookSourceUrl: 'https://site.example',
        bookSourceName: '筆趣閣',
        ruleContent: ContentRule(content: 'id.old@text'),
      ),
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (_, _, {start}) async => _probe,
      ask: (_, _) => reply.future,
      apply: (_, _) async {},
      secrets: (_) async => const {},
      backups: AiRepairBackups(),
    );

    await pumpPage(tester, session);
    await _settle(tester);

    expect(find.text('AI 修復 · 筆趣閣'), findsOneWidget);
    expect(find.text('校驗原本的書源'), findsOneWidget);
    expect(find.text('AI 修改規則'), findsOneWidget);
    expect(find.text('AI 回覆中…'), findsOneWidget);
    expect(find.text('校驗修好的書源'), findsOneWidget, reason: '還沒輪到的段也列著');
    expect(find.textContaining('輪'), findsNothing);
    expect(find.text('經過'), findsNothing, reason: '還沒有做完的步');
    expect(find.text('結束'), findsOneWidget);
    // 送到哪個服務是卡片裡的一列（ADR 0076）。
    expect(find.text('送到'), findsOneWidget);
    expect(find.text('ai.example · m'), findsOneWidget);

    reply.complete(
      fakeAiReply(
        jsonEncode({
          'action': 'submit',
          'patch': {
            'ruleContent': {'content': 'class.txt@text'},
          },
          'note': '正文在 div.txt',
        }),
      ),
    );
    await _settle(tester);

    expect(find.text('校驗修好的書源'), findsOneWidget);
    expect(find.text('1 步'), findsOneWidget);
    expect(find.text('AI 改了正文，交出'), findsOneWidget);
    expect(find.text('修好了'), findsOneWidget);
    expect(find.text('AI：正文在 div.txt'), findsOneWidget);
    expect(find.text('還原改前的版本'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('結束'), findsNothing);

    // 展開後一步一列，清單變長、下面的結果捲出畫面，所以結果先看。
    await tester.tap(find.text('經過'));
    await tester.pump();
    expect(find.text('AI 改了正文，交出'), findsNWidgets(2));
  });

  testWidgets('a hand-in the check turns back sends the AI back to work: '
      'the AI stage spins again and the check stage waits', (tester) async {
    final replies = [Completer<AiReply>(), Completer<AiReply>()];
    var asked = 0;
    final session = AiRepairSession(
      source: BookSource(
        bookSourceUrl: 'https://site.example',
        bookSourceName: '筆趣閣',
        ruleContent: ContentRule(content: 'id.old@text'),
      ),
      service: _service,
      check: (source, _) async => _checked(source),
      probe: (_, _, {start}) async => _probe,
      ask: (_, _) => replies[asked++].future,
      apply: (_, _) async {},
      secrets: (_) async => const {},
      backups: AiRepairBackups(),
    );

    await pumpPage(tester, session);
    await _settle(tester);
    // 交出的規則校驗不過：退回給 AI，再問一次。
    replies[0].complete(
      fakeAiReply(
        jsonEncode({
          'action': 'submit',
          'patch': {
            'ruleContent': {'content': 'class.wrong@text'},
          },
          'note': '正文在 div.wrong',
        }),
      ),
    );
    await _settle(tester);
    expect(asked, 2, reason: '退回後接著問 AI');

    Icon iconOf(String title) => tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(GroupedRow),
        ),
        matching: find.byType(Icon),
      ),
    );
    expect(find.text('1 步'), findsOneWidget, reason: '正在回覆的那一步不算經過');
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'AI 修改規則又在做',
    );
    expect(
      iconOf('校驗修好的書源').icon,
      Icons.radio_button_unchecked_rounded,
      reason: '這一輪還沒交出',
    );

    // 這一輪 AI 說修不好：AI 那段是紅叉，校驗那段還是空心圓。
    replies[1].complete(
      fakeAiReply(
        jsonEncode({'action': 'give_up', 'why': 'site_gone', 'reason': '網站關了'}),
      ),
    );
    await _settle(tester);
    expect(iconOf('AI 修改規則').icon, Icons.cancel_rounded);
    expect(iconOf('校驗修好的書源').icon, Icons.radio_button_unchecked_rounded);
  });

  testWidgets('the clipboard way waits for a paste on the same page', (
    tester,
  ) async {
    final copied = <String>[];
    final session = AiRepairSession(
      source: BookSource(
        bookSourceUrl: 'https://site.example',
        bookSourceName: '筆趣閣',
        ruleContent: ContentRule(content: 'id.old@text'),
      ),
      service: null,
      check: (source, _) async => _checked(source),
      probe: (_, _, {start}) async => _probe,
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

  testWidgets('creating a source shows its own four stages, the name the AI '
      'gave it, and a row to share it', (tester) async {
    const url = 'https://site.example/category.html';
    final session = AiRepairSession(
      source: aiCreateBlankSource(url)!,
      create: (url: url, sampleTitle: ''),
      service: _service,
      siteCheck: (_, _) async => const SiteCheck(SiteVerdict.alive, '網站正常回應'),
      fetchPage: (_, _, _) async => (
        lines: const ['  ← $url 200：<form>'],
        pages: const [(line: '  ← $url 200：<form>', body: '<form>')],
      ),
      check: (source, _) async => _checked(source),
      probe: (_, _, {start}) async => _probe,
      ask: (_, _) async => fakeAiReply(
        jsonEncode({
          'action': 'submit',
          'patch': {
            'bookSourceName': '範例書站',
            'ruleContent': {'content': 'class.txt@text'},
          },
          'note': '都試過',
        }),
      ),
      apply: (_, _) async {},
      secrets: (_) async => const {},
    );

    await pumpPage(tester, session);
    await _settle(tester);

    expect(find.text('AI 建立書源 · 範例書站'), findsOneWidget);
    expect(find.text('檢查網站'), findsOneWidget);
    expect(find.text('抓貼的網頁'), findsOneWidget);
    expect(find.text('AI 寫規則'), findsOneWidget);
    expect(find.text('校驗寫好的書源'), findsOneWidget);
    expect(find.text('建立好了'), findsOneWidget);
    expect(find.text('分享這個書源'), findsOneWidget);
    expect(find.text('還原改前的版本'), findsNothing);
  });
}
