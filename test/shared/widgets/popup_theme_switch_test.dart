import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/popup_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 彈出層開著時系統切換深淺：切換後的畫面要和一開始就在那個深淺打開的
/// 一模一樣（面板底色、把手、遮罩、裡面的字與卡片都跟著換）。
void main() {
  final shot = GlobalKey();
  late ReaderV2SettingsController readerSettings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    readerSettings = ReaderV2SettingsController();
  });

  tearDown(() {
    readerSettings.dispose();
    return GetIt.instance.reset();
  });

  Future<Uint8List> pixels(WidgetTester tester) async {
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  /// 在 [start] 的深淺從 [host] 打開 [open]，切到 [end]，回傳切換後的畫面。
  Future<Uint8List> render(
    WidgetTester tester, {
    required void Function(BuildContext context) open,
    required _Host host,
    required Brightness start,
    required Brightness end,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dispatcher = tester.platformDispatcher;
    dispatcher.platformBrightnessTestValue = start;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);

    // 面板裡打開的那一列；閱讀器面板的內容要畫得出骨架，用分組列。
    final row = GlobalKey();
    final button = GroupedSection(
      children: [
        GroupedRow(
          key: row,
          title: '再開',
          onTap: () => open(row.currentContext!),
        ),
      ],
    );
    void openHost(BuildContext context) => switch (host) {
      _Host.page || _Host.readerMenu => open(context),
      _Host.sheet => AppBottomSheet.show<void>(
        context: context,
        title: '外面',
        children: [button],
      ),
      _Host.readerSheet => ReaderV2MenuSheet.show<void>(
        context,
        settings: readerSettings,
        builder: (_) => ReaderV2SheetScaffold(title: '外面', children: [button]),
      ),
    };

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        darkTheme: buildAppTheme(AppStyle.paper, Brightness.dark),
        themeMode: ThemeMode.system,
        themeAnimationStyle: AnimationStyle.noAnimation,
        builder: (context, child) => RepaintBoundary(key: shot, child: child),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) {
                final opener = Builder(
                  builder: (context) => TextButton(
                    onPressed: () => openHost(context),
                    child: const Text('開'),
                  ),
                );
                // 閱讀選單：頁面上包一層選單配色，從裡面打開。
                return host == _Host.readerMenu
                    ? DerivedTheme(
                        derive: ReaderV2MenuStyle.menuThemeOf,
                        child: opener,
                      )
                    : opener;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
    if (host.nested) {
      await tester.tap(find.text('再開'));
      await tester.pumpAndSettle();
    }
    dispatcher.platformBrightnessTestValue = end;
    await tester.pumpAndSettle();
    return pixels(tester);
  }

  final popups = <String, void Function(BuildContext)>{
    '底部面板': (context) => AppBottomSheet.show<void>(
      context: context,
      title: '面板',
      children: [
        GroupedSection(
          header: '分組',
          children: [GroupedRow(title: '項目', onTap: () {})],
        ),
      ],
    ),
    '系統把手的面板': (context) => AppBottomSheet.showCustom<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            title: '篩選搜尋結果',
            trailing: PlainTextAction(label: '清除', onPressed: () {}),
          ),
          const SizedBox(height: 120),
        ],
      ),
    ),
    '提示框': (context) =>
        showAppConfirm(context: context, title: '刪除 3 本書？', message: '書會移出書架'),
    '動作表': (context) => showAppActionSheet<String>(
      context: context,
      title: '字型',
      actions: const [AppSheetAction(label: '系統字型', value: 'a')],
    ),
    '彈出選單': (context) => showGlassMenu<String>(
      context: context,
      anchor: const Rect.fromLTWH(300, 300, 40, 40),
      entries: [
        GlassMenuItem(
          value: 'a',
          label: '強調色',
          swatch: (context) => Theme.of(context).colorScheme.primary,
        ),
      ],
    ),
    '長按預覽選單': (context) => showContextPreviewMenu<String>(
      context: context,
      sourceRect: const Rect.fromLTWH(40, 200, 200, 60),
      // 照書源管理與發現的預覽：底色在預覽裡取，字色由 Material 給。
      preview: Builder(
        builder: (context) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: const Text('書名'),
        ),
      ),
      entries: const [GlassMenuItem(value: 'a', label: '移出書架')],
    ),
    '閱讀器面板': (context) => ReaderV2MenuSheet.show<void>(
      context,
      settings: readerSettings,
      builder: (_) => ReaderV2SheetScaffold(
        title: '標註',
        children: [GroupedRow(title: '顏色', onTap: () {})],
      ),
    ),
    '對話框': (context) => showAppDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('字級'),
        content: TextField(
          decoration: InputDecoration(
            fillColor: Theme.of(context).colorScheme.surface,
          ),
        ),
      ),
    ),
  };

  for (final MapEntry(key: name, value: open) in popups.entries) {
    for (final host in _Host.values) {
      for (final (start, end) in [
        (Brightness.light, Brightness.dark),
        (Brightness.dark, Brightness.light),
      ]) {
        testWidgets('$name（${host.label}）：${start.name} 開著切到 ${end.name}，'
            '和直接在 ${end.name} 打開一樣', (tester) async {
          final expected = await render(
            tester,
            open: open,
            host: host,
            start: end,
            end: end,
          );
          final switched = await render(
            tester,
            open: open,
            host: host,
            start: start,
            end: end,
          );
          expect(_firstDifference(switched, expected), isNull);
        });
      }
    }
  }
}

/// 第一個不同的像素（400 寬），一樣時回傳 null。
String? _firstDifference(Uint8List actual, Uint8List expected) {
  for (var i = 0; i < expected.length; i += 4) {
    for (var c = 0; c < 4; c++) {
      if (actual[i + c] != expected[i + c]) {
        final p = i ~/ 4;
        String rgba(Uint8List b) => b.sublist(i, i + 4).join(',');
        return '(${p % 400}, ${p ~/ 400}) 是 ${rgba(actual)}，'
            '應為 ${rgba(expected)}';
      }
    }
  }
  return null;
}

/// 從哪裡打開。
enum _Host {
  page('從頁面開'),
  sheet('從底部面板裡開'),
  readerSheet('從閱讀器面板裡開'),
  readerMenu('從閱讀選單開');

  const _Host(this.label);

  final String label;

  /// 先打開一個面板，再從面板裡打開。
  bool get nested => this == sheet || this == readerSheet;
}
