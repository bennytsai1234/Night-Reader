import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/chapter_scrollbar.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/locked_chapter_icon.dart';

class ReaderV2ChaptersDrawer extends StatefulWidget {
  const ReaderV2ChaptersDrawer({
    super.key,
    required this.chapters,
    required this.currentChapter,
    required this.titleFor,
    required this.onChapterTap,
    this.onClosed,
    this.listenable,
  });

  final List<BookChapter> chapters;

  /// 畫面上這一章（打勾、捲到它）。目錄開著時換章也跟著換。
  final ValueListenable<int> currentChapter;
  final String Function(int index) titleFor;

  /// 點了一章。收起目錄、蓋紙與載入都由呼叫端負責。
  final ValueChanged<int> onChapterTap;

  /// 目錄收到底、從畫面上拿掉時呼叫。Scaffold 的抽屜收完才卸下內容；
  /// [Scaffold.onDrawerChanged] 在收起動畫一開始就發，不能當成收完。
  final VoidCallback? onClosed;
  final Listenable? listenable;

  @override
  State<ReaderV2ChaptersDrawer> createState() => _ReaderV2ChaptersDrawerState();
}

class _ReaderV2ChaptersDrawerState extends State<ReaderV2ChaptersDrawer> {
  /// 列高：1 倍字級時固定 56，字級放大到放不下（GroupedRow 上下內距 20
  /// 加一行 15×1.3 的標題）時跟著長高。捲動定位用同一個值。
  double get _tileExtent =>
      math.max(56.0, 20 + MediaQuery.textScalerOf(context).scale(15) * 1.3 + 2);

  final ScrollController _scrollController = ScrollController();
  int _lastScrolledChapterIndex = -1;

  int get _currentChapterIndex => widget.currentChapter.value;

  @override
  void initState() {
    super.initState();
    widget.listenable?.addListener(_handleChanged);
    widget.currentChapter.addListener(_handleCurrentChapterChanged);
  }

  /// 目前章換了：只有打勾狀態改變的那兩列重建（[_CurrentChapterTile]），
  /// 清單本身不重建。原本整份重建，跳章一開始目前章就換成目標章，正在
  /// 收起的目錄約 30 列一起重建，落在跳章動畫的第一格（2026-10-29 量到）。
  void _handleCurrentChapterChanged() {
    if (!mounted) return;
    _scheduleScrollToCurrentChapter();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleScrollToCurrentChapter();
  }

