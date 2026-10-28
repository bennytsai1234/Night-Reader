// 臨時：全 App 探索的樣本——書架切換列表與網格（書架區裡的四步），先做成
// 頁面給使用者看量法與看法對不對，再一區一區擴大。書架 26 本，同書架區。
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'sample';

Future<void> _tooltip(WidgetTester tester, String tooltip) {
  final byTooltip = find.byTooltip(tooltip);
  return tester.tap(
    byTooltip.evaluate().isNotEmpty
        ? byTooltip.last
        : find.bySemanticsLabel(tooltip).last,
  );
}

Future<void> _steps(WidgetTester tester) async {
  var n = 0;
  Future<void> step(String label, Future<void> Function() action) {
    n++;
    return surveyStep(
      tester,
      area: _area,
      key: 'sample${n.toString().padLeft(2, '0')}',
      label: label,
      action: action,
      minFrames: 0,
    );
  }

  Future<void> openArrange() => _tooltip(tester, '整理書架');
  await step('整理書架：打開', openArrange);
  await step('切換成列表', () => tester.tap(find.text('列表').last));
  await step('整理書架：打開', openArrange);
  await step('切換成網格', () => tester.tap(find.text('網格').last));
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: sample (shelf list / grid)', (tester) async {
    await runSurvey(
      tester,
      launch: () async {
        await tester.runAsync(() => seedMoreBooks(20));
        await pumpApp(tester);
      },
      steps: () => _steps(tester),
    );
  });
}
