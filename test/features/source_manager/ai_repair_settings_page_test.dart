import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/features/source_manager/ai_repair/ai_repair_settings_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AiRepairSettings> open(
    WidgetTester tester,
    String saved, {
    Future<List<String>> Function(AiService service)? listModels,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (saved.isNotEmpty) AiRepairSettings.serviceKey: saved,
    });
    final settings = AiRepairSettings(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: AiRepairSettingsPage(settings: settings, listModels: listModels),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('picking a common service fills its address and its tested '
      'model', (tester) async {
    final settings = await open(
      tester,
      '{"baseUrl":"https://api.openai.com/v1","apiKey":"sk-1","model":"gpt"}',
    );
    expect(find.text('OpenAI'), findsOneWidget);

    await tester.tap(find.text('常用服務'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenCode Go').last);
    await tester.pumpAndSettle();
    await leave(tester);

    final go = aiServicePresets.first;
    final saved = await settings.read();
    expect(saved.baseUrl, go.baseUrl);
    expect(saved.model, go.model);
    expect(saved.apiKey, 'sk-1');
  });

  testWidgets('a service without a tested model leaves the model to pick', (
    tester,
  ) async {
    final settings = await open(
      tester,
      '{"baseUrl":"https://opencode.ai/inference/go/openai/v1",'
      '"apiKey":"sk-1","model":"deepseek-v4.1-flash"}',
    );
    await tester.tap(find.text('常用服務'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    expect(find.text('選擇'), findsOneWidget);
    await leave(tester);
    expect((await settings.read()).model, '');
  });

  testWidgets('the model for finding books is picked from the same list and '
      'can go back to the repair model', (tester) async {
    final settings = await open(
      tester,
      '{"baseUrl":"https://ai.example/v1","apiKey":"sk-1","model":"repair"}',
      listModels: (_) async => ['repair', 'finder'],
    );
    expect(find.text('同修書源'), findsOneWidget);
    await tester.tap(find.text('找書的模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('finder'));
    await tester.pumpAndSettle();
    await leave(tester);
    expect(await settings.findModel(), 'finder');
    expect((await settings.read()).model, 'repair');

    await open(
      tester,
      '{"baseUrl":"https://ai.example/v1","apiKey":"sk-1","model":"repair",'
      '"findModel":"finder"}',
      listModels: (_) async => ['repair', 'finder'],
    );
    await tester.tap(find.text('找書的模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同修書源').last);
    await tester.pumpAndSettle();
    await leave(tester);
    expect(
      await AiRepairSettings(await SharedPreferences.getInstance()).findModel(),
      '',
    );
  });

  testWidgets('how many sites to repair at once is picked from a menu', (
    tester,
  ) async {
    final settings = await open(tester, '');
    expect(find.text('$aiDefaultConcurrency'), findsOneWidget);
    await tester.tap(find.text('同時修幾個網站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6 個'));
    await tester.pumpAndSettle();
    expect(await settings.concurrency(), 6);
  });

  testWidgets('a model list that comes back after the service changed is '
      'dropped', (tester) async {
    // Codex 審查：列模型清單還沒回來就換了服務，舊服務的清單照樣跳出來，
    // 選了就把舊服務的模型寫進新服務。
    final pending = Completer<List<String>>();
    final settings = await open(
      tester,
      '{"baseUrl":"https://api.openai.com/v1","apiKey":"sk-1","model":""}',
      listModels: (_) => pending.future,
    );
    await tester.tap(find.text('模型'));
    await tester.pump();
    await tester.tap(find.text('常用服務'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();

    pending.complete(['gpt-old']);
    await tester.pumpAndSettle();

    expect(find.text('gpt-old'), findsNothing);
    await leave(tester);
    expect((await settings.read()).model, '');
  });
}
