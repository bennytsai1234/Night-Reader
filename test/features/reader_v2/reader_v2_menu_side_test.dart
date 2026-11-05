import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 閱讀選單與面板跟著每行字數對齊正文的左右邊。
void main() {
  Future<ReaderV2SettingsController> settingsWith(int lineChars) async {
    SharedPreferences.setMockInitialValues({
      PreferKey.readerLineChars: lineChars,
    });
    final getIt = GetIt.instance;
    if (getIt.isRegistered<SharedPreferences>()) {
      getIt.unregister<SharedPreferences>();
    }
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    return ReaderV2SettingsController();
  }

  tearDown(GetIt.instance.reset);

  test(
    'a phone that cannot fit the line keeps the menus where they were',
    () async {
      final settings = await settingsWith(32);
      addTearDown(settings.dispose);

      expect(settings.menuSideFor(412), isNull);
    },
  );

  test('on a phone the menus reach 4 past the text so line ends stay covered, '
      'between 4 and 16 from the screen edge', () async {
    final settings = await settingsWith(32);
    addTearDown(settings.dispose);

    // 預設留白（12 起）：選單在正文左右邊再往外 4。
    final text = settings.paddingHorizontalFor(412);
    expect(text, lessThan(20));
    expect(settings.menuInsetFor(412), text - 4);

    // 留白很寬：選單照原本離邊 16。
    settings.paddingHorizontal = 40;
    expect(settings.menuInsetFor(412), 16);

    // 正文貼著畫面邊：選單也留 4。
    settings.paddingHorizontal = 0;
    expect(settings.paddingHorizontalFor(412), lessThan(8));
    expect(settings.menuInsetFor(412), 4);
  });

  test('a narrowed text column puts the menus on its edges', () async {
    final settings = await settingsWith(32);
    addTearDown(settings.dispose);

    final side = settings.menuSideFor(1280);
    expect(side, isNotNull);
    expect(side, settings.paddingHorizontalFor(1280));
    expect(side, greaterThan(settings.paddingHorizontal));
  });

  test('fewer characters per line pull the menus further in', () async {
    final narrow = await settingsWith(20);
    addTearDown(narrow.dispose);
    final narrowSide = narrow.menuSideFor(1280)!;
    await GetIt.instance.reset();

    final wide = await settingsWith(40);
    addTearDown(wide.dispose);
    final wideSide = wide.menuSideFor(1280)!;

    expect(narrowSide, greaterThan(wideSide));
  });

  test('a very short line still leaves the menus wide enough for their '
      'buttons', () async {
    final settings = await settingsWith(3);
    addTearDown(settings.dispose);

    final side = settings.menuSideFor(1280)!;
    expect(1280 - side * 2, ReaderV2SettingsController.menuMinWidth);
  });

  group('reader panels', () {
    Future<void> openPanel(
      WidgetTester tester,
      ReaderV2SettingsController settings,
    ) async {
      tester.view.physicalSize = const Size(1280, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => ReaderV2MenuSheet.show<void>(
                  context,
                  settings: settings,
                  // 裡面放一層接得到點擊的底，點面板時點到的是面板本身。
                  builder: (_) => const SizedBox(
                    key: Key('panel'),
                    height: 200,
                    child: ColoredBox(color: Colors.transparent),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    double panelWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(const Key('panel'))).width;

    testWidgets('changing characters per line while a panel is open moves '
        'its edges with the text', (tester) async {
      final settings = await tester.runAsync(() => settingsWith(32));
      addTearDown(settings!.dispose);
      await openPanel(tester, settings);

      final before = panelWidth(tester);
      expect(before, 1280 - settings.menuSideFor(1280)! * 2);

      settings.setLineChars(40);
      await tester.pump();
      final after = panelWidth(tester);
      expect(after, greaterThan(before));
      expect(after, 1280 - settings.menuSideFor(1280)! * 2);
    });

    testWidgets('tapping beside a narrowed panel closes it', (tester) async {
      final settings = await tester.runAsync(() => settingsWith(20));
      addTearDown(settings!.dispose);
      await openPanel(tester, settings);
      expect(find.byKey(const Key('panel')), findsOneWidget);

      // 面板下緣旁邊、畫面左邊的空白。
      await tester.tapAt(const Offset(20, 870));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel')), findsNothing);
    });

    testWidgets('tapping inside the panel keeps it open', (tester) async {
      final settings = await tester.runAsync(() => settingsWith(20));
      addTearDown(settings!.dispose);
      await openPanel(tester, settings);

      await tester.tap(find.byKey(const Key('panel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel')), findsOneWidget);
    });
  });
}
