import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/core/services/app_file_selection_service.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/services/chinese_display.dart';

enum _BookshelfBatchAction { download, ensureComplete, checkUpdate }

/// 頁首兩個選單的非排序項目；排序項目直接用 [BookshelfSortMode]。
/// 左邊「整理」管書架怎麼看、怎麼排，右邊「加入」把書帶進書架。
enum _ShelfMenuAction {
  gridView,
  listView,
  select,
  export,
  search,
  addLocal,
  importUrl,
  importFile,
}

/// 長按書籍的情境選單項目。
enum _BookMenuAction { detail, select, checkUpdate, download, remove }

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  bool _isMultiSelect = false;
  final Set<String> _selectedUrls = {};
  _BookshelfBatchAction? _batchAction;

  /// 編輯中由底部工具列取代浮動分頁列，主頁同時鎖住左右換頁。
  void _enterEditMode([Book? first]) {
    setState(() {
      _isMultiSelect = true;
      if (first != null) _selectedUrls.add(first.bookUrl);
    });
    FloatingTabBarScope.maybeOf(context)?.value = true;
  }

  void _exitEditMode() {
    setState(() {
      _isMultiSelect = false;
      _selectedUrls.clear();
    });
    FloatingTabBarScope.maybeOf(context)?.value = false;
  }

  void _toggleSelected(Book book) {
    setState(() {
      if (!_selectedUrls.remove(book.bookUrl)) {
        _selectedUrls.add(book.bookUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BookshelfProvider>();
    return PopScope<void>(
      canPop: !_isMultiSelect,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_isMultiSelect) return;
        _exitEditMode();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: _buildHeader(provider),
        body: Builder(
          builder: (context) {
            final slot = FloatingTabBar.slotOf(context);
            return Stack(
              children: [
                Positioned.fill(child: _buildContent(context, provider)),
                Positioned(
                  left: slot.left,
                  right: slot.right,
                  bottom: slot.bottom,
                  child: AnimatedSwitcher(
                    duration: AppMotion.menu,
                    switchInCurve: AppMotion.menuCurve,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.4),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _isMultiSelect
                        ? _buildEditToolbar(provider)
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  GlassNavHeader _buildHeader(BookshelfProvider provider) {
    if (_isMultiSelect) {
      final allSelected =
          provider.books.isNotEmpty &&
          _selectedUrls.length == provider.books.length;
      return GlassNavHeader(
        title: '已選 ${_selectedUrls.length} 本',
        leading: GlassTextButton(
          label: '完成',
          emphasized: true,
          onPressed: _exitEditMode,
        ),
        actions: [
          GlassTextButton(
            label: allSelected ? '全不選' : '全選',
            onPressed: _batchAction != null
                ? null
                : () => setState(() {
                    if (allSelected) {
                      _selectedUrls.clear();
                    } else {
                      _selectedUrls.addAll(
                        provider.books.map((b) => b.bookUrl),
                      );
                    }
                  }),
          ),
        ],
      );
    }
    return GlassNavHeader(
      title: '書架',
      leading: GlassMenuButton<Object>(
        icon: Icons.swap_vert_rounded,
        tooltip: '整理書架',
        entriesBuilder: (_) => _arrangeMenuEntries(provider),
        onSelected: (value) => _onShelfMenuSelected(provider, value),
      ),
      actions: [
        GlassMenuButton<Object>(
          icon: Icons.add_rounded,
          tooltip: '加入書籍',
          entriesBuilder: (_) => _addMenuEntries,
          onSelected: (value) => _onShelfMenuSelected(provider, value),
        ),
      ],
    );
  }

  List<GlassMenuEntry<Object>> _arrangeMenuEntries(BookshelfProvider provider) {
    return [
      GlassMenuItem(
        value: _ShelfMenuAction.gridView,
        label: '網格',
        icon: Icons.grid_view_outlined,
        checked: provider.isGridView,
      ),
      GlassMenuItem(
        value: _ShelfMenuAction.listView,
        label: '列表',
        icon: Icons.view_list_outlined,
        checked: !provider.isGridView,
      ),
      const GlassMenuDivider(),
      for (final mode in BookshelfSortMode.values)
        GlassMenuItem(
          value: mode,
          label: mode.label,
          checked: provider.sortMode == mode,
        ),
      const GlassMenuDivider(),
      GlassMenuItem(
        value: _ShelfMenuAction.select,
        label: '選取',
        icon: Icons.check_circle_outline,
        enabled: provider.books.isNotEmpty,
      ),
      const GlassMenuItem(
        value: _ShelfMenuAction.export,
        label: '匯出書架',
        icon: Icons.file_upload_outlined,
      ),
    ];
  }

  static const List<GlassMenuEntry<Object>> _addMenuEntries = [
    GlassMenuItem(
      value: _ShelfMenuAction.search,
      label: '搜尋書籍',
      icon: Icons.search_rounded,
    ),
    GlassMenuItem(
      value: _ShelfMenuAction.addLocal,
      label: '加入本地書籍',
      icon: Icons.file_open_outlined,
    ),
    GlassMenuDivider(),
    GlassMenuItem(
      value: _ShelfMenuAction.importUrl,
      label: '從網址匯入書架',
      icon: Icons.link_rounded,
    ),
    GlassMenuItem(
      value: _ShelfMenuAction.importFile,
      label: '從檔案匯入書架',
      icon: Icons.file_download_outlined,
    ),
  ];

  Future<void> _onShelfMenuSelected(
    BookshelfProvider provider,
    Object value,
  ) async {
    switch (value) {
      case BookshelfSortMode mode:
        await provider.setSortMode(mode);
      case _ShelfMenuAction.gridView:
        provider.setGridView(true);
      case _ShelfMenuAction.listView:
        provider.setGridView(false);
      case _ShelfMenuAction.select:
        _enterEditMode();
      case _ShelfMenuAction.search:
        _openSearch();
      case _ShelfMenuAction.addLocal:
        final path = await AppFileSelectionService.instance.pickLocalBookPath();
        if (path != null && mounted) {
          await _importLocalBook(context, provider, path);
        }
      case _ShelfMenuAction.importFile:
        await _handleBookshelfImport(context);
      case _ShelfMenuAction.importUrl:
        await _showImportBookshelfUrlDialog(context, provider);
      case _ShelfMenuAction.export:
        await _handleBookshelfExport(context, provider);
    }
  }

  Widget _buildContent(BuildContext context, BookshelfProvider provider) {
    final insets = MediaQuery.paddingOf(context);
    if (provider.isLoading && provider.books.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.books.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
        child: AppStateView(
          icon: Icons.auto_stories_outlined,
          title: '書架還是空的',
          description: '搜尋並加入一本書，之後就能從這裡繼續閱讀。',
          primaryAction: AppStateAction(
            label: '搜尋書籍',
            icon: Icons.search,
            onPressed: _openSearch,
          ),
        ),
      );
    }
    // 編輯工具列佔用分頁列的位置，清單底部讓出的高度不變。
    final bottom = insets.bottom + AppSpacing.md;
    // 下拉只在背景檢查更新：不轉圈、不提示，檢查期間不會重複觸發。
    return RefreshIndicator.noSpinner(
      onRefresh: provider.refreshBookshelf,
      child: provider.isGridView
          ? _buildGridView(provider, insets.top, bottom)
          : _buildListView(provider, insets.top, bottom),
    );
  }

  Widget _buildEditToolbar(BookshelfProvider provider) {
    final enabled = _selectedUrls.isNotEmpty && _batchAction == null;
    return BookshelfEditToolbar(
      key: const ValueKey('bookshelf-edit-toolbar'),
      progressLabel: _batchAction == null
          ? null
          : _batchProgressTitle(provider),
      actions: [
        BookshelfToolbarAction(
          label: '下載',
          icon: Icons.download_outlined,
          onPressed: enabled ? () => _batchDownload(context, provider) : null,
        ),
        BookshelfToolbarAction(
          label: '補下載',
          icon: Icons.cloud_download_outlined,
          onPressed: enabled
              ? () => _batchEnsureComplete(context, provider)
              : null,
        ),
        BookshelfToolbarAction(
          label: '檢查更新',
          icon: Icons.update,
          onPressed: enabled
              ? () => _batchCheckUpdate(context, provider)
              : null,
        ),
        BookshelfToolbarAction(
          label: '刪除',
          icon: Icons.delete_outline,
          destructive: true,
          onPressed: enabled
              ? () => _showDeleteConfirm(context, provider)
              : null,
        ),
      ],
    );
  }

  Future<void> _importLocalBook(
    BuildContext context,
    BookshelfProvider provider,
    String path,
  ) async {
    try {
      final ok = await provider.importLocalBookPath(path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ok ? '匯入成功' : '匯入失敗')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('匯入失敗: $e')));
    }
  }

  Future<void> _showImportBookshelfUrlDialog(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    // 確認時把網址作為結果帶回；輸入框控制器由提示框擁有。
    final url = await showStatefulAppAlert<String>(
      context: context,
      fieldTexts: const [''],
      builder: (dialogContext, _, fields) {
        void submit() => Navigator.of(dialogContext).pop(fields.single.text);
        return AppAlert<bool>(
          title: '從網址匯入書架',
          content: TextField(
            controller: fields.single,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: '輸入書架 JSON 網址'),
            onSubmitted: (_) => submit(),
          ),
          actions: const [
            AppAlertAction(label: '取消', value: false),
            AppAlertAction(label: '匯入', value: true, isDefault: true),
          ],
          onAction: (confirmed) =>
              confirmed ? submit() : Navigator.of(dialogContext).pop(),
        );
      },
    );
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty || !context.mounted) return;
    try {
      await provider.importBookshelfFromUrl(trimmed);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('書架網址匯入完成')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('書架網址匯入失敗: $e')));
    }
  }

  Future<void> _handleBookshelfImport(BuildContext context) async {
    final path = await AppFileSelectionService.instance
        .pickBookshelfImportPath();
    if (path == null || !context.mounted) return;
    try {
      final imported = await BookshelfExchangeService().importFromFile(
        File(path),
      );
      if (!context.mounted) return;
      final importedTotal =
          imported.books +
          imported.chapters +
          imported.sources +
          imported.contents;
      if (importedTotal == 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('未找到可匯入的書架資料')));
        return;
      }
      context.read<BookshelfProvider>().loadBooks();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已匯入 ${imported.books} 本書、${imported.chapters} 個章節、${imported.sources} 個書源'
            '${imported.contents > 0 ? '，${imported.contents} 份正文快取' : ''}',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('匯入失敗: $e')));
    }
  }

  Future<void> _handleBookshelfExport(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    try {
      await BookshelfExchangeService().shareBookshelf(books: provider.books);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('書架已匯出')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('匯出失敗: $e')));
    }
  }

  Future<void> _batchDownload(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    try {
      final result = await _runBatchAction(
        _BookshelfBatchAction.download,
        provider.batchDownload,
      );
      if (result == null) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已加入 ${result.queuedBooks} 本、${result.queuedChapters} 章；略過 ${result.skippedBooks} 本',
          ),
        ),
      );
      _exitEditMode();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('批次下載失敗: $e')));
    }
  }

  Future<void> _batchEnsureComplete(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    try {
      final result = await _runBatchAction(
        _BookshelfBatchAction.ensureComplete,
        provider.batchEnsureComplete,
      );
      if (result == null) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.queuedBooks > 0
                ? '已加入 ${result.queuedBooks} 本、${result.queuedChapters} 章補下載；略過 ${result.skippedBooks} 本'
                : '所有選取書籍已下載完整',
          ),
        ),
      );
      _exitEditMode();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('整本書補下載失敗: $e')));
    }
  }

  Future<void> _batchCheckUpdate(
    BuildContext context,
    BookshelfProvider provider,
  ) async {
    try {
      final results = await _runBatchAction(
        _BookshelfBatchAction.checkUpdate,
        provider.batchCheckUpdate,
      );
      if (results == null) return;
      final updated = results.where((result) => result.hasUpdate).length;
      final chapters = results.fold<int>(
        0,
        (sum, result) => sum + result.newChapterCount,
      );
      final failed = results.where((result) => result.failed).length;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('檢查完成：$updated 本有更新、$chapters 個新章節、$failed 本失敗'),
        ),
      );
      _exitEditMode();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('批次檢查更新失敗: $e')));
    }
  }

  Future<T?> _runBatchAction<T>(
    _BookshelfBatchAction action,
    Future<T> Function(Set<String> urls) operation,
  ) async {
    if (_batchAction != null || _selectedUrls.isEmpty) return null;
    final selectedUrls = Set<String>.from(_selectedUrls);
    setState(() => _batchAction = action);
    try {
      return await operation(selectedUrls);
    } finally {
      if (mounted) {
        setState(() => _batchAction = null);
      }
    }
  }

  String _batchProgressTitle(BookshelfProvider provider) {
    return switch (_batchAction) {
      _BookshelfBatchAction.download => '正在加入下載佇列…',
      _BookshelfBatchAction.ensureComplete => '正在檢查缺失章節…',
      _BookshelfBatchAction.checkUpdate =>
        provider.updatingCount > 0
            ? '正在檢查更新（剩 ${provider.updatingCount} 本）'
            : '正在整理更新結果…',
      null => '已選擇 ${_selectedUrls.length} 本',
    };
  }

  Widget _buildListView(
    BookshelfProvider provider,
    double topInset,
    double bottomInset,
  ) {
    final padding = EdgeInsets.fromLTRB(
      AppGrouped.margin,
      topInset + AppSpacing.xs,
      AppGrouped.margin,
      bottomInset,
    );
    final books = provider.books;
    // 自訂排序時長按拖曳換位置，不開情境選單；其餘操作走左滑動作。
    if (!_isMultiSelect && provider.sortMode == BookshelfSortMode.custom) {
      return SwipeActionsGroup(
        child: ReorderableListView.builder(
          padding: padding,
          itemCount: books.length,
          onReorderItem: provider.reorderBooks,
          // 預設的拖曳外觀會在卡片外距外畫出方形陰影，改成只微微放大。
          proxyDecorator: (child, _, animation) => ScaleTransition(
            scale: Tween<double>(begin: 1, end: 1.03).animate(
              CurvedAnimation(parent: animation, curve: AppMotion.menuCurve),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
          itemBuilder: (context, index) => KeyedSubtree(
            key: ValueKey(books[index].bookUrl),
            child: _buildListCard(provider, books[index], reorderable: true),
          ),
        ),
      );
    }
    return SwipeActionsGroup(
      child: ListView.builder(
        padding: padding,
        itemCount: books.length,
        itemBuilder: (context, index) => _buildListCard(provider, books[index]),
      ),
    );
  }

  Widget _buildListCard(
    BookshelfProvider provider,
    Book book, {
    bool reorderable = false,
  }) {
    final selecting = _isMultiSelect;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      // 滑出的動作按鈕裁在卡片圓角內。
      child: ClipRRect(
        borderRadius: AppGrouped.cardRadius,
        child: SwipeActions(
          enabled: !selecting,
          trailing: [
            if (!book.isLocal)
              SwipeAction(
                label: '檢查更新',
                icon: Icons.update,
                color: AppTint.azurite.color,
                onPressed: () => _checkUpdateOne(provider, book),
              ),
            SwipeAction(
              label: '移出書架',
              icon: Icons.delete_outline,
              color: AppTint.rust.color,
              destructive: true,
              onPressed: () => _confirmRemoveOne(provider, book),
            ),
          ],
          child: BookshelfListCard(
            book: book,
            selecting: selecting,
            selected: _selectedUrls.contains(book.bookUrl),
            onTap: () => selecting ? _toggleSelected(book) : _openBook(book),
            onLongPress: selecting || reorderable
                ? null
                : (rect) => _showBookMenu(provider, book, rect, grid: false),
          ),
        ),
      ),
    );
  }

  Widget _buildGridView(
    BookshelfProvider provider,
    double topInset,
    double bottomInset,
  ) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        AppGrouped.margin,
        topInset + AppSpacing.xs,
        AppGrouped.margin,
        bottomInset,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        // Leave a little room for the two-line title and the progress bar.
        // The previous ratio overflowed by 1.5 px on the phone's narrow
        // logical width after Flutter rounded the grid constraints.
        childAspectRatio: 0.52,
        crossAxisSpacing: AppSpacing.lg,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: provider.books.length,
      itemBuilder: (context, index) {
        final book = provider.books[index];
        return BookshelfGridTile(
          book: book,
          selecting: _isMultiSelect,
          selected: _selectedUrls.contains(book.bookUrl),
          onTap: () => _isMultiSelect ? _toggleSelected(book) : _openBook(book),
          onLongPress: _isMultiSelect
              ? null
              : (rect) => _showBookMenu(provider, book, rect, grid: true),
        );
      },
    );
  }

  /// Telegram 長按預覽：書籍浮起，旁邊列出這本書可用的動作。
  Future<void> _showBookMenu(
    BookshelfProvider provider,
    Book book,
    Rect sourceRect, {
    required bool grid,
  }) async {
    final busy = _batchAction != null;
    final preview = grid
        ? BookCoverWidget(
            bookName: context.zh(book.name),
            author: book.author,
            coverUrl: book.getDisplayCover(),
            width: sourceRect.width,
            height: sourceRect.height,
            borderRadius: AppRadius.cardXs,
          )
        : BookshelfListCard(book: book, hero: false);
    final action = await showContextPreviewMenu<_BookMenuAction>(
      context: context,
      sourceRect: sourceRect,
      preview: preview,
      previewRadius: grid ? AppRadius.cardXs : AppGrouped.cardRadius,
      entries: [
        const GlassMenuItem(
          value: _BookMenuAction.detail,
          label: '書籍詳情',
          icon: Icons.info_outline,
        ),
        const GlassMenuItem(
          value: _BookMenuAction.select,
          label: '選取',
          icon: Icons.check_circle_outline,
        ),
        if (!book.isLocal) ...[
          const GlassMenuDivider(),
          GlassMenuItem(
            value: _BookMenuAction.checkUpdate,
            label: '檢查更新',
            icon: Icons.update,
            enabled: !busy,
          ),
          GlassMenuItem(
            value: _BookMenuAction.download,
            label: '下載',
            icon: Icons.download_outlined,
            enabled: !busy,
          ),
        ],
        const GlassMenuDivider(),
        const GlassMenuItem(
          value: _BookMenuAction.remove,
          label: '移出書架',
          icon: Icons.delete_outline,
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _BookMenuAction.detail:
        _openDetail(book);
      case _BookMenuAction.select:
        _enterEditMode(book);
      case _BookMenuAction.checkUpdate:
        await _checkUpdateOne(provider, book);
      case _BookMenuAction.download:
        await _downloadOne(provider, book);
      case _BookMenuAction.remove:
        await _confirmRemoveOne(provider, book);
    }
  }

  Future<void> _checkUpdateOne(BookshelfProvider provider, Book book) async {
    if (_batchAction != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = context.zh(book.name);
    try {
      final results = await provider.batchCheckUpdate({book.bookUrl});
      final result = results.isEmpty ? null : results.first;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == null || result.failed
                ? '《$name》檢查更新失敗'
                : result.hasUpdate
                ? '《$name》有 ${result.newChapterCount} 個新章節'
                : '《$name》沒有新章節',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('檢查更新失敗: $e')));
    }
  }

  Future<void> _downloadOne(BookshelfProvider provider, Book book) async {
    if (_batchAction != null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await provider.batchDownload({book.bookUrl});
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.queuedBooks > 0
                ? '已加入 ${result.queuedChapters} 章下載'
                : '沒有加入下載：章節已下載或書源無法使用',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('下載失敗: $e')));
    }
  }

  Future<void> _confirmRemoveOne(BookshelfProvider provider, Book book) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '移出書架',
      message: '這本書會從書架移出，並刪除本機正文、下載任務、目錄與封面資料。',
      confirmLabel: '移出',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await provider.deleteBook(book.bookUrl);
      if (!mounted) return;
      setState(() => _selectedUrls.remove(book.bookUrl));
      messenger.showSnackBar(const SnackBar(content: Text('已移出書架')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('移出書架失敗: $e')));
    }
  }

  void _openDetail(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookDetailPage(book: book)),
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
  }

  void _openBook(Book book) {
    if (book.type == 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('有聲書播放功能已移除，請選擇文本書籍。')));
      return;
    }
    Navigator.push(
      context,
      BookOpenRoute(book: book, openTarget: ReaderV2OpenTarget.resume(book)),
    );
  }

  Future<void> _showDeleteConfirm(
    BuildContext context,
    BookshelfProvider p,
  ) async {
    final selectedUrls = Set<String>.from(_selectedUrls);
    final confirmed = await showAppConfirm(
      context: context,
      title: '確認刪除',
      message:
          '將永久刪除這 ${selectedUrls.length} 本書，以及本機章節、正文快取、下載任務與封面資料。此操作無法復原。',
      confirmLabel: '刪除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(this.context);
    try {
      for (final url in selectedUrls) {
        await p.deleteBook(url);
      }
      if (!mounted) return;
      _exitEditMode();
      messenger.showSnackBar(
        SnackBar(content: Text('已刪除 ${selectedUrls.length} 本書')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('刪除失敗: $e')));
    }
  }
}
