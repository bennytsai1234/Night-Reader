import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import 'reader_v2_menu_palette.dart';

/// 閱讀器上方選單：浮在狀態列下方的玻璃列——兩側圓形玻璃按鈕、中間書名膠囊，
/// 開啟「標題附加資訊」時下方再浮一張章節資訊卡。
class ReaderV2TopMenu extends StatelessWidget {
  const ReaderV2TopMenu({
    super.key,
    required this.controlsVisible,
    required this.bookName,
    required this.chapterTitle,
    required this.chapterUrl,
    required this.originName,
    required this.showReadTitleAddition,
    required this.onBack,
    required this.onMore,
  });

  final bool controlsVisible;
  final String bookName;
  final String chapterTitle;
  final String chapterUrl;
  final String originName;
  final bool showReadTitleAddition;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final menuStyle = ReaderV2MenuStyle.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !controlsVisible,
        child: AnimatedSlide(
          duration: AppMotion.menu,
          curve: AppMotion.menuCurve,
          // 多移出一段，讓浮動玻璃的漫射陰影也一起離開畫面。
          offset: controlsVisible ? Offset.zero : const Offset(0, -1.3),
          // 玻璃元件的亮邊與陰影取自選單配色推導的主題，而非 App 主題。
          child: Theme(
            data: menuStyle.toSheetTheme(Theme.of(context)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppGrouped.margin,
                topInset + AppSpacing.xs,
                AppGrouped.margin,
                0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAppBar(context, menuStyle),
                  if (showReadTitleAddition) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _buildAdditionInfo(context, menuStyle),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, ReaderV2MenuStyle menuStyle) {
    final tint = menuStyle.glassTintOf(context);
    return Row(
      children: [
        GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          iconSize: 20,
          tooltip: '返回',
          tint: tint,
          color: menuStyle.foreground,
          onPressed: onBack,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SizedBox(
            height: AppGlass.buttonSize,
            child: GlassSurface(
              borderRadius: AppRadius.pillShape,
              tint: tint,
              shadow: false,
              grouped: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Center(
                  child: Text(
                    bookName,
                    style: AppTextStyles.titleSm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: menuStyle.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        GlassIconButton(
          icon: Icons.more_horiz_rounded,
          tooltip: '更多',
          tint: tint,
          color: menuStyle.foreground,
          onPressed: onMore,
        ),
      ],
    );
  }

  Widget _buildAdditionInfo(BuildContext context, ReaderV2MenuStyle menuStyle) {
    return GlassSurface(
      borderRadius: AppRadius.cardXl,
      tint: menuStyle.glassTintOf(context),
      grouped: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapterTitle,
                    style: AppTextStyles.labelSm.copyWith(
                      color: menuStyle.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (chapterUrl.isNotEmpty)
                    Text(
                      chapterUrl,
                      style: AppTextStyles.micro.copyWith(
                        color: menuStyle.mutedForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs / 2,
              ),
              decoration: BoxDecoration(
                color: menuStyle.accentMuted,
                borderRadius: AppRadius.pillShape,
              ),
              child: Text(
                originName,
                style: AppTextStyles.micro.copyWith(
                  color: menuStyle.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
