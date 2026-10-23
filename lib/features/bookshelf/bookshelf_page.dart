import 'dart:async';
import 'dart:io';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/bookshelf_exchange_service.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_motion.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_skeleton.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/navigation/app_route_observer.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/core/services/app_file_selection_service.dart';
import 'package:night_reader/shared/theme/app_haptics.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/core/services/chinese_display.dart';

enum _BookshelfBatchAction { checkUpdate, delete }

/// 頁首兩個選單的非排序項目；排序項目直接用 [BookshelfSortMode]。
/// 左邊「整理」管書架怎麼看、怎麼排，右邊「加入」把書帶進書架。
enum _ShelfMenuAction {
  gridView,
  listView,
  unifiedCovers,
  select,
  export,
  search,
  addLocal,
  importUrl,
  importFile,
}

/// 長按書籍的情境選單項目。
enum _BookMenuAction { detail, select, checkUpdate, autoUpdate, remove }

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage>
    with TickerProviderStateMixin, RouteAware {
  bool _isMultiSelect = false;

  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 用 pageRouteOf 不用 ModalRoute.of：後者會讓書架依賴路由狀態，每次有
    // 頁面推入或移走都整頁重建（ADR 0018）。
    final route = pageRouteOf(context);
    if (route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
  }

  /// 別的頁面蓋上書架（書籍詳情、搜尋、閱讀器……）：背景下載完成的重讀
  /// 先記著，不在別人的換頁動畫裡重排被蓋住的書架（ADR 0018、0029）。
  @override
  void didPushNext() => context.read<BookshelfProvider>().setCovered(true);

  /// 書架露出來、返回動畫播完，才補做被蓋住時記下的重讀。
  @override
  void didPopNext() {
    final provider = context.read<BookshelfProvider>();
    unawaited(
      TransitionSettled.uncovered(context).then((_) {
        if (mounted) provider.setCovered(false);
      }),
    );
  }

  final Set<String> _selectedUrls = {};
  _BookshelfBatchAction? _batchAction;

  /// 換排序、書移到最前面時書卡平滑換位，新加入的書淡入。
  /// 移出的書淡完時重建一次，清單才真的拿掉它們、其他書卡補位。
  late final BookshelfLayoutMotion _motion = BookshelfLayoutMotion(
    vsync: this,
    onRemovalsFaded: () {
      if (mounted) setState(() {});
    },
  );

  /// 畫面上的書（含淡出中、已不在書架上的書），供淡出期間照舊畫出來。
  Map<String, Book> _shownBooks = const {};

  /// 書架空著時才用到：還沒有書源時主按鈕改成匯入書源。第一次書架空著
  /// 時才開始查；查到之前是 null，骨架留著，不先畫其中一種空書架。
  bool? _hasSources;
  StreamSubscription<bool>? _hasSourcesSub;

  void _watchSources() {
    if (_hasSourcesSub != null) return;
    final stream = getIt.isRegistered<BookSourceDao>()
        ? getIt<BookSourceDao>().watchHasAny()
        : Stream<bool>.value(true);
    _hasSourcesSub = stream.listen(
      (value) {
        if (mounted && value != _hasSources) {
          setState(() => _hasSources = value);
        }
      },
      // 查不到時照有書源畫（原本的空書架）。
      onError: (Object _) {
        if (mounted && _hasSources == null) {
          setState(() => _hasSources = true);
        }
      },
    );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    unawaited(_hasSourcesSub?.cancel());
    _motion.dispose();
    super.dispose();
  }

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
    AppHaptics.select();
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
        // 批次作業進行中留在編輯模式，結束時才由作業本身退出。
        if (didPop || !_isMultiSelect || _batchAction != null) return;
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
                // 編輯工具列佔用分頁列的位置時，漸隱帶改由這裡墊在它後面。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FloatingTabBarFade(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    hidden: !_isMultiSelect,
                  ),
                ),
                Positioned(
                  left: slot.left,
                  right: slot.right,
                  bottom: slot.bottom,
                  child: AnimatedSwitcher(
                    duration: AppMotion.menu,
                    switchInCurve: AppMotion.menuCurve,
                    switchOutCurve: Curves.easeInCubic,
                    // 跟分頁列一樣從畫面外滑上來，不淡（ADR 0022）。
                    transitionBuilder: (child, animation) => AnimatedBuilder(
                      animation: animation,
                      child: child,
                      builder: (context, child) => GlassSlide(
                        shown: animation.value,
                        edge: AxisDirection.down,
                        gap: slot.bottom,
                        child: child!,
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
        morph: true,
        title: '已選 ${_selectedUrls.length} 本',
        leading: GlassTextButton(
          label: '完成',
          emphasized: true,
          onPressed: _batchAction != null ? null : _exitEditMode,
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
    // 進出多選時標題淡換、兩側按鈕的玻璃留著只改大小（GlassMorph）。
    return GlassNavHeader(
      morph: true,
      title: '書架',
      titleSheen: provider.checkingShelf,
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
      GlassMenuItem(
        value: _ShelfMenuAction.unifiedCovers,
        label: '統一封面',
        icon: Icons.nights_stay_outlined,
        checked: provider.unifiedCovers,
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
      case _ShelfMenuAction.unifiedCovers:
        provider.setUnifiedCovers(!provider.unifiedCovers);
      case _ShelfMenuAction.select:
        _enterEditMode();
      case _ShelfMenuAction.search:
        _openSearch();
      case _ShelfMenuAction.addLocal:
        await _pickLocalBook(provider);
      case _ShelfMenuAction.importFile:
        await _handleBookshelfImport(context);
      case _ShelfMenuAction.importUrl:
        await _showImportBookshelfUrlDialog(context, provider);
      case _ShelfMenuAction.export:
        await _handleBookshelfExport(context, provider);
    }
  }

  /// 初次載入時顯示與目前檢視同形、本數與上次相同的骨架（開 App 時隨進場
  /// 出現，見 [LaunchEntrance]）；書到了、書名的繁簡轉換字典也好了，再等
  /// 畫面上的封面解碼好，書卡連同封面一次換場。
  Widget _buildContent(BuildContext context, BookshelfProvider provider) {
    final insets = MediaQuery.paddingOf(context);
    final empty = provider.books.isEmpty;
    if (empty && !provider.isLoading) _watchSources();
    return SkeletonSwitcher(
      // 第一次是空書架時，查到有沒有書源之前骨架留著：不先畫「搜尋書籍」
      // 再一幀換成「匯入書源」，骨架直接換場成對的那一種。
      // 第一次換場前字典還沒好時骨架也留著：書名不會換場後才從原文變成
      // 轉換後的字。
      loading:
          empty &&
              (provider.isLoading || _hasSources == null && !_contentShown) ||
          !_contentShown && !ChineseDisplay.readyOf(context),
      waitForCovers: CoverWait.onDevice,
      entrance: LaunchEntrance.maybeOf(context),
      // 書架直接畫在頁面底色上：換場只遮骨架一層（ADR 0029）。
      backdrop: Theme.of(context).scaffoldBackgroundColor,
      skeleton: BookshelfSkeleton(
        grid: provider.isGridView,
        bookCount: provider.lastBookCount,
        titles: provider.lastShelfTitles,
        padding: EdgeInsets.fromLTRB(
          AppGrouped.margin,
          insets.top + AppSpacing.xs,
          AppGrouped.margin,
          insets.bottom + AppSpacing.md,
        ),
      ),
      builder: (_) => _buildLoadedContent(provider, insets),
    );
  }

  /// 書架內容已經換場出來過；之後書架變空（移出最後一本）不再退回骨架。
  bool _contentShown = false;

  Widget _buildLoadedContent(BookshelfProvider provider, EdgeInsets insets) {
    _contentShown = true;
    final grid = provider.isGridView;
    final animate = !MediaQuery.disableAnimationsOf(context);
    // 移出的書淡出期間仍在清單裡（已不在書架上，取上次畫的那一本）。
    final shownUrls = _motion.update(
      [for (final book in provider.books) book.bookUrl],
      grid: grid,
      animate: animate,
    );
    final known = {
      ..._shownBooks,
      for (final book in provider.books) book.bookUrl: book,
    };
    final books = [for (final url in shownUrls) ?known[url]];
    _shownBooks = {for (final book in books) book.bookUrl: book};
    // 載入失敗時已有的書照常顯示；只有什麼都沒有時才換成錯誤頁。
    if (books.isEmpty && provider.loadErrorMessage != null) {
      return Padding(
        padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
        child: AppStateView(
          icon: Icons.error_outline,
          title: '書架載入失敗',
          description: provider.loadErrorMessage,
          tone: AppStateTone.error,
          primaryAction: AppStateAction(
            label: '重試',
            icon: Icons.refresh,
            onPressed: provider.loadBooks,
          ),
        ),
      );
    }
    if (books.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: insets.top, bottom: insets.bottom),
        // 還不知道有沒有書源時先空著（移出最後一本書之後），知道了再淡入
        // 對的那一種；之後書源有無改變時兩種交叉淡換。
        child: AnimatedSwitcher(
          duration: animate ? AppMotion.fade : Duration.zero,
          switchInCurve: AppMotion.fadeCurve,
          switchOutCurve: AppMotion.fadeCurve,
          child: switch (_hasSources) {
            null => const SizedBox.expand(key: ValueKey('unknown')),
            true => AppStateView(
              key: const ValueKey('has-sources'),
              icon: Icons.auto_stories_outlined,
              title: '書架還是空的',
              description: '搜尋並加入一本書，之後就能從這裡繼續閱讀。',
              primaryAction: AppStateAction(
                label: '搜尋書籍',
                icon: Icons.search,
                onPressed: _openSearch,
              ),
            ),
            false => AppStateView(
              key: const ValueKey('no-sources'),
              icon: Icons.auto_stories_outlined,
              title: '書架還是空的',
              description: '匯入書源後就能搜尋網路小說，手機裡的 TXT 也能直接加入。',
              primaryAction: AppStateAction(
                label: '匯入書源',
                icon: Icons.download_rounded,
                onPressed: _openSourceManager,
              ),
              secondaryAction: AppStateAction(
                label: '加入本地書籍',
                icon: Icons.file_open_outlined,
                onPressed: () => unawaited(_pickLocalBook(provider)),
              ),
            ),
          },
        ),
      );
    }
    // 編輯工具列佔用分頁列的位置，清單底部讓出的高度不變。
    final bottom = insets.bottom + AppSpacing.md;
    // 下拉在背景檢查更新：不轉圈，檢查期間不會重複觸發；結果只在書卡角標
    // 上顯示 5 秒。
    return RefreshIndicator.noSpinner(
      onRefresh: () => provider.refreshBookshelf(userInitiated: true),
      // 網格與列表互換時交叉淡化加輕微縮放。兩種檢視的封面大小、位置與
      // 捲動位置都不同，逐本原地變形要同時排出兩份版面，畫面外的書也對
      // 不上；整頁淡化較穩，也和 App 其他淡入淡出一致。
      child: AnimatedSwitcher(
        duration: animate ? AppMotion.fade : Duration.zero,
        switchInCurve: AppMotion.fadeCurve,
        switchOutCurve: AppMotion.fadeCurve,
        // 淡出中的舊版面不該再接點擊或被讀屏念到。
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [
            for (final child in previous)
              IgnorePointer(child: ExcludeSemantics(child: child)),
            ?current,
          ],
        ),
        // 版面是內容，只交叉淡化、不縮放（ADR 0022）。
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(
          key: ValueKey(grid),
          // 清單本身另外排一塊：開 App 骨架呼吸時，外層與清單（捲動、每一格
          // 的位置）分在不同幀建，之後才一張張建書卡（[CoverReveal.inSteps]）。
          child: CoverRevealSlot(
            placeholder: const SizedBox.expand(),
            child: grid
                ? _buildGridView(provider, books, insets.top, bottom)
                : _buildListView(provider, books, insets.top, bottom),
          ),
        ),
      ),
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
          .showSnackBar(SnackBar(content: Text(failureMessage('匯入', e))));
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
            decoration: const InputDecoration(hintText: 'https://'),
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
          .showSnackBar(SnackBar(content: Text(failureMessage('書架網址匯入', e))));
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
      unawaited(context.read<BookshelfProvider>().loadBooks());
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
          .showSnackBar(SnackBar(content: Text(failureMessage('匯入', e))));
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
          .showSnackBar(SnackBar(content: Text(failureMessage('匯出', e))));
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
          .showSnackBar(SnackBar(content: Text(failureMessage('批次檢查更新', e))));
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
      _BookshelfBatchAction.checkUpdate =>
        provider.updatingCount > 0
            ? '正在檢查更新（剩 ${provider.updatingCount} 本）'
            : '正在整理更新結果…',
      _BookshelfBatchAction.delete => '正在刪除…',
      null => '已選擇 ${_selectedUrls.length} 本',
    };
  }

  Widget _buildListView(
    BookshelfProvider provider,
    List<Book> books,
    double topInset,
    double bottomInset,
  ) {
    final padding = EdgeInsets.fromLTRB(
      AppGrouped.margin,
      topInset + AppSpacing.xs,
      AppGrouped.margin,
      bottomInset,
    );
    // 自訂排序時長按拖曳換位置，不開情境選單；其餘操作走「選取」。多選時
    // 仍是同一個清單、只關掉拖曳：換成另一種清單會丟掉捲動位置，書卡也會
    // 重建，勾選圈直接冒出來而不是滑進來。
    if (provider.sortMode == BookshelfSortMode.custom) {
      return SwipeActionsGroup(
        child: ReorderableListView.builder(
          padding: padding,
          itemCount: books.length,
          // 拖曳的起點自己包（見下面），多選時關掉；預設的會依開關換外層
          // 元件，書卡跟著重建。
          buildDefaultDragHandles: false,
          onReorderStart: (_) => AppHaptics.lift(),
          onReorderEnd: (_) => AppHaptics.snap(),
          onReorderItem: (oldIndex, newIndex) {
            // 清單裡可能還有淡出中的書（已不在書架上）：照書換算成書架上的
            // 位置。
            final shown = [...books];
            final moved = shown.removeAt(oldIndex);
            final from = provider.books.indexWhere(
              (book) => book.bookUrl == moved.bookUrl,
            );
            if (from < 0) return;
            final shelf = {for (final book in provider.books) book.bookUrl};
            final to = shown
                .take(newIndex)
                .where((book) => shelf.contains(book.bookUrl))
                .length;
            // reorderBooks 在第一個 await 之前就換好清單順序；清單本身已經把
            // 書卡放到定位，採用新順序，不再播換位動畫。
            unawaited(provider.reorderBooks(from, to));
            _motion.accept([for (final book in provider.books) book.bookUrl]);
          },
          // 預設的拖曳外觀會在卡片外距外畫出方形陰影，改成只微微放大。
          proxyDecorator: (child, _, animation) => ScaleTransition(
            scale: Tween<double>(begin: 1, end: 1.03).animate(
              CurvedAnimation(parent: animation, curve: AppMotion.menuCurve),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
          itemBuilder: (context, index) => ReorderableDelayedDragStartListener(
            key: ValueKey(books[index].bookUrl),
            index: index,
            enabled: !_isMultiSelect,
            child: _buildListCard(provider, books[index], reorderable: true),
          ),
        ),
      );
    }
    return SwipeActionsGroup(
      child: ListView.builder(
        padding: padding,
        itemCount: books.length,
        // 每張書卡外面的 BookshelfMotionItem 已經自成一個繪製層，清單不再
        // 多包一層：少一層要合成，開 App 建清單那一格也少建一些。
        addRepaintBoundaries: false,
        itemBuilder: (context, index) => _buildListCard(provider, books[index]),
      ),
    );
  }

  Widget _buildListCard(
    BookshelfProvider provider,
    Book shown, {
    bool reorderable = false,
  }) {
    final selecting = _isMultiSelect;
    final card = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CoverRevealSlot(
        placeholder: const SizedBox(
          height: BookshelfListCard.coverHeight + AppSpacing.md * 2,
        ),
        // 左滑出「檢查更新」「移出書架」。在書卡上橫拖一律滑出動作、不換
        // 分頁（DESIGN.md「按壓回饋」）；滑出的按鈕裁在卡片圓角內。動作在
        // 按下時才讀書架上現在的那本。
        child: ClipRRect(
          borderRadius: AppGrouped.cardRadius,
          child: SwipeActions(
            enabled: !selecting,
            trailing: [
              if (!shown.isLocal)
                SwipeAction(
                  label: '檢查更新',
                  icon: Icons.update,
                  color: AppTint.azurite.color,
                  onPressed: () =>
                      _checkUpdateOne(provider, provider.current(shown)),
                ),
              SwipeAction(
                label: '移出書架',
                icon: Icons.delete_outline,
                color: AppTint.rust.color,
                destructive: true,
                onPressed: () =>
                    _confirmRemoveOne(provider, provider.current(shown)),
              ),
            ],
            // 書架重讀時只有這本書看得到的內容變了才重建這張書卡；點開、
            // 長按在按下時才讀書架上現在的那本（閱讀位置這些看不到的欄位
            // 可能已經換過）。
            child: ValueListenableBuilder<Book>(
              valueListenable: provider.bookListenable(shown),
              builder: (context, book, _) => _UpdateBadgeOf(
                badges: provider.updateBadges,
                bookUrl: book.bookUrl,
                builder: (badge) => BookshelfListCard(
                  book: book,
                  updateBadge: selecting ? null : badge,
                  selecting: selecting,
                  selected: _selectedUrls.contains(book.bookUrl),
                  onTap: () => selecting
                      ? _toggleSelected(book)
                      : _openBook(provider.current(book)),
                  onLongPress: selecting || reorderable
                      ? null
                      : (rect) => _showBookMenu(
                          provider,
                          provider.current(book),
                          rect,
                          grid: false,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return BookshelfMotionItem(id: shown.bookUrl, motion: _motion, child: card);
  }

  Widget _buildGridView(
    BookshelfProvider provider,
    List<Book> books,
    double topInset,
    double bottomInset,
  ) {
    const columns = 3;
    final width = MediaQuery.sizeOf(context).width;
    final cellWidth =
        (width - AppGrouped.margin * 2 - AppSpacing.lg * (columns - 1)) /
        columns;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        AppGrouped.margin,
        topInset + AppSpacing.xs,
        AppGrouped.margin,
        bottomInset,
      ),
      // 每格外面的 BookshelfMotionItem 已經自成一個繪製層，不再多包一層；
      // 格狀書卡沒有要捲出畫面也留著的狀態（按壓回饋是 PressScale，不是
      // InkWell），不包保留狀態的那一層。開 App 建清單那一格少建一些。
      addRepaintBoundaries: false,
      addAutomaticKeepAlives: false,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        // 列高依格寬與系統字級算出，兩行書名放大時也放得下。
        mainAxisExtent: BookshelfGridTile.heightFor(
          cellWidth,
          MediaQuery.textScalerOf(context),
        ),
        crossAxisSpacing: AppSpacing.lg,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final shown = books[index];
        return BookshelfMotionItem(
          id: shown.bookUrl,
          motion: _motion,
          child: CoverRevealSlot(
            // 書架重讀時只有這本書看得到的內容變了才重建這張書卡；點開、
            // 長按在按下時才讀書架上現在的那本（閱讀位置這些看不到的欄位
            // 可能已經換過）。
            child: ValueListenableBuilder<Book>(
              valueListenable: provider.bookListenable(shown),
              builder: (context, book, _) => _UpdateBadgeOf(
                badges: provider.updateBadges,
                bookUrl: book.bookUrl,
                builder: (badge) => BookshelfGridTile(
                  book: book,
                  updateBadge: badge,
                  selecting: _isMultiSelect,
                  selected: _selectedUrls.contains(book.bookUrl),
                  onTap: () => _isMultiSelect
                      ? _toggleSelected(book)
                      : _openBook(provider.current(book)),
                  onLongPress: _isMultiSelect
                      ? null
                      : (rect) => _showBookMenu(
                          provider,
                          provider.current(book),
                          rect,
                          grid: true,
                        ),
                ),
              ),
            ),
          ),
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
            coverUrl: UnifiedCovers.coverOf(book),
            width: sourceRect.width,
            height: sourceRect.height,
            borderRadius: AppRadius.cardXs,
          )
        : BookshelfListCard(book: book);
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
            value: _BookMenuAction.autoUpdate,
            label: '自動檢查更新',
            icon: Icons.autorenew_rounded,
            checked: book.canUpdate,
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
      case _BookMenuAction.autoUpdate:
        await _toggleAutoUpdate(provider, book);
      case _BookMenuAction.remove:
        await _confirmRemoveOne(provider, book);
    }
  }

  /// 正在單獨檢查更新的書；同一本進行中時忽略重複觸發。
  final Set<String> _singleBookBusy = <String>{};

  Future<void> _checkUpdateOne(BookshelfProvider provider, Book book) async {
    if (_batchAction != null || !_singleBookBusy.add(book.bookUrl)) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = context.zh(book.name);
    // 書源慢時要好幾秒才有結果，先告訴使用者已經開始。
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('正在檢查《$name》…')));
    try {
      final results = await provider.batchCheckUpdate({book.bookUrl});
      final result = results.isEmpty ? null : results.first;
      messenger.hideCurrentSnackBar();
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
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage('檢查更新', e))),
      );
    } finally {
      _singleBookBusy.remove(book.bookUrl);
    }
  }

  Future<void> _toggleAutoUpdate(BookshelfProvider provider, Book book) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = context.zh(book.name);
    final enable = !book.canUpdate;
    try {
      await provider.setBookCanUpdate(book, enable);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(enable ? '《$name》恢復自動檢查更新' : '《$name》不再自動檢查更新'),
          ),
        );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage('設定', e))));
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
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage('移出書架', e))),
      );
    }
  }

  void _openDetail(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BookDetailPage(book: book)),
    );
  }

  Future<void> _pickLocalBook(BookshelfProvider provider) async {
    final path = await AppFileSelectionService.instance.pickLocalBookPath();
    if (path != null && mounted) {
      await _importLocalBook(context, provider, path);
    }
  }

  /// 書源管理在還沒有書源時，頁面中央就是匯入按鈕。
  void _openSourceManager() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SourceManagerPage()),
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
  }

  Future<void> _openBook(Book book) async {
    if (book.type == 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('有聲書播放功能已移除，請選擇文本書籍。')));
      return;
    }
    // 閱讀器只改了這本書的進度，不會通知書架；回來時要重排（最近閱讀）並更新
    // 進度線。記成「露出來要重讀」，和閱讀期間下載完成的重讀併成一次，返回
    // 動畫播完才做（didPopNext，ADR 0018）。
    context.read<BookshelfProvider>().reloadWhenUncovered();
    await Navigator.push(
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
      // 走批次作業：工具列顯示進度、期間停用，不能再按刪除或下載。
      await _runBatchAction(_BookshelfBatchAction.delete, p.deleteBooks);
      if (!mounted) return;
      _exitEditMode();
      messenger.showSnackBar(
        SnackBar(content: Text('已刪除 ${selectedUrls.length} 本書')),
      );
    } catch (e) {
      if (!mounted) return;
      // 中途失敗時，已刪掉的書不再留在選取裡。
      final remaining = p.books.map((book) => book.bookUrl).toSet();
      setState(() => _selectedUrls.retainAll(remaining));
      messenger.showSnackBar(SnackBar(content: Text(failureMessage('刪除', e))));
    }
  }
}

