import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/highlight_marks.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/chapter_scrollbar.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';
import 'package:night_reader/shared/widgets/locked_chapter_icon.dart';

/// 閱讀器左側的面板：「目錄」「書籤」「標註」三個分頁，頂端的分段切換。
class ReaderV2ChaptersDrawer extends StatefulWidget {
  const ReaderV2ChaptersDrawer({
    super.key,
    required this.chapters,
    required this.currentChapter,
    required this.titleFor,
    required this.onChapterTap,
    this.bookmarks,
    this.bookmarkChapter,
    this.onBookmarkTap,
    this.onBookmarkDelete,
    this.highlights,
    this.highlightChapter,
    this.onHighlightTap,
    this.onHighlightDelete,
    this.onHighlightExport,
    this.onClosed,
    this.listenable,
  });

  /// 這本書的書籤；書籤與標註都沒給就只有目錄、沒有分段。
  final ValueListenable<List<Bookmark>>? bookmarks;

  /// 書籤在這台目錄裡是第幾章（列上寫那一章的章名）。
  final int Function(Bookmark bookmark)? bookmarkChapter;

  /// 點了一個書籤。收起面板與跳過去都由呼叫端負責。
  final ValueChanged<Bookmark>? onBookmarkTap;

  /// 往左滑刪掉一個書籤。
  final ValueChanged<Bookmark>? onBookmarkDelete;

  /// 這本書的標註；沒給就沒有標註分頁。
  final ValueListenable<List<Highlight>>? highlights;

  /// 標註在這台目錄裡是第幾章（列上寫那一章的章名）。
  final int Function(Highlight highlight)? highlightChapter;

  /// 點了一個標註。收起面板與跳過去都由呼叫端負責。
  final ValueChanged<Highlight>? onHighlightTap;

  /// 往左滑刪掉一個標註。
  final ValueChanged<Highlight>? onHighlightDelete;

  /// 按了「匯出」，給照這台目錄排好的標註。
  final ValueChanged<List<Highlight>>? onHighlightExport;

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

  /// 正在看哪個分頁；每次打開都從目錄開始。
  _DrawerTab _tab = _DrawerTab.chapters;

  int get _currentChapterIndex => widget.currentChapter.value;

  @override
  void initState() {
    super.initState();
    widget.listenable?.addListener(_handleChanged);
    widget.currentChapter.addListener(_handleCurrentChapterChanged);
  }

