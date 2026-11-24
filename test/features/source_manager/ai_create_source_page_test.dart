import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/features/source_manager/ai_repair/ai_create_source_page.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('an address without its scheme gets https, and one that is not a '
      'website is refused', () {
    expect(aiCreateUrl('www.site.example/a'), 'https://www.site.example/a');
    expect(aiCreateUrl(' http://site.example '), 'http://site.example');
    expect(aiCreateUrl(''), isNull);
    expect(aiCreateUrl('ftp://site.example'), isNull);
    expect(
      aiCreateUrl('https://me:secret@site.example/'),
      isNull,
      reason: '網址裡的帳密會送給 AI、寫進書源說明',
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required bool withService,
    List<BookSource> sources = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AiRepairSettings(await SharedPreferences.getInstance());
    if (withService) {
      await settings.save((
        baseUrl: 'https://ai.example/v1',
        apiKey: 'k',
        model: 'm',
        effort: '',
      ));
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: AiCreateSourcePage(
          settings: settings,
          runs: RepairRuns(),
          sources: () async => sources,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('開始建立 waits for an address and asks for an AI service when '
      'none is set', (tester) async {
    await pumpPage(tester, withService: false);

    expect(find.text('AI 建立書源'), findsOneWidget);
    final start = tester.widget<Widget>(find.text('開始建立'));
    expect(start, isNotNull);
    await tester.tap(find.text('開始建立'));
    await tester.pumpAndSettle();
    expect(find.text('還沒設定 AI 服務。'), findsNothing, reason: '沒填網址時不能按');

    await tester.enterText(find.byType(TextField).first, 'site.example');
    await tester.pump();
    await tester.tap(find.text('開始建立'));
    await tester.pumpAndSettle();
    expect(find.text('還沒設定 AI 服務。'), findsOneWidget);
    expect(find.text('設定 AI 服務'), findsOneWidget);
  });

  testWidgets('a site that already has a source asks first, and offers the AI '
      'repair when that source is marked abnormal', (tester) async {
    final same = BookSource(
      bookSourceUrl: 'https://site.example',
      bookSourceName: '舊的站',
    )..addGroup(abnormalSourceGroupTag);
    await pumpPage(tester, withService: true, sources: [same]);

    expect(find.text('送到'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      'https://site.example/list',
    );
    await tester.pump();
    await tester.tap(find.text('開始建立'));
    await tester.pumpAndSettle();

    expect(find.text('已經有同網站的書源「舊的站」。'), findsOneWidget);
    expect(find.text('AI 修復它'), findsOneWidget);
    expect(find.text('仍然建立'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('AI 建立書源'), findsOneWidget, reason: '取消就留在輸入頁');
  });

  // 第一次設定服務：在設定頁選好、返回時就有「送到」（頁面一關上就讀，
  // 設定頁要等返回動畫播完才拆掉）。
  testWidgets('setting up a service shows where it sends on coming back', (
    tester,
  ) async {
    await pumpPage(tester, withService: false);
    expect(find.text('送到'), findsNothing);

    await tester.tap(find.byType(GlassMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 服務設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('常用服務'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenCode Go'));
    await tester.pumpAndSettle();
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(GroupedRow, 'opencode.ai · deepseek-v4.1-flash'),
      findsOneWidget,
    );
  });
}
