import 'package:flutter/material.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:provider/provider.dart';

/// 外觀與主題：風格、深淺與玻璃效果。風格與深淺同時決定 App 介面、
/// 閱讀正文與閱讀選單的配色。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeSettings = context.watch<ThemeSettingsProvider>();
    final appSettings = context.watch<SettingsProvider>();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassNavHeader(title: '外觀與主題'),
      body: GroupedListView(
        children: [
          GroupedSection(
            topGap: AppSpacing.lg,
            header: '風格',
            children: [
              GroupedContent(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _StyleGrid(
                  selected: themeSettings.style,
                  onSelected: themeSettings.setStyle,
                ),
              ),
            ],
          ),
          GroupedSection(
            header: '深淺',
            children: [
              for (final (mode, label) in const [
                (ThemeMode.system, '跟隨系統'),
                (ThemeMode.light, '淺色'),
                (ThemeMode.dark, '深色'),
              ])
                GroupedCheckRow(
                  title: label,
                  selected: appSettings.themeMode == mode,
                  onTap: () => appSettings.setThemeMode(mode),
                ),
            ],
          ),
          GroupedSection(
            header: '玻璃效果',
            children: [
              GroupedContent(
                child: GlassSegmented<GlassStrength>(
                  segments: [
                    for (final strength in GlassStrength.values)
                      GlassSegment(strength, strength.label),
                  ],
                  selected: themeSettings.glassStrength,
                  onChanged: themeSettings.setGlassStrength,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 三欄風格卡：上半是正文紙張與文字，下半是 App 卡片底色與主色；
/// 顯示各風格在目前深淺下的樣子。
class _StyleGrid extends StatelessWidget {
  const _StyleGrid({required this.selected, required this.onSelected});

  final AppStyle selected;
  final ValueChanged<AppStyle> onSelected;

  static const int _columns = 3;
  static const double _gap = AppSpacing.md;

  /// 卡片高度 = 不隨字級變動的留白與色塊 + 三行文字（「永」、範例字、
  /// 風格名稱）。1 倍字級時是 112，系統字級放大時跟著長高。
  static const double _cardChromeHeight = 60;
  static const double _cardTextHeight = 52;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final cardHeight =
        _cardChromeHeight +
        MediaQuery.textScalerOf(context).scale(_cardTextHeight);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final style in AppStyle.values)
              SizedBox(
                width: width,
                height: cardHeight,
                child: _StyleCard(
                  style: style,
                  palette: style.of(brightness),
                  selected: style == selected,
                  onTap: () => onSelected(style),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppStyle style;
  final StylePalette palette;
  final bool selected;
  final VoidCallback onTap;

  static const double _stripHeight = 30;
  static const double _badgeSize = 18;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: style.label,
      selected: selected,
      button: true,
      // excludeSemantics 也排除了子樹手勢的點擊動作，要在這裡補上。
      onTap: onTap,
      excludeSemantics: true,
      child: PressScale(
        scale: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.menu,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardMd,
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : AppChrome.of(context).separator,
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      color: palette.readerBackground,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '永',
                            style: AppTextStyles.titleSm.copyWith(
                              color: palette.readerText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '燈下的字',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: AppTextStyles.labelXs.copyWith(
                              color: palette.readerText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    // 字級放大時色條跟著長高，標籤不被裁掉。
                    constraints: const BoxConstraints(minHeight: _stripHeight),
                    color: palette.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: palette.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            style.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.uiSm.copyWith(
                              color: palette.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: Container(
                    width: _badgeSize,
                    height: _badgeSize,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
