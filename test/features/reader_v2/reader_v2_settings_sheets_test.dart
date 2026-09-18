import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('四個排版 slider 共用 trailing commit，drag end 提交全部最終值', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = ReaderV2SettingsController();
    addTearDown(settings.dispose);
    await settings.loadSettings();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => ReaderV2SettingsSheets.showInterfaceSettings(
                      context,
                      settings,
                    ),
                child: const Text('開啟設定'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('開啟設定'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNWidgets(4));

    tester.widgetList<Slider>(find.byType(Slider)).elementAt(0).onChanged!(20);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('20.0'), findsOneWidget);

    tester.widgetList<Slider>(find.byType(Slider)).elementAt(1).onChanged!(1.8);
    await tester.pump(const Duration(milliseconds: 80));

    // 第二個 slider 的變更須延後整批 timer；第一個值不能由舊 timer 先提交。
    expect(settings.fontSize, 18);
    expect(settings.lineHeight, 1.5);

    tester.widgetList<Slider>(find.byType(Slider)).elementAt(2).onChanged!(0.6);
    await tester.pump();
    tester.widgetList<Slider>(find.byType(Slider)).elementAt(3).onChanged!(1.2);
    await tester.pump();

    tester.widgetList<Slider>(find.byType(Slider)).elementAt(3).onChangeEnd!(
      1.2,
    );
    await tester.pump();
    await tester.pump();

    expect(settings.fontSize, 20);
    expect(settings.lineHeight, 1.8);
    expect(settings.letterSpacing, 0.6);
    expect(settings.paragraphSpacing, 1.2);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(PreferKey.readerFontSize), 20);
    expect(prefs.getDouble(PreferKey.readerLineHeight), 1.8);
    expect(prefs.getDouble(PreferKey.readerLetterSpacing), 0.6);
    expect(prefs.getDouble(PreferKey.readerParagraphSpacing), 1.2);

    // 已提交後 dirty 會清空；外部較新的值不能在 sheet dispose 時被舊快照覆寫。
    settings.setTypography(fontSize: 22);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(settings.fontSize, 22);
    expect(prefs.getDouble(PreferKey.readerFontSize), 22);
  });

  testWidgets('只提交使用者改動欄位，保留等待期間的外部排版更新', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = ReaderV2SettingsController();
    addTearDown(settings.dispose);
    await settings.loadSettings();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => ReaderV2SettingsSheets.showInterfaceSettings(
                      context,
                      settings,
                    ),
                child: const Text('開啟設定'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('開啟設定'));
    await tester.pumpAndSettle();

    tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(20);
    await tester.pump(const Duration(milliseconds: 40));

    settings.setTypography(
      lineHeight: 2.2,
      letterSpacing: 1.4,
      paragraphSpacing: 2.0,
    );
    await tester.pump();

    tester.widgetList<Slider>(find.byType(Slider)).first.onChangeEnd!(20);
    await tester.pump();
    await tester.pump();

    expect(settings.fontSize, 20);
    expect(settings.lineHeight, 2.2);
    expect(settings.letterSpacing, 1.4);
    expect(settings.paragraphSpacing, 2.0);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(PreferKey.readerFontSize), 20);
    expect(prefs.getDouble(PreferKey.readerLineHeight), 2.2);
    expect(prefs.getDouble(PreferKey.readerLetterSpacing), 1.4);
    expect(prefs.getDouble(PreferKey.readerParagraphSpacing), 2.0);
  });
}
