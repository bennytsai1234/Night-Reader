import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_sheet.dart';
import 'package:night_reader/features/reader/features/settings/reader_settings_controller.dart';
import 'package:night_reader/features/reader/features/settings/reader_settings_sections.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/popups/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/theme/theme_reveal_scope.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/chinese/ui_language.dart';

class ReaderSettingsSheets {
  const ReaderSettingsSheets._();

  /// 排版面板：半高、不加暗色遮罩，調整時可直接看到正文變化。
  static Future<void> showInterfaceSettings(
    BuildContext context,
    ReaderSettingsController settings,
  ) {
    return ReaderMenuSheet.show<void>(
      context,
      settings: settings,
      barrierColor: Colors.transparent,
      builder: (_) => _ReaderInterfaceSheet(settings: settings),
    );
  }
}

class _ReaderInterfaceSheet extends StatefulWidget {
  const _ReaderInterfaceSheet({required this.settings});

  final ReaderSettingsController settings;

  @override
  State<_ReaderInterfaceSheet> createState() => _ReaderInterfaceSheetState();
}

class _ReaderInterfaceSheetState extends State<_ReaderInterfaceSheet> {
  // 面板自己有左右內距，各組卡片不再加外距。關掉面板時還沒提交的步進
  // 在 dispose 提交。
  late final ReaderSettingsGroups _groups = ReaderSettingsGroups(
    widget.settings,
    margin: EdgeInsets.zero,
  );

  @override
  void dispose() {
    _groups.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderSheetScaffold(
      title: '外觀與排版',
      maxHeightFactor: 0.6,
      children: [
        const SheetSection(title: '風格'),
        const _ReaderStyleSelector(),
        // 面板只放邊讀邊會調的幾項；其他排版、版面、頁首頁尾在閱讀偏好頁。
        _groups.typography(compact: true),
        ..._groups.pageLayout(compact: true),
        GroupedSection(
          margin: EdgeInsets.zero,
          children: [
            GroupedRow(
              title: '更多排版設定',
              onTap: () => _openReadingSettings(context),
            ),
          ],
        ),
      ],
    );
  }

  /// 閱讀偏好頁用自己的控制器寫入同一組偏好設定。它蓋著閱讀器時閱讀器的
  /// 動畫是停的，在那邊改一次就排一次正文會卡在半途、拖到返回動畫裡才
  /// 繼續；等它整個關掉（返回動畫播完）才讓閱讀器照最後的設定重讀、排一次
  /// （ADR 0018，和閱讀器「全域系統設定」同一套）。
  Future<void> _openReadingSettings(BuildContext context) async {
    final route = MaterialPageRoute<void>(
      builder: (_) => const ReadingSettingsPage(),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    await widget.settings.loadSettings();
  }
}

/// 風格選擇：改的是目前深淺用的風格（「外觀與主題」頁的同一個設定），
/// 換了整個 App 一起換，另一個深淺的風格不動。色票顯示各風格在目前深淺
/// 下的正文紙張與文字（含純黑）：紙色上一個正文字色的大「夜」。
class _ReaderStyleSelector extends StatelessWidget
    implements GroupedSkeletonItem {
  const _ReaderStyleSelector();

  static const double _swatchSize = 52;

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final labels = [
      for (final style in AppStyle.values)
        GroupedItemShape.text(
          context,
          style.label,
          style: AppTextStyles.labelSm,
          width: double.infinity,
        ),
    ];
    // 每一格和 Row 裡的 Column 一樣寬：色票與名稱取較寬的（字級放大時
    // 「牛皮紙」比色票寬），色票與名稱在格裡置中；格與格之間照
    // spaceBetween 平分剩下的寬度，至少隔 md。
    final columns = [
      for (final label in labels) math.max(_swatchSize, label.width!),
    ];
    final content = columns.fold<double>(0, (sum, column) => sum + column);
    final rowWidth = math.max(
      width,
      content + (columns.length - 1) * AppSpacing.md,
    );
    final gap = (rowWidth - content) / (columns.length - 1);
    final marks = <SkeletonShape>[];
    var left = 0.0;
    for (var i = 0; i < labels.length; i++) {
      final column = columns[i];
      marks.add(
        SkeletonShape(
          Rect.fromLTWH(
            left + (column - _swatchSize) / 2,
            0,
            _swatchSize,
            _swatchSize,
          ),
          radius: AppRadius.pillShape,
        ),
      );
      marks.addAll(
        labels[i].marksAt(
          Offset(
            left + (column - labels[i].width!) / 2,
            _swatchSize + AppSpacing.xs,
          ),
        ),
      );
      left += column + gap;
    }
    return GroupedItemShape(
      _swatchSize + AppSpacing.xs + labels.first.height,
      marks: marks,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeSettings = context.watch<ThemeSettingsProvider>();
    final brightness = StylePalette.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    // 寬度夠時色票平均分散；窄視窗（分割畫面等）放不下時改為左右捲動。
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            spacing: AppSpacing.md,
            children: [
              for (final style in AppStyle.values)
                _swatch(
                  context,
                  style,
                  style.paletteFor(
                    brightness,
                    AppAccent.theme,
                    pureBlack: themeSettings.pureBlack,
                  ),
                  selected: style == themeSettings.styleFor(brightness),
                  scheme: scheme,
                  // 和外觀設定頁一樣，新配色從點擊處像墨水一樣暈開。
                  onTap: () => ThemeRevealScope.of(context).run(
                    current: style == themeSettings.styleFor(brightness),
                    change: () => themeSettings.setStyle(brightness, style),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(
    BuildContext context,
    AppStyle style,
    StylePalette palette, {
    required bool selected,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: context.ui(style.label),
      selected: selected,
      button: true,
      // excludeSemantics 也排除了子樹手勢的點擊動作，要在這裡補上。
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.menu,
              width: _swatchSize,
              height: _swatchSize,
              decoration: BoxDecoration(
                color: palette.readerBackground,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              alignment: Alignment.center,
              // 大「夜」是正文字色：純黑時紙都是黑的，靠字色分出風格。
              child: UiText(
                '夜',
                // 色票大小固定，字不隨系統字級放大。
                textScaler: TextScaler.noScaling,
                style: AppTextStyles.uiSm.copyWith(
                  fontSize: 26,
                  color: palette.readerText,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            UiText(
              style.label,
              style: AppTextStyles.labelSm.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
