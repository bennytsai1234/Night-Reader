import 'dart:async';
import 'dart:io';

import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';
import 'package:super_sliver_list/super_sliver_list.dart' as super_list;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';
import 'package:night_reader/features/book_detail/change_cover_sheet.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_reading_state.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/export_book_service.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/features/source_manager/source_debug_page.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';

import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/chapter_scrollbar.dart';
import 'package:night_reader/shared/widgets/locked_chapter_icon.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'widgets/book_cover_ambience.dart';
import 'widgets/book_detail_skeleton.dart';
import 'widgets/book_info_header.dart';
import 'widgets/book_info_intro.dart';
import 'widgets/book_info_toc_bar.dart';
import 'widgets/book_read_capsule.dart';
import 'widgets/change_source_sheet.dart';

import 'package:night_reader/core/services/chinese_display.dart';

class BookDetailPage extends StatefulWidget {
  final Book? book;
  final AggregatedSearchBook? searchBook;

  /// 從閱讀器的「更多」開啟：閱讀鈕與點目錄回到原本的閱讀器（點章節時以
  /// 章節網址為結果 pop：這裡的目錄可能比閱讀器手上的新，序號對不上），
  /// 不另開一個閱讀器；加入／移出書架與換源留給
  /// 閱讀器自己處理，這裡不顯示，免得刪掉正在讀的正文或換掉書。
  final bool fromReader;

  const BookDetailPage({
    super.key,
    this.book,
    this.searchBook,
    this.fromReader = false,
  }) : assert(book != null || searchBook != null);

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

enum _MenuAction {
  checkUpdate,
  autoUpdate,
  download,
  changeCover,
  export,
  edit,
}

class _BookDetailPageState extends State<BookDetailPage> {
  final ScrollController _scrollController = ScrollController();
  final super_list.ListController _chapterListController =
      super_list.ListController();
  final GlobalKey _tocKey = GlobalKey();

  /// 匯出全書的進度（0–1）；null 表示沒有在匯出。
  double? _exportProgress;

  /// 大頁首捲進玻璃頁首底下後，頁首標題淡入顯示書名。
  final ValueNotifier<bool> _titleCollapsed = ValueNotifier(false);

  /// 有封面氛圍時，玻璃頁首在頁頂是透明的，讓氛圍鋪到頁首後面；往下捲
  /// 到氛圍離開頁首時變回實色底（0 透明、1 實色）。
  final ValueNotifier<double> _headerSolidity = ValueNotifier(0);

  /// 進場動畫播完時完成；詳情等它才開始載入（ADR 0018）。
  Future<void>? _entrance;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entrance ??= TransitionSettled.entered(context);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _titleCollapsed.dispose();
    _headerSolidity.dispose();
    _chapterListController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    _titleCollapsed.value = offset > BookInfoHeader.collapseOffset;
    _headerSolidity.value = (offset / BookInfoHeader.titleTop).clamp(0.0, 1.0);
  }

