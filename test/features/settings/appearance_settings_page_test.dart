import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/settings/appearance_settings_page.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ThemeSettingsProvider themeSettings;

  /// 預設是一般手機的大小（393×852）。
  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(393, 852),
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    GetIt.instance.registerSingleton<SharedPreferences>(prefs);
    addTearDown(GetIt.instance.reset);
    themeSettings = ThemeSettingsProvider();
    final settings = SettingsProvider();
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeSettings),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: Consumer<ThemeSettingsProvider>(
          builder: (context, theme, _) => MaterialApp(
            theme: buildAppTheme(
              theme.darkStyle,
              Brightness.dark,
              accent: theme.accent,
              pureBlack: theme.pureBlack,
            ),
            home: const AppearanceSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('淺色、深色風格各一排、每排全部風格，一頁放得下到玻璃效果', (tester) async {
    await pumpPage(tester);
    final tops = <double>[];
    for (final style in AppStyle.values) {
      final cards = find.bySemanticsLabel(style.label);
      expect(cards, findsNWidgets(2), reason: '${style.label}淺色、深色各一張');
      for (final card in cards.evaluate()) {
        tops.add(
          tester.getTopLeft(find.byElementPredicate((e) => e == card)).dy,
        );
      }
    }
    expect(tops.toSet(), hasLength(2), reason: '排成兩排');
    expect(
      tops.where((top) => top == tops.first),
      hasLength(AppStyle.values.length),
    );
    final glass = tester.getBottomLeft(find.text('玻璃'));
    expect(glass.dy, lessThan(852), reason: '不用往下捲就看得到玻璃效果');
  });

  testWidgets('窄螢幕加大字級時，風格名稱換行而不省略', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpPage(tester, size: const Size(320, 640));
    for (final style in AppStyle.values) {
      for (final element in find.text(style.label).evaluate()) {
        final label = element.renderObject! as RenderParagraph;
        expect(label.didExceedMaxLines, isFalse, reason: style.label);
      }
    }
  });

  testWidgets('上面那排只改淺色的風格，下面那排只改深色的風格', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.bySemanticsLabel(AppStyle.tea.label).first);
    await tester.pumpAndSettle();
    expect(themeSettings.lightStyle, AppStyle.tea);
    expect(themeSettings.darkStyle, ThemeSettingsProvider.defaultDarkStyle);

    await tester.tap(find.bySemanticsLabel(AppStyle.kraft.label).last);
    await tester.pumpAndSettle();
    expect(themeSettings.darkStyle, AppStyle.kraft);
    expect(themeSettings.lightStyle, AppStyle.tea);
    expect(prefs.getString(PreferKey.lightStyle), AppStyle.tea.name);
    expect(prefs.getString(PreferKey.darkStyle), AppStyle.kraft.name);
    final context = tester.element(find.byType(AppearanceSettingsPage));
    expect(
      Theme.of(context).scaffoldBackgroundColor,
      const Color(0xFF000000),
      reason: '純黑開著，深色換成牛皮紙仍是純黑底',
    );
  });

  testWidgets('關掉深色用純黑，深色換回風格自己的底色並保存', (tester) async {
    await pumpPage(tester);
    themeSettings.setStyle(Brightness.dark, AppStyle.tea);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色用純黑'));
    await tester.pumpAndSettle();
    expect(themeSettings.pureBlack, isFalse);
    expect(prefs.getBool(PreferKey.pureBlack), isFalse);
    final context = tester.element(find.byType(AppearanceSettingsPage));
    expect(
      Theme.of(context).scaffoldBackgroundColor,
      AppStyle.tea.dark.background,
    );
  });

  testWidgets('從強調色選單選顏色，整個 App 的主色跟著換並保存', (tester) async {
    await pumpPage(tester);
    expect(themeSettings.darkStyle, AppStyle.plain);
    expect(find.text('跟隨主題'), findsOneWidget);

    await tester.tap(find.text('強調色'));
    await tester.pumpAndSettle();
    for (final accent in AppAccent.values.skip(1)) {
      expect(find.text(accent.label), findsWidgets);
    }

    await tester.tap(find.text('竹綠').last);
    await tester.pumpAndSettle();

    expect(themeSettings.accent, AppAccent.bamboo);
    expect(prefs.getString(PreferKey.appAccent), AppAccent.bamboo.name);
    final context = tester.element(find.byType(AppearanceSettingsPage));
    final primary = Theme.of(context).colorScheme.primary;
    expect(
      primary,
      AppStyle.plain.paletteFor(Brightness.dark, AppAccent.bamboo).primary,
    );
    expect(
      HSLColor.fromColor(primary).hue,
      closeTo(HSLColor.fromColor(AppAccent.bamboo.dark!).hue, 2),
      reason: '素色深色選竹綠，開關是綠色而不是白色',
    );
  });

  testWidgets('不再有骨架的選項，骨架照固定的樣子與換場', (tester) async {
    await pumpPage(tester);
    for (final title in ['骨架深淺', '骨架呼吸', '骨架換場', '換場時長']) {
      expect(find.text(title), findsNothing, reason: title);
    }
    final context = tester.element(find.byType(AppearanceSettingsPage));
    expect(SkeletonLook.of(context), const SkeletonLook());
    expect(SkeletonLook.of(context).strength, SkeletonStrength.standard);
    expect(SkeletonLook.of(context).breath, SkeletonBreath.gentleSweep);
    expect(SkeletonReveal.of(context), const SkeletonReveal());
    expect(SkeletonReveal.of(context).sweeps, isTrue);
    expect(
      SkeletonReveal.of(context).duration,
      const Duration(milliseconds: 600),
    );
  });
}
