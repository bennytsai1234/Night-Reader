import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/ui_text.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/popup_routes.dart';
import 'package:night_reader/shared/widgets/drag_overflow_text.dart';

/// Telegram 式底部面板：分組底色、拖曳把手、置中標題與右側圓形關閉鈕，
/// 下方為可捲動內容。
class AppBottomSheet extends StatelessWidget {
  final String title;

  /// 舊版標題旁的圖示；新版面板只顯示置中標題，保留參數讓既有呼叫端相容。
  final IconData? icon;
  final List<Widget> children;

  /// 滑入時內容先畫骨架，滑到位才在骨架底下逐列建立、再換成內容
  /// （[GroupedSheetContent]，ADR 0029）。骨架照分組卡片的樣子畫，只放
  /// 分組卡片的面板才開。
  final bool skeletonEntrance;

  /// 頁首右邊的動作；有它時關閉鈕移到左邊（docs/design/components.md
  /// 「左右各一顆」）。
  final Widget? trailing;
  final bool showDragHandle;

  /// 底欄最大高度佔螢幕高度的比例；需要同時看到正文的面板使用較小值。
  final double maxHeightFactor;

  const AppBottomSheet({
    super.key,
    required this.title,
    this.icon,
    required this.children,
    this.skeletonEntrance = false,
    this.trailing,
    this.showDragHandle = true,
    this.maxHeightFactor = 0.9,
  });

  static const double _handleWidth = 36;
  static const double _handleHeight = 5;

  /// 頁首左右的留白：按鈕的觸控範圍是 44、看得到的圓是 32，往外讓 6，
  /// 看得到的邊才和底下的卡片切齊。
  static const double _headerInset =
      AppGrouped.margin - (AppGlass.buttonSize - PanelButtons.size) / 2;

  /// 內容左右對齊分組卡片的外距，底下留一段空白。
  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(
    AppGrouped.margin,
    0,
    AppGrouped.margin,
    AppSpacing.xxl,
  );

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
    final close = GlassIconButton(
      icon: Icons.close_rounded,
      tooltip: '關閉',
      color: chrome.sectionText,
      onPressed: () => Navigator.maybePop(context),
    );
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
            PanelButtons(
              child: SizedBox(
                height: AppGlass.headerToolbarHeight,
                child: NavigationToolbar(
                  centerMiddle: true,
                  middleSpacing: AppSpacing.md,
                  // 左右各一顆：有右側動作時關閉在左邊；沒有時左邊空出和
                  // 關閉鈕一樣寬，長標題也留在正中。兩側照按鈕自己的大小置中，
                  // 不被撐高。
                  leading: trailing == null
                      ? const SizedBox(
                          width: _headerInset + AppGlass.buttonSize,
                        )
                      : Padding(
                          padding: const EdgeInsets.only(left: _headerInset),
                          child: Center(widthFactor: 1, child: close),
                        ),
                  middle: Semantics(
                    header: true,
                    child: DragOverflowText(
                      child: UiText(
                        title,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleSm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: _headerInset),
                    child: Center(widthFactor: 1, child: trailing ?? close),
                  ),
                ),
              ),
            ),

            // 可捲動的內容區域
            Flexible(
              child: skeletonEntrance
                  ? GroupedSheetContent(
                      padding: _contentPadding,
                      background: chrome.groupedBackground,
                      children: children,
                    )
                  : SingleChildScrollView(
                      padding: _contentPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: children,
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
  /// 底色之上。底色、把手與遮罩照當下的主題畫，面板開著時系統切換深淺也
  /// 跟著換；指定 [backgroundColor] 的面板在裡面自己照主題畫底色。
  static Future<T?> showCustom<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool useSafeArea = false,
    bool isDismissible = true,
    bool? showDragHandle,
    Color? backgroundColor,
    Color? barrierColor,
    ShapeBorder? shape,
    Clip? clipBehavior,
    BoxConstraints? constraints,
    bool raised = true,
  }) {
    // 面板裡的底色照面板的主題（深色往上一階，`sheetThemeOf`）；閱讀器面板
    // 用選單主題自己分層，給 raised: false。
    final origin = PopupOrigin.of(context);
    // 外殼不畫底色：外殼的顏色在打開時就定住，底色由裡面的 Material 照
    // 當下的主題畫。系統的把手畫在外殼裡、內容上方，底下就沒有底色，所以
    // 把手也由裡面畫（[_SheetDragHandle]）。
    final paintsSurface = backgroundColor == null;
    return pushAppSheet<T>(
      origin: origin,
      builder: (context) {
        Widget sheet = Builder(builder: builder);
        if (raised) sheet = DerivedTheme(derive: sheetThemeOf, child: sheet);
        if (paintsSurface) {
          sheet = _SheetSurface(
            raised: raised,
            // 沒指定時照 Material：主題要把手、而且拉得動才畫。
            showDragHandle:
                showDragHandle ??
                (isDismissible &&
                    (Theme.of(context).bottomSheetTheme.showDragHandle ??
                        false)),
            child: sheet,
          );
        }
        return origin.wrap(sheet);
      },
      // 不給時照 Material 3 預設：最寬 640、置中。
      constraints: constraints,
      barrierColor: barrierColor,
      // 讀螢幕軟體念遮罩的名字；不給時是 Material 的英文「Scrim」。
      barrierLabel: UiLanguageText.convert(context, '關閉'),
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      isDismissible: isDismissible,
      showDragHandle: paintsSurface ? false : showDragHandle,
      backgroundColor: backgroundColor ?? Colors.transparent,
      elevation: 0,
      shape:
          shape ??
          const RoundedRectangleBorder(borderRadius: AppRadius.topSheetXl),
      clipBehavior: clipBehavior ?? Clip.antiAlias,
    );
  }
}

/// 底部面板的底色（分組清單底色）與系統樣式的把手，照當下的主題畫。
///
/// 放在墊高一階的面板主題外面，和原本畫在外殼的 Material 同一個主題：
/// 把手顏色與預設字樣照外面的主題，只有底色取墊高後的那一階。
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({
    required this.raised,
    required this.showDragHandle,
    required this.child,
  });

