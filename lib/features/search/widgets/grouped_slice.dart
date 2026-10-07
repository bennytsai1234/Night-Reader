import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 惰性清單中的一列分組卡片切片。
///
/// [GroupedSection] 一次建出所有列；書源、章節這類可能上百列的清單改由
/// builder 逐列建立，每列自己畫出卡片的對應段落：第一列帶上圓角、最後一列
/// 帶下圓角，其餘列上方畫髮絲分隔線，連起來與 [GroupedSection] 的卡片一致。
class GroupedSliceItem extends StatelessWidget {
  const GroupedSliceItem({
    super.key,
    required this.index,
    required this.count,
    required this.child,
    this.separatorIndent = AppGrouped.rowPadding,
  });

  final int index;
  final int count;
  final Widget child;
  final double separatorIndent;

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
              if (!first)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: separatorIndent),
                  child: Container(
                    height: AppGlass.hairline,
                    color: chrome.separator,
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 平鋪清單（搜尋結果、發現書籍）的列間分隔線，從文字起點開始。
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
