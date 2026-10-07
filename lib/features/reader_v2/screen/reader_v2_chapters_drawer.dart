import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

class ReaderV2ChaptersDrawer extends StatefulWidget {
  const ReaderV2ChaptersDrawer({
    super.key,
    required this.chapters,
    required this.currentChapterIndex,
    required this.titleFor,
    required this.onChapterTap,
    required this.menuBackgroundColor,
    required this.menuTextColor,
    this.listenable,
  });

  final List<BookChapter> chapters;
  final int currentChapterIndex;
  final String Function(int index) titleFor;
  final Future<bool> Function(int index) onChapterTap;

  /// 目錄屬於閱讀選單區域，配色跟隨選單主題而非 App 主題。
  final Color menuBackgroundColor;
  final Color menuTextColor;
  final Listenable? listenable;

  @override
  State<ReaderV2ChaptersDrawer> createState() => _ReaderV2ChaptersDrawerState();
}

class _ReaderV2ChaptersDrawerState extends State<ReaderV2ChaptersDrawer> {
  static const double _tileExtent = 56.0;

  final ScrollController _scrollController = ScrollController();
  int _lastScrolledChapterIndex = -1;
  int? _pendingChapterIndex;

  @override
  void initState() {
    super.initState();
    widget.listenable?.addListener(_handleChanged);
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
    _scheduleScrollToCurrentChapter();
  }

  @override
  void dispose() {
    widget.listenable?.removeListener(_handleChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleChapterTap(int index) async {
    if (_pendingChapterIndex != null) return;
    setState(() => _pendingChapterIndex = index);

    late final bool succeeded;
    try {
      succeeded = await widget.onChapterTap(index);
    } finally {
      if (mounted) {
        setState(() => _pendingChapterIndex = null);
      }
    }

    if (!mounted || !succeeded || !Navigator.canPop(context)) return;
    Navigator.pop(context);
  }

  Widget _buildPendingIndicator(String chapterTitle) {
    return Semantics(
      container: true,
      label: '正在跳轉至$chapterTitle',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  VoidCallback? _chapterTapHandler(int index) {
    if (_pendingChapterIndex != null) return null;
    return () {
      unawaited(_handleChapterTap(index));
    };
  }

  /// Telegram 式平面列：固定高度（捲動定位依賴 [_tileExtent]），
  /// 目前章節以主色加粗並在右側打勾，列間以髮絲線分隔。
  Widget _buildChapterTile(BuildContext context, int index) {
    final scheme = Theme.of(context).colorScheme;
    final chapterTitle = widget.titleFor(index);
    final isCurrentChapter = widget.currentChapterIndex == index;
    final isPending = _pendingChapterIndex == index;
    final Widget? trailing = isPending
        ? _buildPendingIndicator(chapterTitle)
        : isCurrentChapter
        ? Icon(Icons.check_rounded, size: 20, color: scheme.primary)
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
              onTap: _chapterTapHandler(index),
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
    final currentChapterIndex = widget.currentChapterIndex;
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
    final menuStyle = ReaderV2MenuStyle.resolve(
      context: context,
      backgroundColor: widget.menuBackgroundColor,
      textColor: widget.menuTextColor,
    );
    final theme = menuStyle.toSheetTheme(Theme.of(context));
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
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: widget.chapters.length,
                itemExtent: _tileExtent,
                itemBuilder: _buildChapterTile,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