  void _handleCurrentChapterChanged() {
    if (!mounted) return;
    setState(() {});
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
  Widget _buildChapterTile(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final chapterTitle = widget.titleFor(index);
    final isCurrentChapter = _currentChapterIndex == index;
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
                child: _tabs.length == 1
                    ? _buildTitle(theme)
                    : _buildTabs(theme),
              ),
            ),
            Container(height: AppGlass.hairline, color: chrome.separator),
            Expanded(
              // 每個分頁都留著：切回目錄時捲動位置不變。
              child: IndexedStack(
                index: _tabs.indexOf(_tab),
                sizing: StackFit.expand,
                children: [
                  _buildChapterList(context),
                  if (widget.bookmarks case final bookmarks?)
                    _buildBookmarkList(context, bookmarks),
                  if (widget.highlights case final highlights?)
                    _buildHighlightList(context, highlights),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Row(
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
        _countLabel(theme, '共 ${widget.chapters.length} 章'),
      ],
    );
  }

  /// 有哪些分頁：目錄一定有，書籤與標註有給才有。
  List<_DrawerTab> get _tabs => [
    _DrawerTab.chapters,
    if (widget.bookmarks != null) _DrawerTab.bookmarks,
    if (widget.highlights != null) _DrawerTab.highlights,
  ];

  /// 頂端分段切換目錄、書籤與標註，右側寫這一頁有幾章、幾個書籤或標註；
  /// 標註頁另有「匯出」。
  Widget _buildTabs(ThemeData theme) {
    return Row(
      children: [
        GlassSegmented<_DrawerTab>(
          expand: false,
          segments: [for (final tab in _tabs) GlassSegment(tab, tab.label)],
          selected: _tab,
          onChanged: (tab) {
            setState(() => _tab = tab);
            if (tab == _DrawerTab.chapters) _scheduleScrollToCurrentChapter();
          },
        ),
        const Spacer(),
        switch (_tab) {
          _DrawerTab.chapters => _countLabel(
            theme,
            '共 ${widget.chapters.length} 章',
          ),
          _DrawerTab.bookmarks => ValueListenableBuilder(
            valueListenable: widget.bookmarks!,
            builder: (context, items, _) => items.isEmpty
                ? const SizedBox.shrink()
                : _countLabel(theme, '${items.length} 個'),
          ),
          _DrawerTab.highlights => ValueListenableBuilder(
            valueListenable: widget.highlights!,
            builder: (context, items, _) => items.isEmpty
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _countLabel(theme, '${items.length} 個'),
                      if (widget.onHighlightExport case final onExport?)
                        IconButton(
                          tooltip: '匯出',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.ios_share_rounded, size: 20),
                          onPressed: () => onExport([
                            for (final row in _highlightRows(items))
                              row.highlight,
                          ]),
                        ),
                    ],
                  ),
          ),
        },
      ],
    );
  }

  Widget _countLabel(ThemeData theme, String text) => Text(
    text,
    style: AppTextStyles.uiSm.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  );

  /// 書籤列：選到的字（最多兩行）、下面寫在哪一章；往左滑刪除。
  Widget _buildBookmarkList(
    BuildContext context,
    ValueListenable<List<Bookmark>> bookmarks,
  ) {
    return ValueListenableBuilder(
      valueListenable: bookmarks,
      builder: (context, items, _) {
        if (items.isEmpty) {
          return const AppStateView(
            icon: Icons.bookmark_border_rounded,
            title: '沒有書籤',
          );
        }
        // 照在這台目錄裡的章排（書籤可能來自另一個書源，記下的序號是那邊
        // 的），同一章照第幾個字。
        final rows =
            [
              for (final bookmark in items)
                (
                  bookmark: bookmark,
                  chapter:
                      widget.bookmarkChapter?.call(bookmark) ??
                      bookmark.chapterIndex,
                ),
            ]..sort(
              (a, b) => a.chapter != b.chapter
                  ? a.chapter.compareTo(b.chapter)
                  : a.bookmark.charOffset.compareTo(b.bookmark.charOffset),
            );
        return SwipeActionsGroup(
          child: ListView.builder(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final (:bookmark, :chapter) = rows[index];
              final excerpt = bookmark.excerpt;
              return SwipeActions(
                key: ValueKey(bookmark.id),
                enabled: widget.onBookmarkDelete != null,
                trailing: [
                  SwipeAction(
                    label: '刪除',
                    icon: Icons.delete_outline_rounded,
                    color: AppTint.rust.color,
                    destructive: true,
                    onPressed: () => widget.onBookmarkDelete?.call(bookmark),
                  ),
                ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GroupedRow(
                      title: excerpt,
                      maxTitleLines: 2,
                      subtitle: widget.bookmarkChapter == null
                          ? bookmark.chapterTitle
                          : widget.titleFor(chapter),
                      maxSubtitleLines: 1,
                      showChevron: false,
                      onTap: () => widget.onBookmarkTap?.call(bookmark),
                    ),
                    Container(
                      height: AppGlass.hairline,
                      margin: const EdgeInsets.only(
                        left: AppGrouped.rowPadding,
                      ),
                      color: AppChrome.of(context).separator,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 照在這台目錄裡的章排（標註可能來自另一個書源），同一章照第幾個字。
  List<({Highlight highlight, int chapter})> _highlightRows(
    List<Highlight> items,
  ) =>
      [
        for (final highlight in items)
          (
            highlight: highlight,
            chapter:
                widget.highlightChapter?.call(highlight) ??
                highlight.chapterIndex,
          ),
      ]..sort(
        (a, b) => a.chapter != b.chapter
            ? a.chapter.compareTo(b.chapter)
            : a.highlight.charOffset.compareTo(b.highlight.charOffset),
      );

  /// 標註列：左邊一條標註的顏色，畫到的字（最多三行）、下面寫在哪一章；
  /// 往左滑刪除。
  Widget _buildHighlightList(
    BuildContext context,
    ValueListenable<List<Highlight>> highlights,
  ) {
    return ValueListenableBuilder(
      valueListenable: highlights,
      builder: (context, items, _) {
        if (items.isEmpty) {
          return const AppStateView(
            icon: Icons.border_color_outlined,
            title: '沒有標註',
          );
        }
        final rows = _highlightRows(items);
        return SwipeActionsGroup(
          child: ListView.builder(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final (:highlight, :chapter) = rows[index];
              return SwipeActions(
                key: ValueKey(highlight.id),
                enabled: widget.onHighlightDelete != null,
                trailing: [
                  SwipeAction(
                    label: '刪除',
                    icon: Icons.delete_outline_rounded,
                    color: AppTint.rust.color,
                    destructive: true,
                    onPressed: () => widget.onHighlightDelete?.call(highlight),
                  ),
                ],
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GroupedRow(
                      leading: HighlightColorBar(color: highlight.color),
                      title: highlight.quote,
                      maxTitleLines: 3,
                      subtitle: widget.highlightChapter == null
                          ? highlight.chapterTitle
                          : widget.titleFor(chapter),
                      maxSubtitleLines: 1,
                      showChevron: false,
                      onTap: () => widget.onHighlightTap?.call(highlight),
                    ),
                    Container(
                      height: AppGlass.hairline,
                      margin: const EdgeInsets.only(
                        left: AppGrouped.rowPadding,
                      ),
                      color: AppChrome.of(context).separator,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildChapterList(BuildContext context) {
    return ChapterScrollbar(
      itemCount: widget.chapters.length,
      visibleRange: _visibleRange,
      onJumpTo: _jumpToChapterRow,
      labelFor: widget.titleFor,
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        itemCount: widget.chapters.length,
        itemExtent: _tileExtent,
        itemBuilder: _buildChapterTile,
      ),
    );
  }
}

enum _DrawerTab {
  chapters('目錄'),
  bookmarks('書籤'),
  highlights('標註');

  const _DrawerTab(this.label);

  final String label;
}