  /// 玻璃頁首（狀態列＋工具列＋漸隱）佔用的高度。
  double _headerExtent(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      AppGlass.headerToolbarHeight +
      AppGlass.headerFadeHeight;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BookDetailProvider(
        widget.searchBook ??
            AggregatedSearchBook(book: widget.book!, sources: []),
        entrance: _entrance!,
      ),
      child: Consumer<BookDetailProvider>(
        builder: (context, provider, child) {
          final chrome = AppChrome.of(context);
          return Scaffold(
            extendBodyBehindAppBar: true,
            extendBody: true,
            backgroundColor: chrome.groupedBackground,
            appBar: _buildHeader(context, provider),
            // 內距要從 Scaffold 內取得：延伸到頁首下方時 top 才包含頁首高度，
            // bottom 才包含底部的浮動閱讀鈕。
            body: Builder(
              builder: (bodyContext) => Stack(
                children: [
                  Positioned.fill(
                    child: provider.loadErrorMessage != null
                        ? _buildLoadError(bodyContext, provider)
                        : _buildContent(bodyContext, provider),
                  ),
                  // 閱讀鈕後方墊一條漸隱帶，同主頁分頁列：簡介與目錄捲到
                  // 膠囊之前就淡出，不會從它上下透出來。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: FloatingTabBarFade(
                      color: chrome.groupedBackground,
                      hidden: !provider.hasReadyWorld,
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: BookReadCapsule(
              started: provider.book.hasStartedReading,
              visible: provider.hasReadyWorld,
              onPressed: widget.fromReader
                  ? () => Navigator.of(context).pop()
                  : () => _navigateToReader(
                      context,
                      provider.book,
                      ReaderV2OpenTarget.resume(provider.book),
                      provider.allChapters,
                    ),
            ),
          );
        },
      ),
    );
  }

  /// 有沒有封面氛圍；沒有時頁首維持實色。
  bool _hasAmbience(BookDetailProvider provider) =>
      BookCoverAmbience.supports(UnifiedCovers.coverOf(provider.book));

  /// 書名、作者與封面一進頁就畫出，載入中只有動作按鈕與頁首以下顯示
  /// 骨架；資料到了照骨架換場（[SliverSkeletonSwitcher]）換成內容。
  Widget _buildContent(BuildContext context, BookDetailProvider provider) {
    final currentBook = provider.book;
    final padding = MediaQuery.paddingOf(context);
    final ambience = _hasAmbience(provider);
    final loading = provider.isLoading;
    final chapters = provider.filteredChapters;
    return ChapterScrollbar(
      itemCount: loading ? 0 : chapters.length,
      visibleRange: () => _chapterListController.isAttached
          ? _chapterListController.visibleRange
          : null,
      onJumpTo: (index) => _jumpToTocRow(context, index),
      labelFor: (index) => context.zh(chapters[index].title),
      padding: EdgeInsets.only(
        top: _headerExtent(context),
        bottom: padding.bottom,
      ),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                if (ambience)
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    // 書名之前完全漸隱成底色，書名與作者畫在純底色上。
                    height: padding.top + BookInfoHeader.titleTop,
                    child: BookCoverAmbience(
                      coverUrl: UnifiedCovers.coverOf(currentBook),
                      bookName: context.zh(currentBook.name),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(top: padding.top),
                  child: BookInfoHeader(
                    book: currentBook,
                    provider: provider,
                    loading: loading,
                    showPhotoView: _showPhotoView,
                    onToggleBookshelf: widget.fromReader
                        ? null
                        : () => _handleBookshelfToggle(context, provider),
                    onChangeSource: currentBook.isLocal || widget.fromReader
                        ? null
                        : () => _showChangeSourceDialog(context, provider),
                    onShowToc: _scrollToToc,
                  ),
                ),
              ],
            ),
          ),
          // 骨架照這一輪載入開始時手上的書排；資料到了先在骨架底下排好
          // 內容，再照骨架換場的設定換過去，骨架不跟著新資料變形。
          SliverSkeletonSwitcher(
            loading: loading,
            skeleton: BookDetailSkeleton(book: provider.skeletonBook),
            builder: (context) => _buildLoadedSlivers(context, provider),
          ),
          // 底部讓出浮動閱讀鈕（已含在 padding.bottom 裡）。
          SliverPadding(
            padding: EdgeInsets.only(bottom: padding.bottom + AppSpacing.md),
          ),
        ],
      ),
    );
  }

  /// 拖動目錄捲軸：第 [index] 列停在玻璃頁首下方。
  void _jumpToTocRow(BuildContext context, int index) {
    if (!_chapterListController.isAttached || !_scrollController.hasClients) {
      return;
    }
    final viewport = _scrollController.position.viewportDimension;
    _chapterListController.jumpToItem(
      index: index,
      scrollController: _scrollController,
      alignment: viewport <= 0
          ? 0
          : (_headerExtent(context) / viewport).clamp(0.0, 0.5),
    );
  }

  /// 載入完成後頁首以下的內容。跟著骨架換場出現的區塊不另外淡；之後才
  /// 出現的（例如目錄搜尋沒有結果的提示）第一次出現時淡入。
  List<Widget> _buildLoadedSlivers(
    BuildContext context,
    BookDetailProvider provider,
  ) {
    final currentBook = provider.book;
    final chapters = provider.filteredChapters;
    Widget fadeIn(String key, Widget sliver) =>
        SliverFadeIn(key: ValueKey(key), sliver: sliver);
    return [
      if ((provider.sourceIssueMessage ?? '').isNotEmpty)
        fadeIn(
          'source-issue',
          SliverToBoxAdapter(
            child: GroupedSection(
              topGap: AppSpacing.xl,
              children: [
                GroupedRow(
                  title: provider.sourceIssueMessage!,
                  leading: const GroupedIconTile(
                    Icons.warning_amber_rounded,
                    tint: AppTint.tea,
                  ),
                  // 要登入才讀得到：點了去登入，登入完重新載入（ADR 0038）。
                  value: provider.loginRequired ? '登入' : null,
                  onTap: provider.loginRequired
                      ? () => unawaited(_login(context, provider))
                      : null,
                ),
              ],
            ),
          ),
        ),
      fadeIn(
        'details',
        SliverToBoxAdapter(
          child: BookInfoDetails(
            book: currentBook,
            provider: provider,
            onShowSourceOptions: () => _showSourceOptions(context, currentBook),
          ),
        ),
      ),
      fadeIn(
        'intro',
        SliverToBoxAdapter(child: BookInfoIntro(book: currentBook)),
      ),
      SliverToBoxAdapter(child: SizedBox(key: _tocKey)),
      fadeIn(
        'toc-bar',
        BookInfoTocBar(
          provider: provider,
          onSearch: () => _showSearchTocDialog(context, provider),
          onLocateCurrent: () => _locateCurrentChapter(context, provider),
        ),
      ),
      if (provider.hasActiveTocSearch && chapters.isEmpty)
        fadeIn(
          'toc-empty',
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xxxl,
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.search_off,
                    size: 44,
                    color: AppChrome.of(context).sectionText,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '找不到相符章節',
                    style: AppTextStyles.bodyBase.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GlassTextButton(
                    label: '清除搜尋',
                    onPressed: provider.clearTocSearch,
                    // 同目錄組標題的按鈕：在頁面底色上跟著淡入，不模糊。
                    blur: false,
                  ),
                ],
              ),
            ),
          ),
        )
      else
        fadeIn(
          'toc',
          super_list.SuperSliverList(
            listController: _chapterListController,
            delegate: SliverChildBuilderDelegate((ctx, i) {
              final chapter = chapters[i];
              final isCurrent = chapter.index == currentBook.chapterIndex;
              return GroupedSliceItem(
                index: i,
                count: chapters.length,
                child: _ChapterRow(
                  title: ctx.zh(chapter.title),
                  isCurrent: isCurrent,
                  isLocked: chapter.isLocked,
                  onTap: widget.fromReader
                      ? () => Navigator.of(context).pop(chapter.url)
                      : () => _navigateToReader(
                          context,
                          currentBook,
                          ReaderV2OpenTarget.chapterStart(chapter.index),
                          provider.allChapters,
                        ),
                ),
              );
            }, childCount: chapters.length),
          ),
        ),
    ];
  }

  Widget _buildLoadError(BuildContext context, BookDetailProvider provider) {
    final padding = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: AppStateView(
        icon: Icons.error_outline,
        title: '書籍載入失敗',
        description: provider.loadErrorMessage,
        tone: AppStateTone.error,
        primaryAction: AppStateAction(
          label: '重試',
          icon: Icons.refresh,
          onPressed: provider.retryInitialization,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildHeader(
    BuildContext context,
    BookDetailProvider provider,
  ) {
    final failed = provider.loadErrorMessage != null;
    final background = AppChrome.of(context).groupedBackground;
    GlassNavHeader header(Color background) =>
        _buildNavHeader(context, provider, background, failed: failed);
    // 沒有封面氛圍時頁首維持實色；有的話跟著捲動由透明轉實色。
    if (failed || !_hasAmbience(provider)) return header(background);
    return PreferredSize(
      preferredSize: header(background).preferredSize,
      child: ValueListenableBuilder<double>(
        valueListenable: _headerSolidity,
        builder: (context, solidity, _) =>
            header(background.withValues(alpha: solidity)),
      ),
    );
  }

  GlassNavHeader _buildNavHeader(
    BuildContext context,
    BookDetailProvider provider,
    Color background, {
    required bool failed,
  }) {
    final actionsEnabled = !provider.isLoading && !failed;
    return GlassNavHeader(
      backgroundColor: background,
      titleWidget: ValueListenableBuilder<bool>(
        valueListenable: _titleCollapsed,
        // 書名一進頁就畫在大頁首裡，捲上去之後才由頁首標題接手。
        builder: (context, collapsed, _) => NavHeaderTitle(
          failed ? '書籍詳情' : context.zh(provider.book.name),
          visible: collapsed || failed,
        ),
      ),
      actions: [
        GlassMenuButton<_MenuAction>(
          enabled: actionsEnabled,
          onSelected: (v) => _handleMenuSelection(context, provider, v),
          entriesBuilder: (ctx) => [
            if (!provider.book.isLocal)
              GlassMenuItem(
                value: _MenuAction.checkUpdate,
                label: provider.isCheckingUpdate ? '正在檢查更新…' : '檢查更新',
                icon: Icons.update_rounded,
                enabled: !provider.isCheckingUpdate,
              ),
            if (!provider.book.isLocal && provider.isInBookshelf)
              GlassMenuItem(
                value: _MenuAction.autoUpdate,
                label: '自動檢查更新',
                icon: Icons.autorenew_rounded,
                checked: provider.book.canUpdate,
              ),
            if (!provider.book.isLocal)
              const GlassMenuItem(
                value: _MenuAction.download,
                label: '預下載章節',
                icon: Icons.download_rounded,
              ),
            const GlassMenuItem(
              value: _MenuAction.changeCover,
              label: '換封面',
              icon: Icons.image_outlined,
            ),
            GlassMenuItem(
              value: _MenuAction.export,
              label: _exportProgress == null
                  ? '匯出全書'
                  : '正在匯出 ${(_exportProgress! * 100).round()}%',
              icon: Icons.ios_share_rounded,
              enabled: _exportProgress == null,
            ),
            const GlassMenuItem(
              value: _MenuAction.edit,
              label: '編輯資訊',
              icon: Icons.edit_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleMenuSelection(
    BuildContext context,
    BookDetailProvider provider,
    _MenuAction action,
  ) async {
    switch (action) {
      case _MenuAction.checkUpdate:
        await _handleCheckUpdate(context, provider);
      case _MenuAction.autoUpdate:
        final result = await provider.setCanUpdate(!provider.book.canUpdate);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(result.message)));
      case _MenuAction.download:
        unawaited(_showDownloadSheet(context, provider));
      case _MenuAction.export:
        await _handleExport(context, provider);
      case _MenuAction.edit:
        _showEditBookInfoDialog(context, provider);
      case _MenuAction.changeCover:
        _showChangeCoverSheet(context, provider);
    }
  }

  void _scrollToToc() {
    final tocContext = _tocKey.currentContext;
    if (tocContext == null || !_scrollController.hasClients) return;
    final target = tocContext.findRenderObject();
    if (target == null) return;
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport == null) return;
    final position = _scrollController.position;
    // 目錄組標題停在玻璃頁首下方。
    final offset =
        (viewport.getOffsetToReveal(target, 0).offset - _headerExtent(context))
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    _scrollController.animateTo(
      offset,
      duration: AppMotion.spring,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _handleBookshelfToggle(
    BuildContext context,
    BookDetailProvider provider,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // 加入或移出還在進行時，不再跳出反向操作的確認框。
    if (provider.isUpdatingBookshelf) return;
    if (provider.isInBookshelf) {
      final confirmed = await showAppConfirm(
        context: context,
        title: '移出書架',
        message: '這本書會從書架移出，並刪除本機正文、下載任務、目錄與封面資料。',
        confirmLabel: '移出',
        destructive: true,
      );
      if (!confirmed || !context.mounted) return;
      final result = await provider.setInBookshelf(false);
      if (!context.mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      if (result.success && context.mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final result = await provider.setInBookshelf(true);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _handleCheckUpdate(
    BuildContext context,
    BookDetailProvider provider,
  ) async {
    final result = await provider.checkForUpdates();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _handleExport(
    BuildContext context,
    BookDetailProvider provider,
  ) async {
    if (provider.totalChapterCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('沒有可匯出的章節')));
      return;
    }
    await provider.refreshCacheStatus();
    if (!context.mounted) return;
    final status = provider.cacheStatus;
    var fetchMissingRemote = false;
    if (!provider.book.isLocal && status.missingChapterCount > 0) {
      final decision = await showAppAlert<String>(
        context: context,
        title: '匯出可能不完整',
        message:
            '目前只快取 ${status.storedChapterCount}/${status.totalChapterCount} 章，'
            '仍缺 ${status.missingChapterCount} 章正文。',
        actions: const [
          AppAlertAction(label: '補抓並匯出', value: 'export', isDefault: true),
          AppAlertAction(label: '只匯出已快取', value: 'cached'),
          AppAlertAction(label: '先下載缺失章節', value: 'download'),
          AppAlertAction(label: '取消', value: 'cancel'),
        ],
      );
      if (!context.mounted || decision == null || decision == 'cancel') return;
      if (decision == 'download') {
        final result = await provider.queueDownloadMissing();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }
      fetchMissingRemote = decision == 'export';
    }

    // 補抓缺少的正文可能要好幾分鐘：選單顯示進度，期間不能再匯出一次。
    if (_exportProgress != null) return;
    setState(() => _exportProgress = 0);
    try {
      await ExportBookService().exportToTxt(
        provider.book,
        fetchMissingRemote: fetchMissingRemote,
        onProgress: (progress) {
          if (mounted) setState(() => _exportProgress = progress);
        },
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已建立匯出檔案')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage('匯出', e))));
    } finally {
      if (mounted) setState(() => _exportProgress = null);
    }
  }

  Future<void> _showDownloadSheet(
    BuildContext context,
    BookDetailProvider provider,
  ) async {
    final choice = await showAppActionSheet<String>(
      context: context,
      title: '預下載章節',
      actions: const [
        AppSheetAction(
          label: '從目前章節起下載到結尾',
          value: 'from_current',
          icon: Icons.playlist_add_outlined,
        ),
        AppSheetAction(
          label: '從目前章節起下載後 10 章',
          value: 'next_10',
          icon: Icons.looks_one_outlined,
        ),
        AppSheetAction(
          label: '從目前章節起下載後 50 章',
          value: 'next_50',
          icon: Icons.filter_5_outlined,
        ),
        AppSheetAction(
          label: '下載全書',
          value: 'all',
          icon: Icons.library_books_outlined,
        ),
        AppSheetAction(
          label: '下載全部未下載章節',
          value: 'missing',
          icon: Icons.download_done_outlined,
        ),
        AppSheetAction(
          label: '指定章節範圍',
          value: 'range',
          icon: Icons.tune_outlined,
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'from_current':
        unawaited(_queueDownload(context, provider.queueDownloadFromCurrent()));
      case 'next_10':
        unawaited(_queueDownload(context, provider.queueDownloadNext(10)));
      case 'next_50':
        unawaited(_queueDownload(context, provider.queueDownloadNext(50)));
      case 'all':
        unawaited(_queueDownload(context, provider.queueDownloadAll()));
      case 'missing':
        unawaited(_queueDownload(context, provider.queueDownloadMissing()));
      case 'range':
        _showDownloadRangeDialog(context, provider);
    }
  }

  Future<void> _queueDownload(
    BuildContext context,
    Future<StorageDownloadQueueResult> task,
  ) async {
    final result = await task;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  /// 提示框內的分組輸入卡片。
  Widget _fieldCard(BuildContext context, List<Widget> rows) {
    final chrome = AppChrome.of(context);
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(const InsetSeparator(indent: AppGrouped.rowPadding));
      }
      children.add(rows[i]);
    }
    return ClipRRect(
      borderRadius: AppRadius.cardMd,
      child: ColoredBox(
        color: chrome.groupedBackground,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  void _showDownloadRangeDialog(
    BuildContext context,
    BookDetailProvider provider,
  ) {
    String? errorMessage;
    showStatefulAppAlert<void>(
      context: context,
      fieldTexts: [
        '${provider.book.chapterIndex + 1}',
        '${provider.totalChapterCount}',
      ],
      builder: (ctx, setDialogState, fields) => AppAlert<bool>(
        title: '指定下載範圍',
        // 錯誤寫在對話框裡；頁面的 SnackBar 會被對話框的遮罩蓋住。
        message: errorMessage,
        content: _fieldCard(ctx, [
          GroupedTextFieldRow(
            label: '起始章節',
            controller: fields[0],
            keyboardType: TextInputType.number,
          ),
          GroupedTextFieldRow(
            label: '結束章節',
            controller: fields[1],
            keyboardType: TextInputType.number,
          ),
        ]),
        actions: const [
          AppAlertAction(label: '取消', value: false),
          AppAlertAction(label: '加入佇列', value: true, isDefault: true),
        ],
        onAction: (confirmed) {
          if (!confirmed) {
            Navigator.pop(ctx);
            return;
          }
          final startValue = int.tryParse(fields[0].text.trim());
          final endValue = int.tryParse(fields[1].text.trim());
          if (startValue == null ||
              endValue == null ||
              startValue <= 0 ||
              endValue < startValue) {
            setDialogState(() => errorMessage = '請輸入有效章節範圍');
            return;
          }
          Navigator.pop(ctx);
          _queueDownload(
            context,
            provider.queueDownloadRange(startValue - 1, endValue - 1),
          );
        },
      ),
    );
  }

  void _locateCurrentChapter(
    BuildContext context,
    BookDetailProvider provider,
  ) {
    provider.resetTocViewForCurrentChapter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || !context.mounted) return;
      final index = provider.displayIndexForChapter(provider.book.chapterIndex);
      if (index < 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('目前閱讀章節不在目錄中')));
        return;
      }
      if (!_chapterListController.isAttached) return;
      final viewport = _scrollController.position.viewportDimension;
      // 章節停在玻璃頁首下方一點，不被頁首蓋住。
      final alignment = viewport <= 0
          ? 0.12
          : ((_headerExtent(context) + AppSpacing.xl) / viewport).clamp(
              0.0,
              0.5,
            );
      _chapterListController.animateToItem(
        index: index,
        scrollController: _scrollController,
        alignment: alignment,
        duration: (_) => const Duration(milliseconds: 320),
        curve: (_) => Curves.easeOutCubic,
      );
    });
  }

  void _showPhotoView(BuildContext context, String url) {
    final isLocal = url.startsWith('local://') || url.startsWith('file://');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: const GlassNavHeader(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: isLocal
                ? Image.file(
                    url.startsWith('local://')
                        ? File(url.replaceFirst('local://', ''))
                        : File(Uri.parse(url).toFilePath()),
                  )
                : CachedNetworkImage(imageUrl: url),
          ),
        ),
      ),
    );
  }

  /// 目錄要登入才讀得到：開書源的登入，登入資料變了就重新載入。
  Future<void> _login(BuildContext context, BookDetailProvider provider) async {
    final source = provider.currentSource;
    if (source == null) return;
    final changed = await openSourceLogin(context, source);
    if (changed && context.mounted) await provider.retryInitialization();
  }

  Future<void> _showSourceOptions(BuildContext context, Book b) async {
    final provider = context.read<BookDetailProvider>();
    final source = provider.currentSource;
    final chrome = AppChrome.of(context);
    final action = await showAppAlert<String>(
      context: context,
      title: b.originName,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '狀態：${provider.sourceStatusLabel}',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            provider.sourceStatusDescription,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySm,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            b.origin,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelXs.copyWith(color: chrome.sectionText),
          ),
        ],
      ),
      actions: [
        AppAlertAction(label: '詳情', value: 'detail', enabled: source != null),
        AppAlertAction(label: '除錯', value: 'debug', enabled: source != null),
        const AppAlertAction(label: '關閉', value: 'close', isDefault: true),
      ],
    );
    if (source == null || !context.mounted) return;
    if (action == 'detail') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SourceEditorPage(source: source)),
      );
    } else if (action == 'debug') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SourceDebugPage(source: source, debugKey: b.name),
        ),
      );
    } else {
      return;
    }
    // 編輯或除錯改的書源只寫進資料庫；返回動畫播完再重讀，下次進編輯頁
    // 才不會帶著舊規則（ADR 0018）。
    if (!mounted) return;
    await TransitionSettled.uncovered(this.context);
    if (mounted) await provider.reloadSource();
  }

  Future<void> _navigateToReader(
    BuildContext context,
    Book b,
    ReaderV2OpenTarget openTarget,
    List<BookChapter> initialChapters,
  ) async {
    final provider = context.read<BookDetailProvider>();
    await Navigator.push(
      context,
      BookOpenRoute(
        book: b,
        openTarget: openTarget,
        initialChapters: initialChapters,
      ),
    );
    // 閱讀器改的進度、加入書架與換源都只寫進資料庫；回來時照資料庫重新
    // 顯示。返回動畫播完才重建，不和返回疊在一起（ADR 0018）。閱讀器裡
    // 換源是換掉閱讀器那一頁，這時這裡就收到結果，但上面還蓋著新的閱讀
    // 器，同樣等它關掉。
    if (!mounted) return;
    await TransitionSettled.uncovered(this.context);
    if (mounted) await provider.reloadAfterReading();
  }

  void _showChangeSourceDialog(BuildContext context, BookDetailProvider p) {
    if (p.book.isLocal) return;
    AppBottomSheet.showCustom(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ChangeSourceSheet(book: p.book, detailProvider: p),
    );
  }

  Future<void> _showSearchTocDialog(
    BuildContext context,
    BookDetailProvider p,
  ) async {
    await showStatefulAppAlert<void>(
      context: context,
      fieldTexts: [p.tocSearchQuery],
      builder: (ctx, _, fields) => AppAlert<void>(
        title: '搜尋目錄',
        content: _fieldCard(ctx, [
          GroupedTextFieldRow(
            controller: fields.single,
            autofocus: true,
            onChanged: p.setSearchQuery,
          ),
        ]),
        actions: const [
          AppAlertAction(label: '關閉', value: null, isDefault: true),
        ],
      ),
    );
  }

  void _showEditBookInfoDialog(BuildContext context, BookDetailProvider p) {
    var saving = false;
    String? errorMessage;
    showStatefulAppAlert<void>(
      context: context,
      barrierDismissible: false,
      fieldTexts: [
        p.book.name,
        p.book.author,
        // 預填畫面上看到的內容（使用者改過的優先）。
        p.book.getDisplayIntro() ?? '',
        p.book.customCoverUrl ?? p.book.coverUrl ?? '',
        p.book.kind ?? '',
        p.book.customTag ?? '',
        p.book.originName,
        p.book.tocUrl,
      ],
      builder: (ctx, setDialogState, fields) {
        final [n, a, i, c, k, tag, sourceName, toc] = fields;
        GroupedTextFieldRow field(
          String label,
          TextEditingController controller, {
          int maxLines = 1,
        }) => GroupedTextFieldRow(
          label: label,
          controller: controller,
          maxLines: maxLines,
          minLines: 1,
        );
        return IgnorePointer(
          ignoring: saving,
          child: AppAlert<bool>(
            title: '編輯',
            message: errorMessage,
            content: _fieldCard(ctx, [
              field('書名', n),
              field('作者', a),
              field('封面', c),
              field('分類', k),
              field('自訂標籤', tag),
              field('來源名稱', sourceName),
              field('目錄 URL', toc),
              field('簡介', i, maxLines: 3),
            ]),
            actions: [
              AppAlertAction(label: '取消', value: false, enabled: !saving),
              AppAlertAction(
                label: saving ? '儲存中…' : '儲存',
                value: true,
                isDefault: true,
                enabled: !saving,
              ),
            ],
            onAction: (save) async {
              if (!save) {
                Navigator.pop(ctx);
                return;
              }
              setDialogState(() {
                saving = true;
                errorMessage = null;
              });
              final result = await p.updateBookInfo(
                n.text,
                a.text,
                i.text,
                c.text,
                kind: k.text,
                customTag: tag.text,
                originName: sourceName.text,
                tocUrl: toc.text,
              );
              if (!ctx.mounted) return;
              if (result.success) {
                Navigator.pop(ctx);
                return;
              }
              setDialogState(() {
                saving = false;
                errorMessage = result.message;
              });
            },
          ),
        );
      },
    );
  }

  void _showChangeCoverSheet(BuildContext context, BookDetailProvider p) =>
      AppBottomSheet.showCustom(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => ChangeNotifierProvider.value(
          value: p,
          child: ChangeCoverSheet(bookName: p.book.name, author: p.book.author),
        ),
      );
}

/// 目錄的一列：目前閱讀章節以主色標示，右側「目前」；付費還沒買的章節
/// 右側鎖頭。
class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.title,
    required this.isCurrent,
    required this.isLocked,
    required this.onTap,
  });

  final String title;
  final bool isCurrent;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GroupedRow(
      title: title,
      titleWidget: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodyBase.copyWith(
          height: 1.3,
          color: isCurrent ? scheme.primary : scheme.onSurface,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      showChevron: false,
      trailing: isCurrent
          ? Text(
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
