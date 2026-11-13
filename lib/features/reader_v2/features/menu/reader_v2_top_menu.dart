import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import 'reader_v2_bottom_menu.dart' show ReaderV2ChapterNavigationState;
import 'reader_v2_menu_entrance.dart';
import 'reader_v2_menu_palette.dart';

import 'package:night_reader/shared/widgets/drag_overflow_text.dart';

/// 閱讀器上方選單：浮在狀態列下方的玻璃列——兩側圓形玻璃按鈕、中間書名膠囊，
/// 開啟「標題附加資訊」時下方再浮一張章節資訊卡。
class ReaderV2TopMenu extends StatelessWidget {
  const ReaderV2TopMenu({
    super.key,
    required this.controlsVisible,
    required this.bookName,
    required this.navigation,
    required this.originName,
    required this.showReadTitleAddition,
    required this.onBack,
    required this.onMore,
    this.onOpenOrigin,
    this.horizontalInset = AppGrouped.margin,
  });

  /// 左右離畫面邊的距離；正文欄照每行字數收窄時對齊正文的左右邊。
  final double horizontalInset;

  /// 選單開著；只有滑動那一層聽它（見 [ReaderV2MenuEntrance]）。
  final ValueListenable<bool> controlsVisible;
  final String bookName;

  /// 章節卡的章名照它的目前章。
  final ReaderV2ChapterNavigationState navigation;
  final String originName;
  final bool showReadTitleAddition;
  final VoidCallback onBack;
  final VoidCallback onMore;

  /// 點書源膠囊：用瀏覽器開這一章的網頁；null（本地書）時膠囊不能點。
  final VoidCallback? onOpenOrigin;

  @override
  Widget build(BuildContext context) {
    final menuStyle = ReaderV2MenuStyle.of(context);
    final topInset = MediaQuery.paddingOf(context).top;
    return ReaderV2MenuEntrance(
      visible: controlsVisible,
      edge: AxisDirection.up,
      // 玻璃元件的亮邊與陰影取自選單配色推導的主題，而非 App 主題。
      child: Theme(
        data: menuStyle.toSheetTheme(Theme.of(context)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalInset,
            topInset + AppSpacing.xs,
            horizontalInset,
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
                  child: DragOverflowText(
                    child: Text(
                      bookName,
                      style: AppTextStyles.titleSm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: menuStyle.foreground,
                      ),
                      maxLines: 1,
                    ),
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
              // 只有章名聽換章（捲動途中換章不重建選單）。
              child: ValueListenableBuilder<int>(
                valueListenable: navigation.current,
                builder: (context, _, _) => DragOverflowText(
                  child: Text(
                    navigation.currentTitle,
                    style: AppTextStyles.labelSm.copyWith(
                      color: menuStyle.foreground,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
            if (originName.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.md),
              // 書源名稱可能很長；膠囊限寬（360 寬的畫面約四成），章節名稱
              // 才不會被擠掉。
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: _originTap(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs / 2,
                    ),
                    decoration: BoxDecoration(
                      color: menuStyle.accentMuted,
                      borderRadius: AppRadius.pillShape,
                    ),
                    child: DragOverflowText(
                      child: Text(
                        originName,
                        maxLines: 1,
                        style: AppTextStyles.micro.copyWith(
                          color: menuStyle.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _originTap({required Widget child}) {
    final onTap = onOpenOrigin;
    if (onTap == null) return child;
    return Semantics(
      button: true,
      hint: '用瀏覽器開這一章',
      child: PressScale(onTap: onTap, child: child),
    );
  }
}
