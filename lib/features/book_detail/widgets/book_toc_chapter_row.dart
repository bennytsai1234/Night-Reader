import 'package:flutter/material.dart';
import 'package:night_reader/core/chinese/chinese_display.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/book/locked_chapter_icon.dart';
import 'package:night_reader/shared/widgets/book/toc_volume_row.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

import '../book_detail_provider.dart';

/// 書籍詳情目錄的第 [row] 列（[BookDetailProvider.filteredChapters]）：分卷
/// 或章節。頁面與資料到了之後的骨架（`BookDetailSkeleton`）用同一個，骨架
/// 照它排。[onOpen] 是點了章節。
Widget bookTocRow(
  BuildContext context,
  BookDetailProvider provider,
  int row, {
  ValueChanged<BookChapter>? onOpen,
}) {
  final chapter = provider.filteredChapters[row];
  final position = provider.displayPositionAt(row);
  final volumes = provider.tocVolumes;
  if (chapter.isVolume) {
    return TocVolumeRow(
      title: context.zh(chapter.title),
      count: volumes.countOf(position),
      collapsed: provider.groupsVolumes
          ? provider.isVolumeCollapsed(position)
          : null,
      onToggle: () => provider.toggleVolume(position),
    );
  }
  return BookTocChapterRow(
    title: context.zh(chapter.title),
    indented: provider.groupsVolumes && volumes.volumeOf(position) >= 0,
    isCurrent: chapter.index == provider.book.chapterIndex,
    isLocked: chapter.isLocked,
    onTap: onOpen == null ? null : () => onOpen(chapter),
  );
}

/// 目錄的一列章節：目前閱讀章節以主色標示，右側「目前」；付費還沒買的章節
/// 右側鎖頭。
class BookTocChapterRow extends StatelessWidget implements GroupedSkeletonItem {
  const BookTocChapterRow({
    super.key,
    required this.title,
    required this.indented,
    required this.isCurrent,
    required this.isLocked,
    required this.onTap,
  });

  final String title;

  /// 卷內的章往右縮一個字（目錄照卷分組時）。
  final bool indented;
  final bool isCurrent;
  final bool isLocked;
  final VoidCallback? onTap;

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row(context).skeletonShape(context, width: width);

  @override
  Widget build(BuildContext context) => _row(context);

  GroupedRow _row(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GroupedRow(
      title: title,
      translateTitle: false,
      titleWidget: Padding(
        padding: EdgeInsets.only(left: indented ? tocChapterIndent : 0),
        child: DragOverflowText(
          child: UiText(
            title,
            translate: false,
            maxLines: 1,
            style: AppTextStyles.bodyBase.copyWith(
              height: 1.3,
              color: isCurrent ? scheme.primary : scheme.onSurface,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
      showChevron: false,
      trailing: isCurrent
          ? UiText(
              '目前',
              style: AppTextStyles.labelSm.copyWith(color: scheme.primary),
            )
          : isLocked
          ? const LockedChapterIcon()
          : null,
      onTap: onTap,
    );
  }
}
