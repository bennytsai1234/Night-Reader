import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sections.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:provider/provider.dart';

class ReaderV2SettingsSheets {
  const ReaderV2SettingsSheets._();

  /// 排版面板：半高、不加暗色遮罩，調整時可直接看到正文變化。
  static void showInterfaceSettings(
    BuildContext context,
    ReaderV2SettingsController settings,
  ) {
    ReaderV2MenuSheet.show<void>(
      context,
      settings: settings,
      barrierColor: Colors.transparent,
      builder: (_) => _ReaderInterfaceSheet(settings: settings),
    );
  }

  static void showAdvancedSettings(
    BuildContext context,
    ReaderV2SettingsController settings, {
    VoidCallback? onChangeSource,
  }) {
    ReaderV2MenuSheet.show<void>(
      context,
      settings: settings,
      builder: (_) => _ReaderAdvancedSheet(
        settings: settings,
        onChangeSource: onChangeSource,
      ),
    );
  }
}

class _ReaderInterfaceSheet extends StatelessWidget {
  const _ReaderInterfaceSheet({required this.settings});

  final ReaderV2SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final hintStyle = AppTextStyles.uiXs.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ReaderV2SheetScaffold(
      title: '外觀與排版',
      maxHeightFactor: 0.6,
      children: [
        SheetSection(
          title: '風格',
          trailing: Text('月亮鈕切換深淺', style: hintStyle),
        ),
        const _ReaderStyleSelector(),
        ReaderV2TypographySection(
          settings: settings,
          collapsible: true,
          moreChildren: [ReaderV2PageLayoutSection(settings: settings)],
        ),
      ],
    );
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
    // 寬度夠時五個色票平均分散；窄視窗（分割畫面等）放不下時改為左右捲動。
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
                  onTap: () => themeSettings.setStyle(style),
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

class _ReaderAdvancedSheet extends StatelessWidget {
  const _ReaderAdvancedSheet({required this.settings, this.onChangeSource});

  final ReaderV2SettingsController settings;
  final VoidCallback? onChangeSource;

  @override
  Widget build(BuildContext context) {
    final changeSource = onChangeSource;
    final colorScheme = Theme.of(context).colorScheme;
    return ReaderV2SheetScaffold(
      title: '進階設定',
      children: [
        if (changeSource != null) ...[
          const SheetSection(title: '書源'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.swap_horiz),
            title: Text(
              '換源',
              style: AppTextStyles.uiMd.copyWith(color: colorScheme.onSurface),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () {
              Navigator.pop(context);
              changeSource();
            },
          ),
        ],
        ReaderV2AutoPageSection(settings: settings),
        ReaderV2ChineseConvertSection(settings: settings),
        ReaderV2ClickActionSection(settings: settings),
      ],
    );
  }
}
