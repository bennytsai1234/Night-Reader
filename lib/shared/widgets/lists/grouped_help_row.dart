import 'package:flutter/widgets.dart';

import '../popups/app_bottom_sheet.dart';
import '../skeleton/grouped_list_skeleton.dart';
import 'grouped_row.dart';
import 'grouped_section.dart';

/// 說明面板裡的一段：小標（可省）加一列一件事。
typedef HelpSection = ({String? heading, List<String> items});

/// 收起來的說明（ADR 0076）：卡片裡的一列，標題寫這段說明回答的問題
/// （「會送出什麼」「什麼時候同步」），點了開底部面板，面板裡小標分段、
/// 一列一件事。一頁最多一列。同一張卡片的其他列有列首圖示時它也帶一個
/// （[leading]）。
class GroupedHelpRow extends StatelessWidget
    implements GroupedRowLike, GroupedSkeletonItem {
  const GroupedHelpRow({
    super.key,
    required this.title,
    required this.sections,
    this.leading,
  });

  final String title;
  final List<HelpSection> sections;
  final Widget? leading;

  @override
  bool get hasLeading => leading != null;

  GroupedRow get _row =>
      GroupedRow(leading: leading, title: title, onTap: () {});

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row.skeletonShape(context, width: width);

  /// 打開說明面板；測試與其他入口也用它。
  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<HelpSection> sections,
  }) => AppBottomSheet.show<void>(
    context: context,
    title: title,
    children: [
      for (final section in sections)
        GroupedSection(
          header: section.heading,
          children: [
            for (final item in section.items)
              GroupedRow(title: item, showChevron: false),
          ],
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => GroupedRow(
    leading: leading,
    title: title,
    onTap: () => show(context, title: title, sections: sections),
  );
}
