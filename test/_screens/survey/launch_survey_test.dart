// 臨時：全 App 探索「開 App 進場」區。進場本身是一步（pumpWidget 整個 App，
// 錄到書架的骨架換成內容、進場播完為止）。兩個情境：書架 6 本（launch01），
// 書架再加 20 本（launch02）。
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'launch';

/// 書架已經建出來、進場播完（骨架換成內容、收尾也做完）。
bool _entranceFinished() {
  final shelf = find.byType(BookshelfPage).evaluate();
  if (shelf.isEmpty) return false;
  return LaunchEntrance.maybeOf(shelf.first)?.isFinished ?? false;
}

/// 開 App 這一步：整個 App 從無到有，直到進場播完。和 [pumpApp] 同一套
/// 建置，差別只在這一步是錄下來的。
Future<void> _launchStep(WidgetTester tester, String key, String label) =>
    surveyStep(
      tester,
      area: _area,
      key: key,
      label: label,
      action: () => tester.pumpWidget(
        MultiProvider(
          providers: AppProviders.providers,
          child: const ReaderApp(),
        ),
      ),
      until: _entranceFinished,
    );

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: launch', (tester) async {
    await runSurvey(
      tester,
      launch: () => _launchStep(tester, 'launch01', '開 App：進場到內容出現'),
      steps: () async {},
    );
  });

  testWidgets('survey: launch with 20 more books', (tester) async {
    await runSurvey(
      tester,
      launch: () async {
        // 書架上再多 20 本（upsert，重跑與暖身不會重複加）。
        await tester.runAsync(() => seedMoreBooks(20));
        await _launchStep(tester, 'launch02', '開 App（書架 26 本）：進場到內容出現');
      },
      steps: () async {},
    );
  });
}
