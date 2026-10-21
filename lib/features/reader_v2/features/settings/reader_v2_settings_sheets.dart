import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sections.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/theme_reveal_scope.dart';
import 'package:provider/provider.dart';

class ReaderV2SettingsSheets {
  const ReaderV2SettingsSheets._();

  /// 排版面板：半高、不加暗色遮罩，調整時可直接看到正文變化。
  static Future<void> showInterfaceSettings(
    BuildContext context,
    ReaderV2SettingsController settings,
  ) {
    return ReaderV2MenuSheet.show<void>(
      context,
      settings: settings,
      barrierColor: Colors.transparent,
      builder: (_) => _ReaderInterfaceSheet(settings: settings),
    );
  }
}

class _ReaderInterfaceSheet extends StatefulWidget {
  const _ReaderInterfaceSheet({required this.settings});

  final ReaderV2SettingsController settings;

  @override
  State<_ReaderInterfaceSheet> createState() => _ReaderInterfaceSheetState();
}

class _ReaderInterfaceSheetState extends State<_ReaderInterfaceSheet> {
  // 面板自己有左右內距，各組卡片不再加外距。關掉面板時還沒提交的步進
  // 在 dispose 提交。
  late final ReaderV2SettingsGroups _groups = ReaderV2SettingsGroups(
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
    return ReaderV2SheetScaffold(
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

/// 風格選擇：與「外觀與主題」頁是同一個設定，換了整個 App 一起換。
/// 色票顯示各風格在目前深淺下的正文紙張與文字。
class _ReaderStyleSelector extends StatelessWidget {
  const _ReaderStyleSelector();

  static const double _swatchSize = 52;

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
                  style,
                  style.of(brightness),
                  selected: style == themeSettings.style,
                  scheme: scheme,
                  // 和外觀設定頁一樣，新配色從點擊處像墨水一樣暈開。
                  onTap: () {
                    if (style == themeSettings.style) return;
                    ThemeRevealScope.of(context)
                        .run(change: () => themeSettings.setStyle(style));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(
    AppStyle style,
    StylePalette palette, {
    required bool selected,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: style.label,
      selected: selected,
      button: true,
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
              child: Text(
                'Aa',
                style: AppTextStyles.uiSm.copyWith(
                  color: palette.readerText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
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
