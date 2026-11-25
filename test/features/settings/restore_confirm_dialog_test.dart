import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/settings/restore_confirm_dialog.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/lists/grouped_row.dart';

void main() {
  /// 開確認框，回傳等結果的 Future。
  Future<Future<({bool restoreSettings})?>> open(WidgetTester tester) async {
    late Future<({bool restoreSettings})?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.kraft, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = confirmRestore(context),
              child: const Text('開'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
    return result;
  }

  bool switchOn(WidgetTester tester) =>
      tester.widget<GroupedSwitchRow>(find.byType(GroupedSwitchRow)).value;

  testWidgets('「設定也還原」預設開，直接開始就連設定一起還原', (tester) async {
    final result = await open(tester);

    expect(find.text('設定也還原'), findsOneWidget);
    expect(switchOn(tester), isTrue);
    await tester.tap(find.text('開始還原'));
    await tester.pumpAndSettle();

    expect(await result, (restoreSettings: true));
  });

  testWidgets('關掉開關再開始，設定不還原', (tester) async {
    final result = await open(tester);

    await tester.tap(find.text('設定也還原'));
    await tester.pumpAndSettle();
    expect(switchOn(tester), isFalse);
    await tester.tap(find.text('開始還原'));
    await tester.pumpAndSettle();

    expect(await result, (restoreSettings: false));
  });

  testWidgets('取消就不還原', (tester) async {
    final result = await open(tester);

    await tester.tap(find.text('設定也還原'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });
}
