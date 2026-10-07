import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';
import 'package:super_sliver_list/super_sliver_list.dart' as super_list;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/features/book_detail/book_detail_provider.dart';
import 'package:night_reader/features/book_detail/change_cover_sheet.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/export_book_service.dart';
import 'package:night_reader/features/search/widgets/grouped_slice.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/features/source_manager/source_debug_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';

import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'widgets/book_info_header.dart';
import 'widgets/book_info_intro.dart';
import 'widgets/book_info_toc_bar.dart';
import 'widgets/change_source_sheet.dart';
import 'package:night_reader/core/services/chinese_display.dart';

class BookDetailPage extends StatefulWidget {
  final Book? book;
  final AggregatedSearchBook? searchBook;

  const BookDetailPage({super.key, this.book, this.searchBook})
    : assert(book != null || searchBook != null);

  @override
  State<BookDetailPage> createState() => _BookDetailPageState();
}

enum _MenuAction { checkUpdate, download, changeCover, export, edit }

class _BookDetailPageState extends State<BookDetailPage> {
  final ScrollController _scrollController = ScrollController();
  final super_list.ListController _chapterListController =
      super_list.ListController();
  final GlobalKey _tocKey = GlobalKey();

  /// 大頁首捲進玻璃頁首底下後，頁首標題淡入顯示書名。
  final ValueNotifier<bool> _titleCollapsed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncCollapsedTitle);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_syncCollapsedTitle);
    _titleCollapsed.dispose();
    _chapterListController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _syncCollapsedTitle() {
    if (!_scrollController.hasClients) return;
    _titleCollapsed.value =
        _scrollController.offset > BookInfoHeader.collapseOffset;
  }

  /// 玻璃頁首（狀態列＋工具列＋漸隱）佔用的高度。
  double _headerExtent(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      AppGlass.headerToolbarHeight +
      AppGlass.headerFadeHeight;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create:
          (_) => BookDetailProvider(
            widget.searchBook ??
                AggregatedSearchBook(book: widget.book!, sources: []),
          ),
      child: Consumer<BookDetailProvider>(
        builder: (context, provider, child) {
          final chrome = AppChrome.of(context);
          return Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: chrome.groupedBackground,
            appBar: _buildHeader(context, provider),
            // 內距要從 Scaffold 內取得：延伸到頁首下方時 top 才包含頁首高度。
            body: Builder(
              builder:
                  (bodyContext) =>
                      provider.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : provider.loadErrorMessage != null
                          ? _buildLoadError(bodyContext, provider)
                          : _buildContent(bodyContext, provider),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, BookDetailProvider provider) {
    final currentBook = provider.book;
    final padding = MediaQuery.paddingOf(context);
    final chapters = provider.filteredChapters;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: padding.top)),
        SliverToBoxAdapter(
          child: BookInfoHeader(
            book: currentBook,
            provider: provider,
            showPhotoView: _showPhotoView,
            onRead:
                () => _navigateToReader(
                  context,
                  currentBook,
                  ReaderV2OpenTarget.resume(currentBook),
                  provider.allChapters,
                ),
            onToggleBookshelf: () => _handleBookshelfToggle(context, provider),
            onChangeSource:
                currentBook.isLocal
                    ? null
                    : () => _showChangeSourceDialog(context, provider),
            onShowToc: _scrollToToc,
          ),
        ),
        if ((provider.sourceIssueMessage ?? '').isNotEmpty)
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
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: BookInfoDetails(
            book: currentBook,
            provider: provider,
            onShowSourceOptions: () => _showSourceOptions(context, currentBook),
          ),
        ),
        SliverToBoxAdapter(child: BookInfoIntro(book: currentBook)),
        SliverToBoxAdapter(child: SizedBox(key: _tocKey)),
        BookInfoTocBar(
          provider: provider,
          onSearch: () => _showSearchTocDialog(context, provider),
          onLocateCurrent: () => _locateCurrentChapter(context, provider),
        ),
        if (provider.hasActiveTocSearch && chapters.isEmpty)
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
                  ),
                ],
              ),
            ),
          )
        else
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
                  onTap:
                      () => _navigateToReader(
                        context,
                        currentBook,
                        ReaderV2OpenTarget.chapterStart(chapter.index),
                        provider.allChapters,
                      ),
                ),
              );
            }, childCount: chapters.length),
          ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: padding.bottom + AppSpacing.xxl),
        ),
      ],
    );
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
    final actionsEnabled =
        !provider.isLoading && provider.loadErrorMessage == null;
    final ready = actionsEnabled;
    return GlassNavHeader(
      backgroundColor: AppChrome.of(context).groupedBackground,
      titleWidget: ValueListenableBuilder<bool>(
        valueListenable: _titleCollapsed,
        builder:
            (context, collapsed, child) => AnimatedOpacity(
              opacity: collapsed || !ready ? 1 : 0,
              duration: AppMotion.fade,
              curve: AppMotion.fadeCurve,
              child: child,
            ),
        child: Semantics(
          header: true,
          child: Text(
            ready ? context.zh(provider.book.name) : '書籍詳情',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleSm.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
      actions: [
        if (actionsEnabled)
          GlassMenuButton<_MenuAction>(
            onSelected: (v) => _handleMenuSelection(context, provider, v),
            entriesBuilder:
                (ctx) => [
                  if (!provider.book.isLocal)
                    const GlassMenuItem(
                      value: _MenuAction.checkUpdate,
                      label: '檢查更新',
                      icon: Icons.update_rounded,
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
                  const GlassMenuItem(
                    value: _MenuAction.export,
                    label: '匯出全書',
                    icon: Icons.ios_share_rounded,
                  ),
                  const GlassMenuItem(
                    value: _MenuAction.edit,
                    label: '編輯資訊',
                    icon: Icons.edit_outlined,
                  ),
                ],
          )
        else
          const GlassIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: '更多',
            onPressed: null,
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
      case _MenuAction.download:
        _showDownloadSheet(context, provider);
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
    final offset = (viewport.getOffsetToReveal(target, 0).offset -
            _headerExtent(context))
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _handleExport(
    BuildContext context,
    BookDetailProvider provider,
  ) async {
    if (provider.totalChapterCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('沒有可匯出的章節')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }
      fetchMissingRemote = decision == 'export';
    }

    try {
      await ExportBookService().exportToTxt(
        provider.book,
        fetchMissingRemote: fetchMissingRemote,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已建立匯出檔案')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯出失敗: $e')));
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
        _queueDownload(context, provider.queueDownloadFromCurrent());
      case 'next_10':
        _queueDownload(context, provider.queueDownloadNext(10));
      case 'next_50':
        _queueDownload(context, provider.queueDownloadNext(50));
      case 'all':
        _queueDownload(context, provider.queueDownloadAll());
      case 'missing':
        _queueDownload(context, provider.queueDownloadMissing());
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  /// 提示框內的分組輸入卡片。
  Widget _fieldCard(BuildContext context, List<Widget> rows) {
    final chrome = AppChrome.of(context);
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: AppGrouped.rowPadding,
            ),
            child: Container(height: AppGlass.hairline, color: chrome.separator),
          ),
        );
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
    final start = TextEditingController(
      text: '${provider.book.chapterIndex + 1}',
    );
    final end = TextEditingController(text: '${provider.totalChapterCount}');
    showDialog<void>(
      context: context,
      barrierColor: AppChrome.of(context).barrier,
      builder:
          (ctx) => AppAlert<bool>(
            title: '指定下載範圍',
            content: _fieldCard(ctx, [
              GroupedTextFieldRow(
                label: '起始章節',
                controller: start,
                keyboardType: TextInputType.number,
              ),
              GroupedTextFieldRow(
                label: '結束章節',
                controller: end,
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
              final startValue = int.tryParse(start.text.trim());
              final endValue = int.tryParse(end.text.trim());
              if (startValue == null ||
                  endValue == null ||
                  startValue <= 0 ||
                  endValue < startValue) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('請輸入有效章節範圍')));
                return;
              }
              Navigator.pop(ctx);
              _queueDownload(
                context,
                provider.queueDownloadRange(startValue - 1, endValue - 1),
              );
            },
          ),
    ).whenComplete(() {
      start.dispose();
      end.dispose();
    });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('目前閱讀章節不在目錄中')));
        return;
      }
      if (!_chapterListController.isAttached) return;
      final viewport = _scrollController.position.viewportDimension;
      // 章節停在玻璃頁首下方一點，不被頁首蓋住。
      final alignment =
          viewport <= 0
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

  void _showPhotoView(BuildContext context, String url, String heroTag) {
    final isLocal = url.startsWith('local://') || url.startsWith('file://');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (ctx) => Scaffold(
              backgroundColor: Colors.black,
              extendBodyBehindAppBar: true,
              appBar: const GlassNavHeader(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              body: Center(
                child: Hero(
                  tag: heroTag,
                  child:
                      isLocal
                          ? Image.file(
                            url.startsWith('local://')
                                ? File(url.replaceFirst('local://', ''))
                                : File(Uri.parse(url).toFilePath()),
                          )
                          : CachedNetworkImage(imageUrl: url),
                ),
              ),
            ),
      ),
    );
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
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SourceEditorPage(source: source)),
      );
    } else if (action == 'debug') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SourceDebugPage(source: source, debugKey: b.name),
        ),
      );
    }
  }

  void _navigateToReader(
    BuildContext context,
    Book b,
    ReaderV2OpenTarget openTarget,
    List<BookChapter> initialChapters,
  ) {
    Navigator.push(
      context,
      BookOpenRoute(
        book: b,
        openTarget: openTarget,
        initialChapters: initialChapters,
      ),
    );
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
    final query = TextEditingController(text: p.tocSearchQuery);
    await showAppAlert<void>(
      context: context,
      title: '搜尋目錄',
      content: _fieldCard(context, [
        GroupedTextFieldRow(
          controller: query,
          hintText: '章節名稱',
          autofocus: true,
          onChanged: p.setSearchQuery,
        ),
      ]),
      actions: const [
        AppAlertAction(label: '關閉', value: null, isDefault: true),
      ],
    );
    query.dispose();
  }

  void _showEditBookInfoDialog(BuildContext context, BookDetailProvider p) {
    final n = TextEditingController(text: p.book.name),
        a = TextEditingController(text: p.book.author),
        i = TextEditingController(text: p.book.intro),
        c = TextEditingController(text: p.book.coverUrl),
        k = TextEditingController(text: p.book.kind ?? ''),
        tag = TextEditingController(text: p.book.customTag ?? ''),
        sourceName = TextEditingController(text: p.book.originName),
        toc = TextEditingController(text: p.book.tocUrl);
    var saving = false;
    String? errorMessage;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppChrome.of(context).barrier,
      builder:
          (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
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
                  content: _fieldCard(context, [
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
                    AppAlertAction(
                      label: '取消',
                      value: false,
                      enabled: !saving,
                    ),
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
          ),
    ).whenComplete(() {
      n.dispose();
      a.dispose();
      i.dispose();
      c.dispose();
      k.dispose();
      tag.dispose();
      sourceName.dispose();
      toc.dispose();
    });
  }

  void _showChangeCoverSheet(BuildContext context, BookDetailProvider p) =>
      AppBottomSheet.showCustom(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppChrome.of(context).groupedBackground,
        builder:
            (ctx) => ChangeNotifierProvider.value(
              value: p,
              child: ChangeCoverSheet(
                bookName: p.book.name,
                author: p.book.author,
              ),
            ),
      );
}

/// 目錄的一列：目前閱讀章節以主色標示，右側「目前」。
class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.title,
    required this.isCurrent,
    required this.onTap,
  });

  final String title;
  final bool isCurrent;
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
      trailing:
          isCurrent
              ? Text(
                '目前',
                style: AppTextStyles.labelSm.copyWith(color: scheme.primary),
              )
              : null,
      onTap: onTap,
    );
  }
}
