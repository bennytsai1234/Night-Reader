import 'package:flutter/material.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/theme_reveal_scope.dart';
import 'package:provider/provider.dart';

/// 外觀與主題：風格、強調色、深淺、玻璃效果與換頁動畫。風格與深淺同時
/// 決定 App 介面、閱讀正文與閱讀選單的配色。
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: _StyleGrid(
                  selected: themeSettings.style,
                  accent: themeSettings.accent,
                  onSelected: (style) {
                    if (style == themeSettings.style) return;
                    ThemeRevealScope.of(context)
                        .run(change: () => themeSettings.setStyle(style));
                  },
                ),
              ),
              Builder(
                builder: (rowContext) => GroupedRow(
                  title: '強調色',
                  value: themeSettings.accent.label,
                  trailing: _AccentDot(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  showChevron: false,
                  onTap: () => _pickAccent(rowContext, themeSettings),
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
                  onTap: () {
                    if (appSettings.themeMode == mode) return;
                    ThemeRevealScope.of(context)
                        .run(change: () => appSettings.setThemeMode(mode));
                  },
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
          GroupedSection(
            header: '換頁動畫',
            children: [
              GroupedContent(
                child: GlassSegmented<AppPageTransition>(
                  segments: [
                    for (final transition in AppPageTransition.values)
                      GlassSegment(transition, transition.label),
                  ],
                  selected: themeSettings.pageTransition,
                  onChanged: themeSettings.setPageTransition,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 強調色選單：每個色點是套到目前風格與深淺後實際會用的顏色。
Future<void> _pickAccent(
  BuildContext rowContext,
  ThemeSettingsProvider themeSettings,
) async {
  final brightness = Theme.of(rowContext).brightness;
  final accent = await showGlassMenu<AppAccent>(
    context: rowContext,
    anchor: globalRectOf(rowContext),
    entries: [
      for (final accent in AppAccent.values)
        GlassMenuItem(
          value: accent,
          label: accent.label,
          checked: accent == themeSettings.accent,
          swatch: themeSettings.style.paletteFor(brightness, accent).primary,
        ),
    ],
  );
  if (accent == null || accent == themeSettings.accent) return;
  if (!rowContext.mounted) return;
  ThemeRevealScope.of(rowContext)
      .run(change: () => themeSettings.setAccent(accent));
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// 風格卡：每個風格一張直式小書頁，兩列、每列五張，一頁放得下全部風格與
/// 下面的強調色、深淺與玻璃效果。顯示各風格在目前深淺下的樣子。
class _StyleGrid extends StatelessWidget {
  const _StyleGrid({
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final AppStyle selected;

  /// 摺角的主色照目前的強調色畫，選下去看到的就是那個樣子。
  final AppAccent accent;
  final ValueChanged<AppStyle> onSelected;

  static const int _columns = 5;
  static const double _columnGap = AppSpacing.md;
  static const double _rowGap = AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - _columnGap * (_columns - 1)) / _columns;
        return Wrap(
          spacing: _columnGap,
          runSpacing: _rowGap,
          children: [
            for (final style in AppStyle.values)
              SizedBox(
                width: width,
                child: _StyleCard(
                  style: style,
                  palette: style.paletteFor(brightness, accent),
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

/// 一張摺角書頁：閱讀紙色上一個「永」與幾條正文色細線，右上角摺起露出
/// 主色；風格名稱寫在頁下。選中時書頁浮起、加主色外框、名稱變粗。
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

  /// 選中時書頁往上浮起的距離。
  static const double _lift = 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppMotion.menu;
    final page = Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 7, 0),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          '永',
          // 書頁是縮圖，字跟著頁面大小，不隨系統字級放大。
          textScaler: TextScaler.noScaling,
          style: AppTextStyles.uiMd.copyWith(
            color: palette.readerText,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              // 浮起、外框與陰影隨選取一起漸變（0 未選、1 選中）。
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: selected ? 1 : 0),
                duration: duration,
                curve: AppMotion.menuCurve,
                child: page,
                builder: (context, t, child) => Transform.translate(
                  offset: Offset(0, -_lift * t),
                  child: CustomPaint(
                    painter: _FoldedPagePainter(
                      paper: palette.readerBackground,
                      ink: palette.readerText,
                      fold: palette.primary,
                      outline: Color.lerp(chrome.separator, scheme.primary, t)!,
                      outlineWidth:
                          AppGlass.hairline + (2 - AppGlass.hairline) * t,
                      elevation: 1 + 3 * t,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              style.label,
              // 窄螢幕加大字級時換行，不省略成「…」。
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSm.copyWith(
                color: selected ? scheme.onSurface : chrome.sectionText,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 摺角書頁：紙面、陰影與外框都沿同一條頁形（右上角斜切），外框跟著
/// 摺線走；紙上畫正文細線，摺過來的那一角是主色。
class _FoldedPagePainter extends CustomPainter {
  const _FoldedPagePainter({
    required this.paper,
    required this.ink,
    required this.fold,
    required this.outline,
    required this.outlineWidth,
    required this.elevation,
  });

  final Color paper;
  final Color ink;
  final Color fold;
  final Color outline;
  final double outlineWidth;
  final double elevation;

  static const double _foldSize = 14;

  /// 左側是裝訂邊，圓角比右側小一點。
  static const double _spineRadius = 4;
  static const double _edgeRadius = 7;

  /// 每行佔頁寬的比例；0 是段落間的空行。段首縮排一格。
  static const List<double> _lines = [0.92, 1, 0.78, 0, 0.86, 1, 0.55, 0, 0.9];
  static const Set<int> _paragraphStarts = {0, 4, 8};

  static Path _pagePath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(_spineRadius, 0)
      ..lineTo(w - _foldSize, 0)
      ..lineTo(w, _foldSize)
      ..lineTo(w, h - _edgeRadius)
      ..arcToPoint(
        Offset(w - _edgeRadius, h),
        radius: const Radius.circular(_edgeRadius),
      )
      ..lineTo(_spineRadius, h)
      ..arcToPoint(
        Offset(0, h - _spineRadius),
        radius: const Radius.circular(_spineRadius),
      )
      ..lineTo(0, _spineRadius)
      ..arcToPoint(
        const Offset(_spineRadius, 0),
        radius: const Radius.circular(_spineRadius),
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pagePath = _pagePath(size);
    canvas.drawShadow(pagePath, Colors.black, elevation, false);
    canvas.drawPath(pagePath, Paint()..color = paper);

    final left = size.width * 0.13;
    final right = size.width * 0.88;
    final lineWidth = right - left;
    const thickness = 2.5;
    const lineGap = 6.5;
    final paint = Paint()..color = ink.withValues(alpha: 0.33);
    var top = size.height * 0.36;
    for (var i = 0; i < _lines.length; i++) {
      if (top + thickness > size.height - 4) break;
      final factor = _lines[i];
      if (factor > 0) {
        final start = _paragraphStarts.contains(i)
            ? left + lineWidth * 0.2
            : left;
        final end = left + lineWidth * factor;
        if (end > start) {
          canvas.drawRRect(
            RRect.fromLTRBR(
              start,
              top,
              end,
              top + thickness,
              const Radius.circular(thickness / 2),
            ),
            paint,
          );
        }
      }
      top += factor > 0 ? lineGap : lineGap * 0.6;
    }

    // 摺過來的那一角，貼在紙面上。
    final w = size.width;
    final flap = Path()
      ..moveTo(w - _foldSize, 0)
      ..lineTo(w, _foldSize)
      ..lineTo(w - _foldSize, _foldSize)
      ..close();
    canvas.drawShadow(flap, Colors.black, 1.5, false);
    canvas.drawPath(flap, Paint()..color = fold);

    canvas.drawPath(
      pagePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth
        ..strokeJoin = StrokeJoin.round
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(_FoldedPagePainter oldDelegate) =>
      oldDelegate.paper != paper ||
      oldDelegate.ink != ink ||
      oldDelegate.fold != fold ||
      oldDelegate.outline != outline ||
      oldDelegate.outlineWidth != outlineWidth ||
      oldDelegate.elevation != elevation;
}