  final bool raised;
  final bool showDragHandle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = raised ? sheetThemeOf(theme).extension<AppChrome>() : null;
    return Material(
      color: (chrome ?? AppChrome.of(context)).groupedBackground,
      child: showDragHandle
          ? Stack(
              alignment: Alignment.topCenter,
              children: [
                const _SheetDragHandle(),
                Padding(
                  padding: const EdgeInsets.only(top: kMinInteractiveDimension),
                  child: child,
                ),
              ],
            )
          : child,
    );
  }
}

/// 照 Material 3 底部面板的把手畫（`showDragHandle`）：32×4 的圓角條，
/// 置中在 48 見方的觸控範圍裡；讀螢幕軟體點了關閉面板。拖曳由整個面板
/// 接（`enableDrag`）；Material 在面板不能拉掉時還讓把手自己拉得動、滑鼠
/// 停在上面時換色，夜讀沒有這樣的面板，不照做。
class _SheetDragHandle extends StatelessWidget {
  const _SheetDragHandle();

  static const Size _defaultSize = Size(32, 4);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheetTheme = theme.bottomSheetTheme;
    final size = sheetTheme.dragHandleSize ?? _defaultSize;
    return Semantics(
      label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      container: true,
      button: true,
      onTap: () {
        // 照 Material：只關掉這個面板，而且它要在最上層。
        if (ModalRoute.of(context)?.isCurrent ?? false) {
          Navigator.pop(context);
        }
      },
      child: SizedBox(
        width: math.max(size.width, kMinInteractiveDimension),
        height: math.max(size.height, kMinInteractiveDimension),
        child: Center(
          child: Container(
            width: size.width,
            height: size.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size.height / 2),
              color:
                  sheetTheme.dragHandleColor ??
                  theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
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
        AppBottomSheet._headerInset,
        AppSpacing.sm,
        AppBottomSheet._headerInset,
        AppSpacing.xs,
      ),
      child: PanelButtons(
        child: SizedBox(
          height: AppGlass.buttonSize,
          child: NavigationToolbar(
            middleSpacing: AppSpacing.md,
            leading: leading,
            trailing: trailing,
            middle: Semantics(
              header: true,
              child: DragOverflowText(
                child: UiText(
                  title,
                  maxLines: 1,
                  style: AppTextStyles.titleMd.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 閱讀器面板內的區塊標題，字階與色彩同分組清單的組標題。
class SheetSection extends StatelessWidget implements GroupedSkeletonItem {
  final String title;
  const SheetSection({super.key, required this.title});

  static const EdgeInsets _padding = EdgeInsets.only(
    top: AppSpacing.xl,
    bottom: AppSpacing.sm,
  );

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => GroupedItemShape.text(
    context,
    title,
    style: GroupedSectionHeader.textStyle(context),
    width: width,
  ).padded(_padding);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _padding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: GroupedSectionHeader(title),
      ),
    );
  }
}
