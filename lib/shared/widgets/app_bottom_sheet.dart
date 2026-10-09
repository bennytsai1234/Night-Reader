import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

/// Telegram 式底部面板：分組底色、拖曳把手、置中標題與右側圓形關閉鈕，
/// 下方為可捲動內容。
class AppBottomSheet extends StatelessWidget {
  final String title;

  /// 舊版標題旁的圖示；新版面板只顯示置中標題，保留參數讓既有呼叫端相容。
  final IconData? icon;
  final List<Widget> children;

  /// 關閉鈕左側的附加動作。
  final Widget? trailing;
  final bool showDragHandle;

  /// 底欄最大高度佔螢幕高度的比例；需要同時看到正文的面板使用較小值。
  final double maxHeightFactor;

  const AppBottomSheet({
    super.key,
    required this.title,
    this.icon,
    required this.children,
    this.trailing,
    this.showDragHandle = true,
    this.maxHeightFactor = 0.9,
  });

  static const double _handleWidth = 36;
  static const double _handleHeight = 5;
  static const double _closeSize = 32;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    // 底部面板不會自己避開鍵盤：整個面板墊高鍵盤的高度，可捲動區也跟著
    // 縮小，靠近底部的輸入框才捲得到鍵盤上方。
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight =
        (MediaQuery.sizeOf(context).height - keyboard) * maxHeightFactor;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: _buildBody(context, scheme, chrome, maxHeight),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme scheme,
    AppChrome chrome,
    double maxHeight,
  ) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 把手與標題列固定不捲動。
            if (showDragHandle)
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  width: _handleWidth,
                  height: _handleHeight,
                  decoration: BoxDecoration(
                    color: chrome.sectionText.withValues(alpha: 0.35),
                    borderRadius: AppRadius.pillShape,
                  ),
                ),
              ),
            SizedBox(
              height: AppGlass.headerToolbarHeight,
              child: NavigationToolbar(
                centerMiddle: true,
                middleSpacing: AppSpacing.md,
                // 左側放一塊與關閉鈕等寬的空白，讓沒有 trailing 時標題也真正置中。
                leading: const SizedBox(
                  width: AppGrouped.margin + AppGlass.buttonSize,
                ),
                middle: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleSm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(right: AppGrouped.margin),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (trailing != null) ...[
                        trailing!,
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      GlassIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '關閉',
                        size: _closeSize,
                        iconSize: 18,
                        color: chrome.sectionText,
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 可捲動的內容區域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppGrouped.margin,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...children,
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 靜態便捷方法：顯示標準底欄
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    IconData? icon,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return showCustom<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => AppBottomSheet(
        title: title,
        icon: icon,
        trailing: trailing,
        children: children,
      ),
    );
  }

  /// 顯示需要自訂內容與狀態管理的底部工作表，同時統一外層底色、形狀與裁切。
  ///
  /// 未指定 [backgroundColor] 時使用分組清單底色，讓面板內的分組卡片浮在
  /// 底色之上。
  static Future<T?> showCustom<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool useSafeArea = false,
    bool? showDragHandle,
    Color? backgroundColor,
    Color? barrierColor,
    ShapeBorder? shape,
    Clip? clipBehavior,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      barrierColor: barrierColor ?? AppChrome.of(context).barrier,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      showDragHandle: showDragHandle,
      backgroundColor:
          backgroundColor ?? AppChrome.of(context).groupedBackground,
      elevation: 0,
      shape:
          shape ??
          const RoundedRectangleBorder(borderRadius: AppRadius.topSheetXl),
      clipBehavior: clipBehavior ?? Clip.antiAlias,
    );
  }
}

/// 分組樣式底部面板的標題列：置中標題、兩側放文字或圓形玻璃按鈕。
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.sm,
        AppGrouped.margin,
        AppSpacing.xs,
      ),
      child: SizedBox(
        height: AppGlass.buttonSize,
        child: NavigationToolbar(
          middleSpacing: AppSpacing.md,
          leading: leading,
          trailing: trailing,
          middle: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMd.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 閱讀器面板內的區塊標題，字階與色彩同分組清單的組標題。
class SheetSection extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SheetSection({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: GroupedSectionHeader(title)),
          ?trailing,
        ],
      ),
    );
  }
}
