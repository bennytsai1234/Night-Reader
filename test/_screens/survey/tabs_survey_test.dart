// 臨時：全 App 探索「換分頁」區（範例，其他區照這個寫）。
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'tabs';

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: tabs', (tester) async {
    Future<void> tapTab(String label) => tester.tap(
      find.descendant(
        of: find.byType(FloatingTabBar),
        matching: find.text(label),
      ),
    );

    await runSurvey(
      tester,
      steps: () async {
        // 第一次到發現、我的時分頁才建起來，先錄第一次，再錄建好之後。
        var i = 0;
        for (final (from, to) in [
          ('書架', '發現'),
          ('發現', '我的'),
          ('我的', '書架'),
          ('書架', '我的'),
          ('我的', '發現'),
          ('發現', '書架'),
        ]) {
          i++;
          await surveyStep(
            tester,
            area: _area,
            key: 'tabs${i.toString().padLeft(2, '0')}',
            label: '點分頁：$from→$to',
            action: () => tapTab(to),
          );
        }
      },
    );
  });
}
