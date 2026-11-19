/// @docImport 'grouped_list.dart';
library;

import 'package:flutter/material.dart';

import '../../theme/app_chrome.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../text/ui_text.dart';
import 'swipe_actions.dart';

/// Telegram 式分組清單的一組：上方組標題、圓角卡片、下方附註。
///
/// 列與列之間自動插入髮絲分隔線；有任一列（[GroupedRowLike]，可包在
/// [SwipeActions]、[KeyedSubtree] 或單子元件的外框內）帶列首圖示時，分隔線
/// 從文字起點開始。分組本身帶上方間距，連續排列即可。
class GroupedSection extends StatelessWidget {
  const GroupedSection({
    super.key,
    this.header,
    this.headerTrailing,
    this.footer,
    required this.children,
    this.separatorIndent,
    this.margin,
    this.topGap = AppGrouped.sectionGap,
    this.translateHeader = true,
  });

  final String? header;

  /// 組標題是書名這類資料時給 false，不跟介面語言轉換（ADR 0066）。
  final bool translateHeader;

  /// 組標題右側的動作（例如「全部清除」）。
  final Widget? headerTrailing;

  /// 卡片下方的附註，只放狀態或數值（例如最近更新時間），不放功能說明（ADR 0009）。
  final String? footer;
  final List<Widget> children;

  /// 覆寫分隔線左縮排（列首不是 [GroupedIconTile] 寬度時使用）。
  final double? separatorIndent;

  /// 覆寫卡片外距；預設左右 [AppGrouped.margin]。
  final EdgeInsetsGeometry? margin;

  /// 組上方間距；清單第一組可傳較小值。
  final double topGap;

  /// 分隔線的左縮排：沒有覆寫時，有任一列帶列首圖示就從文字起點開始。
  double get _indent =>
      separatorIndent ??
      (children.any(groupedRowHasLeading)
          ? AppGrouped.separatorIndentWithIcon
          : AppGrouped.rowPadding);

  /// 同一組換上 [children] 與 [headerTrailing]（進場把列與組標題右側的按鈕
  /// 各包一層排隊時用），其他設定照舊。包了一層的列看不出有沒有列首圖示，
  /// 分隔線縮排先照原本的列算好。
  GroupedSection withRows(List<Widget> children, {Widget? headerTrailing}) =>
      GroupedSection(
        key: key,
        header: header,
        headerTrailing: headerTrailing,
        footer: footer,
        separatorIndent: _indent,
        margin: margin,
        topGap: topGap,
        translateHeader: translateHeader,
        children: children,
      );

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final indent = _indent;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(InsetSeparator(indent: indent));
      rows.add(children[i]);
    }
    final effectiveMargin =
        margin ?? const EdgeInsets.symmetric(horizontal: AppGrouped.margin);

    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null || headerTrailing != null)
            Padding(
              padding: effectiveMargin.add(
                const EdgeInsets.fromLTRB(
                  AppGrouped.rowPadding,
                  0,
                  AppGrouped.rowPadding,
                  AppSpacing.sm,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: GroupedSectionHeader(
                      header ?? '',
                      translate: translateHeader,
                    ),
                  ),
                  ?headerTrailing,
                ],
              ),
            ),
          Padding(
            padding: effectiveMargin,
            child: ClipRRect(
              borderRadius: AppGrouped.cardRadius,
              child: Material(
                color: chrome.groupedSurface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: rows,
                ),
              ),
            ),
          ),
          if (footer case final footer?)
            Padding(
              padding: effectiveMargin.add(
                const EdgeInsets.fromLTRB(
                  AppGrouped.rowPadding,
                  AppSpacing.sm,
                  AppGrouped.rowPadding,
                  0,
                ),
              ),
              child: UiText(
                footer,
                style: AppTextStyles.bodySm.copyWith(color: chrome.sectionText),
              ),
            ),
        ],
      ),
    );
  }
}

/// 惰性清單中的一列分組卡片切片。
///
/// [GroupedSection] 一次建出所有列；書源、章節這類可能上百列的清單改由
/// builder 逐列建立，每列自己畫出卡片的對應段落：第一列帶上圓角、最後一列
/// 帶下圓角，其餘列上方畫髮絲分隔線；連起來與 [GroupedSection] 的卡片一致。
/// 一段長內容切成好幾片（崩潰日誌）時 [separated] 是 false，片與片之間
/// 不畫線，看起來是同一列。
class GroupedSliceItem extends StatelessWidget {
  const GroupedSliceItem({
    super.key,
    required this.index,
    required this.count,
    required this.child,
    this.separatorIndent = AppGrouped.rowPadding,
    this.separated = true,
  });

  final int index;
  final int count;
  final Widget child;
  final double separatorIndent;
  final bool separated;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final first = index == 0;
    final last = index == count - 1;
    const corner = Radius.circular(AppGrouped.radius);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: first ? corner : Radius.zero,
          bottom: last ? corner : Radius.zero,
        ),
        child: Material(
          color: chrome.groupedSurface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!first && separated) InsetSeparator(indent: separatorIndent),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 從 [indent] 起畫的髮絲分隔線；分組卡片與平鋪清單（搜尋結果、發現書籍）
/// 的列間共用。
class InsetSeparator extends StatelessWidget {
  const InsetSeparator({super.key, required this.indent});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: Container(
        height: AppGlass.hairline,
        color: AppChrome.of(context).separator,
      ),
    );
  }
}

/// 分組卡片內的一列；[GroupedSection] 依 [hasLeading] 決定分隔線縮排。
/// 包裝 [GroupedRow] 的元件（開關列、勾選列、頁面私有的列）實作此介面。
abstract interface class GroupedRowLike {
  /// 是否帶列首圖示。
  bool get hasLeading;
}

/// 穿過常見外框（滑動動作、key、單子元件）找出列本身，判斷是否帶列首圖示。
bool groupedRowHasLeading(Widget widget) => switch (widget) {
  GroupedRowLike row => row.hasLeading,
  SwipeActions(:final child) => groupedRowHasLeading(child),
  KeyedSubtree(:final child) => groupedRowHasLeading(child),
  ProxyWidget(:final child) => groupedRowHasLeading(child),
  SingleChildRenderObjectWidget(:final child?) => groupedRowHasLeading(child),
  _ => false,
};

/// 組標題文字；也可單獨用在非卡片內容（例如格狀選項）上方。
class GroupedSectionHeader extends StatelessWidget {
  const GroupedSectionHeader(this.text, {super.key, this.translate = true});

  final String text;

  /// 組標題是書名這類資料時給 false，不跟介面語言轉換（ADR 0066）。
  final bool translate;

  /// 組標題的字樣；骨架照同一份字樣量組標題的高度。
  static TextStyle textStyle(BuildContext context) =>
      AppTextStyles.uiSm.copyWith(
        color: AppChrome.of(context).sectionText,
        fontWeight: FontWeight.w400,
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: UiText(text, translate: translate, style: textStyle(context)),
    );
  }
}

/// 卡片內的自由內容（數值步進器、色票、預覽等），套用列的內距。
class GroupedContent extends StatelessWidget {
  const GroupedContent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppGrouped.rowPadding,
      vertical: AppSpacing.md,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
  }
}
