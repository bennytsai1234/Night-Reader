import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/features/source_manager/ai_repair/ai_repair_settings_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<AiRepairSettings> open(WidgetTester tester, String saved) async {
    SharedPreferences.setMockInitialValues({
      if (saved.isNotEmpty) AiRepairSettings.serviceKey: saved,
    });
    final settings = AiRepairSettings(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: AiRepairSettingsPage(settings: settings),
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
}
