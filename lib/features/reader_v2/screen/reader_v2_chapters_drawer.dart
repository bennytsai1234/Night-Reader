import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/core/models/toc_volumes.dart';
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
import 'package:night_reader/shared/widgets/toc_volume_row.dart';
import 'package:night_reader/shared/widgets/drag_overflow_text.dart';

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
    this.shown,
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

  /// 面板在畫面上（`ReaderV2SidePanelController.shown`）。面板收著時一直掛著，
  /// 每次變成 true 就重設成剛打開的樣子：從目錄分頁開始、照目前這章重新決定
  /// 收起哪些卷並捲到這章，書籤與標註頁回到頂端；收著時不理會換章。沒給時
  /// 當作一直在畫面上。
  final ValueListenable<bool>? shown;
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

  /// 剛打開、下一次建畫面時重設（[ReaderV2ChaptersDrawer.shown]）。等到建
  /// 畫面時才做，用的是打開那一刻換上的最新目錄。
  bool _resetPending = false;

  /// 每次打開加一：書籤與標註清單照它重建，捲動位置與滑開的列回到原樣。
  int _opening = 0;

  bool get _isShown => widget.shown?.value ?? true;

  int get _currentChapterIndex => widget.currentChapter.value;

  /// 分卷與收起的卷；畫面上第幾列對到第幾章看 [_rows]。每次打開都照
  /// 目前這章重新決定收起哪些（[TocVolumes.initiallyCollapsed]）。
  late TocVolumes _volumes;
  late Set<int> _collapsed;
  late List<int> _rows;

  @override
  void initState() {
    super.initState();
    _resetVolumes();
    widget.listenable?.addListener(_handleChanged);
    widget.currentChapter.addListener(_handleCurrentChapterChanged);
    widget.shown?.addListener(_handleShown);
  }

  void _handleShown() {
    if (!mounted || !_isShown) return;
    setState(() => _resetPending = true);
  }

  /// 剛打開：回到從目錄分頁開始的樣子，捲到目前這章。
  void _resetForOpening() {
    _resetPending = false;
    _tab = _DrawerTab.chapters;
    _opening++;
    _resetVolumes();
    _lastScrolledChapterIndex = -1;
    _scheduleScrollToCurrentChapter();
  }

  void _resetVolumes() {
    _volumes = TocVolumes(widget.chapters);
    _collapsed = _volumes.initiallyCollapsed(_currentChapterIndex);
    _rows = _volumes.rows(_collapsed);
  }

  /// 目前這章所在的卷收著時展開，打勾的那章一定看得到。
  void _revealCurrentChapter() {
    final volume = _volumes.volumeAt(_currentChapterIndex);
    if (_collapsed.remove(volume)) _rows = _volumes.rows(_collapsed);
  }

  void _toggleVolume(int volume) {
    setState(() {
      if (!_collapsed.remove(volume)) _collapsed.add(volume);
      _rows = _volumes.rows(_collapsed);
    });
  }

  void _handleCurrentChapterChanged() {
    // 收著時不跟：下次打開時照當時的這章重設。
    if (!mounted || !_isShown) return;
    setState(_revealCurrentChapter);
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
    // 執行階段每次給一份新的清單；分卷的位置沒變（例如只多了新章）就
    // 沿用收起的卷，列照新的目錄重排。
    if (!identical(oldWidget.chapters, widget.chapters)) {
      final volumes = TocVolumes(widget.chapters);
      if (volumes.sameVolumes(_volumes)) {
        _volumes = volumes;
        _rows = volumes.rows(_collapsed);
      } else {
        _resetVolumes();
        _lastScrolledChapterIndex = -1;
      }
    }
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable?.removeListener(_handleChanged);
      widget.listenable?.addListener(_handleChanged);
      _lastScrolledChapterIndex = -1;
    }
    if (!identical(oldWidget.currentChapter, widget.currentChapter)) {
      oldWidget.currentChapter.removeListener(_handleCurrentChapterChanged);
      widget.currentChapter.addListener(_handleCurrentChapterChanged);
    }
    if (oldWidget.shown != widget.shown) {
      oldWidget.shown?.removeListener(_handleShown);
      widget.shown?.addListener(_handleShown);
    }
    _scheduleScrollToCurrentChapter();
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_handleChanged);
    widget.currentChapter.removeListener(_handleCurrentChapterChanged);
    widget.shown?.removeListener(_handleShown);
    _scrollController.dispose();
    super.dispose();
  }

  /// Telegram 式平面列：固定高度（捲動定位依賴 [_tileExtent]），
  /// 目前章節以主色加粗並在右側打勾，付費還沒買的章節右側鎖頭，列間以
  /// 髮絲線分隔。分卷是粗體的一列，點了收起或展開；卷內的章往右縮一個字。
  Widget _buildChapterTile(BuildContext context, int row) {
    final scheme = Theme.of(context).colorScheme;
    final index = _rows[row];
    final chapterTitle = widget.titleFor(index);
    final Widget tile;
    if (widget.chapters[index].isVolume) {
      tile = TocVolumeRow(
        title: chapterTitle,
        count: _volumes.countOf(index),
        collapsed: _collapsed.contains(index),
        onToggle: () => _toggleVolume(index),
      );
    } else {
      final isCurrentChapter = _currentChapterIndex == index;
      final Widget? trailing = isCurrentChapter
          ? Icon(Icons.check_rounded, size: 20, color: scheme.primary)
          : widget.chapters[index].isLocked
          ? const LockedChapterIcon()
          : null;
      tile = GroupedRow(
        title: chapterTitle,
        titleWidget: Padding(
          padding: EdgeInsets.only(
            left: _volumes.volumeOf(index) >= 0 ? tocChapterIndent : 0,
          ),
          child: DragOverflowText(child: Text(
            chapterTitle,
            maxLines: 1,
            style: AppTextStyles.bodyBase.copyWith(
              height: 1.3,
              color: isCurrentChapter ? scheme.primary : scheme.onSurface,
              fontWeight: isCurrentChapter ? FontWeight.w600 : FontWeight.w400,
            ),
          )),
        ),
        trailing: trailing,
        showChevron: false,
        onTap: () => widget.onChapterTap(index),
      );
    }
    return Column(
      children: [
        Expanded(child: Center(child: tile)),
        Container(
          height: AppGlass.hairline,
          margin: const EdgeInsets.only(left: AppGrouped.rowPadding),
          color: AppChrome.of(context).separator,
        ),
      ],
    );
  }

  void _scrollToCurrentChapter() {
    if (!mounted || !_isShown || !_scrollController.hasClients) return;
    final currentChapterIndex = _currentChapterIndex;
    if (currentChapterIndex == _lastScrolledChapterIndex) return;
    final row = _rows.indexOf(currentChapterIndex);
    if (row < 0) return;
    _lastScrolledChapterIndex = currentChapterIndex;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final viewportDimension = _scrollController.position.viewportDimension;
    final targetOffset =
        (row * _tileExtent) - ((viewportDimension - _tileExtent) / 2);
    final safeOffset = targetOffset.clamp(0.0, maxExtent);
    _scrollController.jumpTo(safeOffset);
  }

  /// 列高固定，畫面上的列直接由捲動位置換算；右側捲動條數的是列，不是章。
  (int, int)? _visibleRange() {
    if (!_scrollController.hasClients || _rows.isEmpty) return null;
    final position = _scrollController.position;
    final first = (position.pixels / _tileExtent).floor();
    final last =
        ((position.pixels + position.viewportDimension) / _tileExtent).ceil() -
        1;
    final maxIndex = _rows.length - 1;
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
    if (!mounted || !_isShown) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrentChapter(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_resetPending) _resetForOpening();
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
                child: _buildTabs(theme),
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
                    KeyedSubtree(
                      key: ValueKey(('bookmarks', _opening)),
                      child: _buildBookmarkList(context, bookmarks),
                    )
                  else
                    const SizedBox.shrink(),
                  if (widget.highlights case final highlights?)
                    KeyedSubtree(
                      key: ValueKey(('highlights', _opening)),
                      child: _buildHighlightList(context, highlights),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 三個分頁一直在；沒給書籤或標註（漫畫）時那一段灰掉（ADR 0059）。
  static const List<_DrawerTab> _tabs = _DrawerTab.values;

  bool _tabEnabled(_DrawerTab tab) => switch (tab) {
    _DrawerTab.chapters => true,
    _DrawerTab.bookmarks => widget.bookmarks != null,
    _DrawerTab.highlights => widget.highlights != null,
  };

  /// 頂端分段切換目錄、書籤與標註，右側寫這一頁有幾章、幾個書籤或標註；
  /// 標註頁另有「匯出」。
  Widget _buildTabs(ThemeData theme) {
    return Row(
      children: [
        GlassSegmented<_DrawerTab>(
          // 每次打開換一份：選取塊直接停在目錄，不從上次的分頁滑回來、和
          // 面板滑出疊在一起。同一次打開裡切分頁照常滑過去。
          key: ValueKey(('tabs', _opening)),
          expand: false,
          segments: [
            for (final tab in _tabs)
              GlassSegment(tab, tab.label, enabled: _tabEnabled(tab)),
          ],
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
            '共 ${_volumes.chapterCount} 章',
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

  /// 標註列：左邊一條標註的顏色，畫到的字（最多三行）、下面寫在哪一章與
  /// 備忘；往左滑刪除。
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
                      // 章名一行，有備忘時接在下面（最多兩行）。
                      subtitle: [
                        widget.highlightChapter == null
                            ? highlight.chapterTitle
                            : widget.titleFor(chapter),
                        if (highlight.note.isNotEmpty) highlight.note,
                      ].join('\n'),
                      maxSubtitleLines: highlight.note.isEmpty ? 1 : 3,
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
      itemCount: _rows.length,
      visibleRange: _visibleRange,
      onJumpTo: _jumpToChapterRow,
      labelFor: (row) => widget.titleFor(_rows[row]),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        itemCount: _rows.length,
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