/// 只在這本書的角標變了才重建書卡：書架檢查結束、角標出現與消失時，其他
/// 書卡與整個書架都不動（ADR 0018）。
class _UpdateBadgeOf extends StatefulWidget {
  const _UpdateBadgeOf({
    required this.badges,
    required this.bookUrl,
    required this.builder,
  });

  final ValueListenable<Map<String, BookUpdateCheckResult>> badges;
  final String bookUrl;
  final Widget Function(BookUpdateCheckResult? badge) builder;

  @override
  State<_UpdateBadgeOf> createState() => _UpdateBadgeOfState();
}

class _UpdateBadgeOfState extends State<_UpdateBadgeOf> {
  BookUpdateCheckResult? _badge;

  @override
  void initState() {
    super.initState();
    _badge = widget.badges.value[widget.bookUrl];
    widget.badges.addListener(_onBadges);
  }

  @override
  void didUpdateWidget(_UpdateBadgeOf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.badges, widget.badges)) {
      oldWidget.badges.removeListener(_onBadges);
      widget.badges.addListener(_onBadges);
    }
    _badge = widget.badges.value[widget.bookUrl];
  }

  @override
  void dispose() {
    widget.badges.removeListener(_onBadges);
    super.dispose();
  }

  void _onBadges() {
    final badge = widget.badges.value[widget.bookUrl];
    if (identical(badge, _badge)) return;
    setState(() => _badge = badge);
  }

  @override
  Widget build(BuildContext context) => widget.builder(_badge);
}
