import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sections.dart';
import 'package:night_reader/shared/theme/app_theme.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';

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
          title: '閱讀主題',
          trailing: Text('正文背景與文字', style: hintStyle),
        ),
        ListenableBuilder(
          listenable: settings,
          builder: (context, _) => _ReaderThemeSelector(
            selectedIndex: settings.themeIndex,
            onSelected: settings.setTheme,
          ),
        ),
        ReaderV2TypographySection(
          settings: settings,
          collapsible: true,
          moreChildren: [
            ReaderV2PageLayoutSection(settings: settings),
            SheetSection(
              title: '選單樣式',
              trailing: Text('選單與工具列配色', style: hintStyle),
            ),
            ListenableBuilder(
              listenable: settings,
              builder: (context, _) => _ReaderThemeSelector(
                selectedIndex: settings.menuThemeIndex,
                onSelected: settings.setMenuTheme,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReaderThemeSelector extends StatelessWidget {
  const _ReaderThemeSelector({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: AppTheme.readingThemes.length,
        itemBuilder: (context, index) {
          final theme = AppTheme.readingThemes[index];
          final selected = selectedIndex == index;
          return Semantics(
            label: theme.name,
            selected: selected,
            button: true,
            child: GestureDetector(
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Aa',
                    style: AppTextStyles.uiSm.copyWith(
                      color: theme.textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
            subtitle: Text(
              '搜尋其他書源並切換本書來源',
              style: AppTextStyles.bodyXs.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
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
