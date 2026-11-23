import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/chinese/chinese_display.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/book/toc_volumes.dart';
import 'package:night_reader/core/source_switch/chapter_borrow.dart';
import 'package:night_reader/features/book_detail/widgets/book_toc_chapter_row.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/book/toc_volume_row.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';

/// 單章借源面板裡借的書源的目錄（ADR 0080）：一打開就捲到估計是同一章的
/// [estimated] 並以主色標出（同目錄的「目前」），點一章交給 [onPick]；分卷
/// 標題點不了，付費章節右側鎖頭、點了交給 [onLocked]。
class BorrowChapterToc extends StatefulWidget {
  const BorrowChapterToc({
    super.key,
    required this.chapters,
    required this.estimated,
    required this.onPick,
    required this.onLocked,
  });

  final List<BookChapter> chapters;
  final int estimated;
  final ValueChanged<int> onPick;
  final VoidCallback onLocked;

  @override
  State<BorrowChapterToc> createState() => _BorrowChapterTocState();
}

class _BorrowChapterTocState extends State<BorrowChapterToc> {
  late final TocVolumes _volumes = TocVolumes(widget.chapters);
  ScrollController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// 列高固定（同閱讀器的目錄），估計的那一章一打開就停在清單中間。
  double get _rowExtent =>
      math.max(56.0, 20 + MediaQuery.textScalerOf(context).scale(15) * 1.3 + 2);

  @override
  Widget build(BuildContext context) {
    final extent = _rowExtent;
    final count = widget.chapters.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        _controller ??= ScrollController(
          initialScrollOffset: math.max(
            0,
            widget.estimated * extent - (constraints.maxHeight - extent) / 2,
          ),
        );
        return ListView.builder(
          controller: _controller,
          itemExtent: extent,
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.paddingOf(context).bottom + AppGrouped.sectionGap,
          ),
          itemCount: count,
          itemBuilder: (context, i) {
            final chapter = widget.chapters[i];
            final title = context.zh(chapter.title);
            return GroupedSliceItem(
              index: i,
              count: count,
              child: chapter.isVolume
                  ? TocVolumeRow(title: title, count: _volumes.countOf(i))
                  : BookTocChapterRow(
                      title: title,
                      indented:
                          _volumes.hasVolumes && _volumes.volumeOf(i) >= 0,
                      isCurrent: i == widget.estimated,
                      isLocked: chapter.isLocked,
                      onTap: chapter.isLocked
                          ? widget.onLocked
                          : chapterBorrowable(chapter)
                          ? () => widget.onPick(i)
                          : null,
                    ),
            );
          },
        );
      },
    );
  }
}