  @override
  void didUpdateWidget(covariant ReaderV2ChaptersDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable?.removeListener(_handleChanged);
      widget.listenable?.addListener(_handleChanged);
      _lastScrolledChapterIndex = -1;
    }
    if (!identical(oldWidget.currentChapter, widget.currentChapter)) {
      oldWidget.currentChapter.removeListener(_handleCurrentChapterChanged);
      widget.currentChapter.addListener(_handleCurrentChapterChanged);
    }
    _scheduleScrollToCurrentChapter();
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_handleChanged);
    widget.currentChapter.removeListener(_handleCurrentChapterChanged);
    _scrollController.dispose();
    widget.onClosed?.call();
    super.dispose();
  }

  /// Telegram 式平面列：固定高度（捲動定位依賴 [_tileExtent]），
  /// 目前章節以主色加粗並在右側打勾，付費還沒買的章節右側鎖頭，列間以
  /// 髮絲線分隔。
  Widget _buildChapterTile(BuildContext context, int index) =>
      _CurrentChapterTile(
        index: index,
        currentChapter: widget.currentChapter,
        builder: (context, isCurrentChapter) =>
            _chapterTile(context, index, isCurrentChapter),
      );

  Widget _chapterTile(BuildContext context, int index, bool isCurrentChapter) {
    final scheme = Theme.of(context).colorScheme;
    final chapterTitle = widget.titleFor(index);
    final Widget? trailing = isCurrentChapter
        ? Icon(Icons.check_rounded, size: 20, color: scheme.primary)
        : index < widget.chapters.length && widget.chapters[index].isLocked
        ? const LockedChapterIcon()
        : null;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: GroupedRow(
              title: chapterTitle,
              titleWidget: Text(
                chapterTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyBase.copyWith(
                  height: 1.3,
                  color: isCurrentChapter ? scheme.primary : scheme.onSurface,
                  fontWeight: isCurrentChapter
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              trailing: trailing,
              showChevron: false,
              onTap: () => widget.onChapterTap(index),
            ),
          ),
        ),
        Container(
          height: AppGlass.hairline,
          margin: const EdgeInsets.only(left: AppGrouped.rowPadding),
          color: AppChrome.of(context).separator,
        ),
      ],
    );
  }

  void _scrollToCurrentChapter() {
    if (!mounted || !_scrollController.hasClients) return;
    final currentChapterIndex = _currentChapterIndex;
    if (currentChapterIndex == _lastScrolledChapterIndex) return;
    _lastScrolledChapterIndex = currentChapterIndex;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final viewportDimension = _scrollController.position.viewportDimension;
    final targetOffset =
        (currentChapterIndex * _tileExtent) -
        ((viewportDimension - _tileExtent) / 2);
    final safeOffset = targetOffset.clamp(0.0, maxExtent);
    _scrollController.jumpTo(safeOffset);
  }

  /// 列高固定，畫面上的列直接由捲動位置換算。
  (int, int)? _visibleRange() {
    if (!_scrollController.hasClients || widget.chapters.isEmpty) return null;
    final position = _scrollController.position;
    final first = (position.pixels / _tileExtent).floor();
    final last =
        ((position.pixels + position.viewportDimension) / _tileExtent).ceil() -
        1;
    final maxIndex = widget.chapters.length - 1;
    return (first.clamp(0, maxIndex), last.clamp(0, maxIndex));
  }

  void _jumpToChapterRow(int index) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (index * _tileExtent).clamp(0.0, position.maxScrollExtent),
    );
  }

  void _handleChanged() {
    _scheduleScrollToCurrentChapter();
  }

  void _scheduleScrollToCurrentChapter() {
    if (!mounted) return;
    // 目錄正在收起（例如點了一章、跳章開始時目前章換成目標章）：不捲。
    // 捲到遠處那一章，畫面上的列全部要新建，落在跳章動畫的第一格
    // （2026-10-29 量到 25ms 以上）；下次打開會重建、照常捲到目前章。
    if (!(Scaffold.maybeOf(context)?.isDrawerOpen ?? true)) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrentChapter(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 目錄屬於閱讀選單區域，配色取選單配色。
    final theme = ReaderV2MenuStyle.of(context).toSheetTheme(Theme.of(context));
    // 此處的 context 仍在 App 主題下，衍生色直接取選單主題上的擴充。
    final chrome = theme.extension<AppChrome>()!;
    return Theme(
      data: theme,
      child: Drawer(
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(AppRadius.xl),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppGrouped.margin,
                  AppSpacing.lg,
                  AppGrouped.margin,
                  AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        '目錄',
                        style: AppTextStyles.titleLg.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '共 ${widget.chapters.length} 章',
                      style: AppTextStyles.uiSm.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(height: AppGlass.hairline, color: chrome.separator),
            Expanded(
              child: ChapterScrollbar(
                itemCount: widget.chapters.length,
                visibleRange: _visibleRange,
                onJumpTo: _jumpToChapterRow,
                labelFor: widget.titleFor,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: _chapterList(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 章節清單：畫的內容（章節、目前章、列高、標題、底部內距）都沒變時給
  /// 同一個元件。`ListView.builder` 每次重建都把畫面上的列整批重建；閱讀頁
  /// 為了跳章、載入整頁重建時，正在收起的目錄約 30 列跟著重建，落在跳章
  /// 動畫的第一格（電腦上 30ms 以上，2026-10-29 量到）。
  Widget _chapterList(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final key = (
      widget.chapters,
      widget.chapters.length,
      _tileExtent,
      widget.titleFor,
      bottom,
    );
    final cached = _list;
    if (cached != null && key == _listKey) return cached;
    _listKey = key;
    return _list = ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: bottom),
      itemCount: widget.chapters.length,
      itemExtent: _tileExtent,
      itemBuilder: _buildChapterTile,
    );
  }

  Widget? _list;
  Object? _listKey;
}

/// 目錄的一列：自己聽目前章，只在「是不是目前這一章」改變時重建。
class _CurrentChapterTile extends StatefulWidget {
  const _CurrentChapterTile({
    required this.index,
    required this.currentChapter,
    required this.builder,
  });

  final int index;
  final ValueListenable<int> currentChapter;
  final Widget Function(BuildContext context, bool isCurrent) builder;

  @override
  State<_CurrentChapterTile> createState() => _CurrentChapterTileState();
}

class _CurrentChapterTileState extends State<_CurrentChapterTile> {
  late bool _current = widget.currentChapter.value == widget.index;

  @override
  void initState() {
    super.initState();
    widget.currentChapter.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(_CurrentChapterTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.currentChapter, widget.currentChapter)) {
      oldWidget.currentChapter.removeListener(_onChanged);
      widget.currentChapter.addListener(_onChanged);
    }
    _current = widget.currentChapter.value == widget.index;
  }

  void _onChanged() {
    final current = widget.currentChapter.value == widget.index;
    if (current != _current) setState(() => _current = current);
  }

  @override
  void dispose() {
    widget.currentChapter.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _current);
}
