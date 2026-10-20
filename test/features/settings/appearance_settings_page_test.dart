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
              theme.style,
              Brightness.dark,
              accent: theme.accent,
            ),
            home: const AppearanceSettingsPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('風格卡一列五張，一頁放得下到玻璃效果', (tester) async {
    await pumpPage(tester);
    final tops = <double>[];
    for (final style in AppStyle.values) {
      tops.add(tester.getTopLeft(find.bySemanticsLabel(style.label)).dy);
    }
    expect(tops, hasLength(5));
    expect(tops.toSet(), hasLength(1), reason: '五張排成一列');
    final glass = tester.getBottomLeft(find.text('玻璃'));
    expect(glass.dy, lessThan(852), reason: '不用往下捲就看得到玻璃效果');
  });

  testWidgets('窄螢幕加大字級時，風格名稱換行而不省略', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpPage(tester, size: const Size(320, 640));
    for (final style in AppStyle.values) {
      final label = tester.renderObject<RenderParagraph>(
        find.text(style.label),
      );
      expect(label.didExceedMaxLines, isFalse, reason: style.label);
    }
  });

  testWidgets('從強調色選單選顏色，整個 App 的主色跟著換並保存', (tester) async {
    await pumpPage(tester);
    themeSettings.setStyle(AppStyle.plain);
    await tester.pumpAndSettle();
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

  testWidgets('骨架換場預設由左而右、0.6 秒，改了會保存', (tester) async {
    await pumpPage(tester);
    await tester.scrollUntilVisible(find.text('換場時長'), 200);
    expect(find.text('由左而右'), findsOneWidget);
    expect(find.text('0.6 秒'), findsOneWidget);

    // 捲到畫面中間，不被頁首與底部讓出的位置擋住。
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(themeSettings.skeletonReveal.duration.inMilliseconds, 700);
    expect(prefs.getInt(PreferKey.skeletonRevealMillis), 700);

    await tester.tap(find.text('骨架換場'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('整頁淡入').last);
    await tester.pumpAndSettle();
    expect(themeSettings.skeletonReveal.style, SkeletonRevealStyle.fade);
    expect(
      prefs.getString(PreferKey.skeletonRevealStyle),
      SkeletonRevealStyle.fade.name,
    );
  });
}
