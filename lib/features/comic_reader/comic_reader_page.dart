import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/comic/comic_chapter_download.dart';
import 'package:night_reader/core/comic/comic_chapter_numbers.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_controller.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_side_panel.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_window_settings.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/shared/navigation/status_bar.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/theme_reveal_scope.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'comic_page_source.dart';
import 'comic_progress_sync.dart';
import 'comic_reader_menu.dart';
import 'comic_strip_model.dart';
import 'comic_strip_view.dart';
import 'network_comic_page_source.dart';

/// 漫畫閱讀器（ADR 0052、`docs/design/comics.md`）：條漫加上閱讀選單。
/// 平常只有圖，點中間叫出選單；進度記「第幾話第幾張」（`Book.charOffset`
/// 是第幾張，`visualOffsetPx` 是在那張讀到幾成，只用在這台回到原處）。
class ComicReaderPage extends StatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.book,
    this.startChapter,
    this.initialChapters = const <BookChapter>[],
    this.pageSource,
  });

  final Book book;

  /// 從第幾話開頭讀；null 是接著上次讀到的地方。
  final int? startChapter;
  final List<BookChapter> initialChapters;

  /// 圖從哪裡來；null 時照書源（網路書）。測試與本地漫畫傳自己的。
  final ComicPageSource? pageSource;

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

enum _MoreAction { changeSource, refetchChapter, bookDetail, globalSettings }

class _ComicReaderPageState extends State<ComicReaderPage> {
  static const Duration _saveDelay = Duration(milliseconds: 400);

  final ReaderV2SettingsController _settings = ReaderV2SettingsController();
  final ValueNotifier<bool> _menuVisible = ValueNotifier(false);
  final ValueNotifier<bool> _autoScrolling = ValueNotifier(false);
  final ValueNotifier<int> _currentChapter = ValueNotifier(0);
  final ValueNotifier<ComicMenuProgress> _progress = ValueNotifier(
    const ComicMenuProgress(chapterIndex: 0, pageIndex: 0, pageCount: 0),
  );
  final ValueNotifier<ReaderV2ScrubState> _scrub = ValueNotifier((
    isScrubbing: false,
    percent: 0,
  ));
  final ReaderV2SidePanelController _chapterPanel =
      ReaderV2SidePanelController();
  final ComicStripController _strip = ComicStripController();

  List<BookChapter> _chapters = const [];
  BookSource? _source;
  ComicStripModel? _model;
  double _initialFraction = 0;
  Object? _loadError;

  ComicLocation? _pendingSave;
  Timer? _saveTimer;
  ComicLocation? _location;
  late final ComicProgressSync _sync = ComicProgressSync(
    book: _book,
    bookDao: getIt<BookDao>(),
    current: () => _location,
    flush: _flush,
    titles: () => [for (final chapter in _chapters) chapter.title],
    jumpTo: (chapter, page) => _jumpTo(chapter, pageIndex: page),
    resumes: widget.startChapter == null,
  );

  Book get _book => widget.book;

  @override
  void initState() {
    super.initState();
    _strip.onAutoScrollStopped = () => _autoScrolling.value = false;
    _menuVisible.addListener(() {
      final behind = _menuBehind;
      if (_menuVisible.value && behind != null) {
        _refreshProgress(behind.chapterIndex, behind.pageIndex);
      }
    });
    unawaited(_settings.loadSettings());
    unawaited(_open());
  }

  @override
  void dispose() {
    // 存好最後的位置再上傳（[ComicProgressSync.dispose] 會先 flush）。
    _sync.dispose();
    _model?.dispose();
    _settings.dispose();
    _menuVisible.dispose();
    _autoScrolling.dispose();
    _currentChapter.dispose();
    _progress.dispose();
    _scrub.dispose();
    _chapterPanel.dispose();
    super.dispose();
  }

  // ─── 開書與進度 ─────────────────────────────────────────────────────

  Future<void> _open() async {
    try {
      var chapters = widget.initialChapters;
      if (chapters.isEmpty) {
        chapters = await getIt<ChapterDao>().getByBook(_book.bookUrl);
      }
      BookSource? source;
      if (!_book.isLocal) {
        source = await getIt<BookSourceDao>().getByUrl(_book.origin);
        if (source == null) throw StateError('找不到這本書的書源');
        if (chapters.isEmpty) {
          chapters = await BookSourceService().getChapterList(source, _book);
          if (_book.isInBookshelf) {
            await getIt<ChapterDao>().insertChapters(chapters);
          }
        }
      }
      if (chapters.isEmpty) throw StateError('目錄是空的');
      // 換頁動畫播完才建條漫：建整條條漫與選單很重，放在動畫途中會掉幀
      // （ADR 0037 等靜止再放）；動畫期間畫和條漫同比例的骨架。
      await _routeSettled();
      _sync.start();
      // 接著上次讀的地方開：等開 App 的同步做完一下，照同步後的位置開。
      final resume = await _sync.openLocation();
      if (!mounted) return;
      final start = widget.startChapter;
      final chapterIndex = (start ?? resume?.chapterIndex ?? _book.chapterIndex)
          .clamp(0, chapters.length - 1);
      final pageSource =
          widget.pageSource ??
          NetworkComicPageSource(
            book: _book,
            source: source!,
            chapters: chapters,
          );
      final model = ComicStripModel(
        source: pageSource,
        chapterCount: chapters.length,
        chapterIndex: chapterIndex,
        pageIndex: start == null ? resume?.pageIndex ?? _book.charOffset : 0,
      )..addListener(_onModel);
      setState(() {
        _chapters = chapters;
        _source = source;
        _model = model;
        _initialFraction = start == null
            ? (resume?.fraction ?? _book.visualOffsetPx)
                  .clamp(0.0, 1.0)
                  .toDouble()
            : 0;
      });
      _currentChapter.value = chapterIndex;
      _refreshProgress(chapterIndex, model.anchorPage);
      model.start();
      _sync.bookOpened();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// 這一頁的進場動畫播完（沒有動畫時馬上完成）。
  Future<void> _routeSettled() async {
    // 開書從 initState 開始，那時還不能查上層的路由：先讓出一次。
    await Future<void>.value();
    if (!mounted) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) return;
    final done = Completer<void>();
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.forward ||
          status == AnimationStatus.reverse) {
        return;
      }
      animation.removeStatusListener(listener);
      if (!done.isCompleted) done.complete();
    }

    animation.addStatusListener(listener);
    await done.future;
  }

  void _onModel() {
    final shown = _progress.value;
    final at =
        _menuBehind ??
        (chapterIndex: shown.chapterIndex, pageIndex: shown.pageIndex);
    _refreshProgress(at.chapterIndex, at.pageIndex);
  }

  /// 選單要顯示的進度。選單收著時不推給它（收著也在元件樹上，推了就整塊
  /// 重建，捲動中每換一張就多花幾毫秒），打開的那一刻再補上。
  ({int chapterIndex, int pageIndex})? _menuBehind;

  void _refreshProgress(int chapterIndex, int pageIndex) {
    if (!_menuVisible.value) {
      _menuBehind = (chapterIndex: chapterIndex, pageIndex: pageIndex);
      return;
    }
    _menuBehind = null;
    _progress.value = ComicMenuProgress(
      chapterIndex: chapterIndex,
      pageIndex: pageIndex,
      pageCount: _model?.pageCountOf(chapterIndex) ?? 0,
    );
  }

  void _onLocation(ComicLocation location) {
    _location = location;
    _currentChapter.value = location.chapterIndex;
    _refreshProgress(location.chapterIndex, location.pageIndex);
    _pendingSave = location;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () {
      final pending = _pendingSave;
      _pendingSave = null;
      if (pending != null) unawaited(_save(pending));
    });
  }

  Future<void> _save(ComicLocation location) async {
    final title = _titleOf(location.chapterIndex);
    final movedAt = await getIt<BookDao>().updateProgress(
      _book.bookUrl,
      location.chapterIndex,
      title,
      location.pageIndex,
      visualOffsetPx: location.fraction,
    );
    _book
      ..chapterIndex = location.chapterIndex
      ..charOffset = location.pageIndex
      ..visualOffsetPx = location.fraction
      ..durChapterTitle = title
      ..durChapterTime = DateTime.now().millisecondsSinceEpoch;
    if (movedAt != null) _book.progressTime = movedAt;
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    final pending = _pendingSave;
    _pendingSave = null;
    if (pending != null) await _save(pending);
  }

  String _titleOf(int index) =>
      index >= 0 && index < _chapters.length ? _chapters[index].title : '';

  int _gapBetween(int from, int to) =>
      ComicChapterNumbers.gapBetween(_titleOf(from), _titleOf(to));

  // ─── 操作 ───────────────────────────────────────────────────────────

  void _onTap(ComicTapRegion region) {
    if (_menuVisible.value) {
      _menuVisible.value = false;
      return;
    }
    switch (region) {
      case ComicTapRegion.menu:
        _menuVisible.value = true;
      case ComicTapRegion.previous:
        _strip.scrollByScreen(forward: false);
      case ComicTapRegion.next:
        _strip.scrollByScreen(forward: true);
    }
  }

  void _jumpTo(int chapterIndex, {int pageIndex = 0}) {
    final model = _model;
    if (model == null) return;
    _stopAutoScroll();
    model.jumpTo(chapterIndex, pageIndex: pageIndex);
    _currentChapter.value = chapterIndex;
    _refreshProgress(chapterIndex, pageIndex);
    _onLocation(ComicLocation(chapterIndex, pageIndex));
  }

  void _toggleAutoScroll() {
    if (_autoScrolling.value) {
      _stopAutoScroll();
      return;
    }
    _autoScrolling.value = true;
    _menuVisible.value = false;
    _strip.setAutoScroll(_settings.autoPageSpeed);
  }

  void _stopAutoScroll() {
    if (!_autoScrolling.value) return;
    _autoScrolling.value = false;
    _strip.setAutoScroll(0);
  }

  /// 深淺是整個 App 共用的設定，閱讀器切換後其他畫面一併跟著換。
  void _toggleDayNight() {
    final dark = StylePalette.of(context).brightness == Brightness.dark;
    final settings = context.read<SettingsProvider>();
    ThemeRevealScope.of(context).run(
      change: () =>
          settings.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
    );
  }

  Future<void> _openPreferences() => ReaderV2MenuSheet.show<void>(
    context,
    settings: _settings,
    builder: (context) => ReaderV2SheetScaffold(
      title: '漫畫偏好',
      children: [
        NumberStepperRow(
          label: '自動捲動速度',
          value: _settings.autoPageSpeed,
          min: ReaderV2SettingsController.minAutoPageSpeed,
          max: ReaderV2SettingsController.maxAutoPageSpeed,
          step: 0.01,
          displayScale: 100,
          unit: '%',
          onChanged: (speed) {
            _settings.setAutoPageSpeed(speed);
            if (_autoScrolling.value) _strip.setAutoScroll(speed);
          },
        ),
      ],
    ),
  );

  Future<void> _showMore() async {
    final action = await showAppActionSheet<_MoreAction>(
      context: context,
      actions: [
        if (!_book.isLocal) ...const [
          AppSheetAction(
            label: '換源',
            icon: Icons.swap_horiz_rounded,
            value: _MoreAction.changeSource,
          ),
          AppSheetAction(
            label: '重新取得本章',
            icon: Icons.refresh_rounded,
            value: _MoreAction.refetchChapter,
          ),
        ],
        const AppSheetAction(
          label: '書籍詳情',
          icon: Icons.info_outline_rounded,
          value: _MoreAction.bookDetail,
        ),
        const AppSheetAction(
          label: '全域系統設定',
          icon: Icons.settings_suggest_rounded,
          value: _MoreAction.globalSettings,
        ),
      ],
    );
    if (!mounted || action == null) return;
    _menuVisible.value = false;
    switch (action) {
      case _MoreAction.changeSource:
        await _showChangeSource();
      case _MoreAction.refetchChapter:
        await _refetchChapter();
      case _MoreAction.bookDetail:
        await _showBookDetail();
      case _MoreAction.globalSettings:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
        if (mounted) unawaited(_settings.loadSettings());
    }
  }

  /// 換源：清單只列漫畫源（ADR 0053）；選好後先抓目標那一話確認有圖，
  /// 再換掉書與目錄，用新書源重開閱讀器，接著讀同一話同一張。
  Future<void> _showChangeSource() async {
    PreparedSourceSwitch? prepared;
    await AppBottomSheet.showCustom<void>(
      context: context,
      constraints: ReaderV2MenuSheet.constraintsFor(context, _settings),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeSourceSheet(
        book: _book,
        onSelectSource: (candidate) =>
            _switchSource(candidate, onSuccess: (done) => prepared = done),
      ),
    );
    final done = prepared;
    if (!mounted || done == null) return;
    unawaited(
      Navigator.of(context).pushReplacement(
        BookOpenRoute(book: done.migratedBook, initialChapters: done.chapters),
      ),
    );
  }

  Future<ChangeSourceOutcome> _switchSource(
    SearchBook candidate, {
    required void Function(PreparedSourceSwitch prepared) onSuccess,
  }) async {
    final service = SourceSwitchService(
      operationQuiescer: (oldBook) =>
          DownloadService().quiesceForSourceSwitch(oldBook),
      assetRetirer: BookCoverStorageService().handoffSourceSwitchAssets,
    );
    try {
      await _flush();
      final location = _progress.value;
      final title = _titleOf(location.chapterIndex);
      final prepared = await service.prepareSwitch(
        _book.copyWith(
          chapterIndex: location.chapterIndex,
          durChapterTitle: title,
          charOffset: location.pageIndex,
        ),
        candidate,
        targetChapterIndex: location.chapterIndex,
        targetChapterTitle: title.isEmpty ? null : title,
      );
      await service.commitSwitch(_book, prepared);
      AppEventBus().fire(AppEventBus.upBookshelf);
      onSuccess(prepared);
      return (success: true, message: '已切換到 ${prepared.source.bookSourceName}');
    } catch (error) {
      if (!isSourceSwitchUnavailable(error)) rethrow;
      return (success: false, message: failureMessage('換源', error));
    }
  }

  /// 刪掉這一話下載好的與抓到一半的圖，照書源重抓。
  Future<void> _refetchChapter() async {
    final index = _currentChapter.value;
    final chapter = _chapters[index];
    final cbz = await ComicChapterDownload.cbzFor(_book, chapter);
    if (cbz != null) await cbz.delete();
    final partial = await ComicChapterDownload.partialDirFor(_book, chapter);
    if (await partial.exists()) await partial.delete(recursive: true);
    imageCache.clear();
    if (!mounted) return;
    final model = _model;
    if (model == null) return;
    final source =
        widget.pageSource ??
        NetworkComicPageSource(
          book: _book,
          source: _source!,
          chapters: _chapters,
        );
    final fresh = ComicStripModel(
      source: source,
      chapterCount: _chapters.length,
      chapterIndex: index,
    )..addListener(_onModel);
    model
      ..removeListener(_onModel)
      ..dispose();
    setState(() {
      _model = fresh;
      _initialFraction = 0;
    });
    fresh.start();
  }

  Future<void> _showBookDetail() async {
    await _flush();
    if (!mounted) return;
    final targetUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => BookDetailPage(book: _book, fromReader: true),
      ),
    );
    if (!mounted || targetUrl == null) return;
    final index = _chapters.indexWhere((chapter) => chapter.url == targetUrl);
    if (index >= 0) _jumpTo(index);
  }

  Future<void> _openWeb(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _exit() async {
    await _flush();
    if (mounted) Navigator.of(context).pop();
  }

  // ─── 畫面 ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = StylePalette.of(context);
    final dark = palette.brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => StatusBarHidden(
        hidden: _settings.hideStatusBar,
        hideNavigationBar: _settings.hideNavigationBar,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: ReaderV2WindowSettings(
            keepScreenOn: _settings.keepScreenOn,
            backlight: null,
            orientation: _settings.orientation,
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (_chapterPanel.isOnScreen) {
                  _chapterPanel.close();
                } else if (_menuVisible.value) {
                  _menuVisible.value = false;
                } else {
                  unawaited(_exit());
                }
              },
              child: Scaffold(
                backgroundColor: palette.readerBackground,
                body: _buildBody(context, palette, dark),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, StylePalette palette, bool dark) {
    final model = _model;
    if (model == null) {
      return _loadError == null
          ? const _OpeningSkeleton()
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '打不開這本漫畫：$_loadError',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.readerText),
                ),
              ),
            );
    }
    final navigation = ReaderV2ChapterNavigationState(
      chapterCount: _chapters.length,
      current: _currentChapter,
      scrub: _scrub,
      titleFor: _titleOf,
    );
    return ReaderV2SidePanel(
      controller: _chapterPanel,
      panel: ReaderV2ChaptersDrawer(
        shown: _chapterPanel.shown,
        chapters: _chapters,
        currentChapter: _currentChapter,
        titleFor: _titleOf,
        onChapterTap: (index) {
          _chapterPanel.close();
          _jumpTo(index);
        },
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ComicStripView(
              key: ObjectKey(model),
              model: model,
              controller: _strip,
              foreground: palette.readerText,
              accent: palette.primary,
              initialFraction: _initialFraction,
              onLocation: _onLocation,
              onTap: _onTap,
              titleOf: _titleOf,
              gapBetween: _gapBetween,
              webUrlOpener: (url) => unawaited(_openWeb(url)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: ReaderV2TopMenu(
              controlsVisible: _menuVisible,
              bookName: _book.name,
              navigation: navigation,
              originName: _book.isLocal ? '' : _book.originName,
              showReadTitleAddition: true,
              onBack: () => unawaited(_exit()),
              onMore: () => unawaited(_showMore()),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ComicReaderBottomMenu(
              controlsVisible: _menuVisible,
              progress: _progress,
              chapterCount: _chapters.length,
              autoScrolling: _autoScrolling,
              dayNightIcon: dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              dayNightTooltip: dark ? '淺色' : '深色',
              onToggleAutoScroll: _toggleAutoScroll,
              onToggleDayNight: _toggleDayNight,
              onPrevChapter: () => _jumpTo(_currentChapter.value - 1),
              onNextChapter: () => _jumpTo(_currentChapter.value + 1),
              onSeekPage: (page) =>
                  _jumpTo(_currentChapter.value, pageIndex: page),
              onOpenChapters: () {
                _menuVisible.value = false;
                _chapterPanel.open();
              },
              onPreferences: () => unawaited(_openPreferences()),
            ),
          ),
        ],
      ),
    );
  }
}

/// 開書時（換頁動畫期間、第一話還沒載好）畫的骨架：和條漫還不知道寬高時
/// 的骨架同比例，條漫接手時看不出換了一層。
class _OpeningSkeleton extends StatelessWidget {
  const _OpeningSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = width * ComicStripModel.defaultAspectRatio;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Skeleton(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < ComicStripModel.placeholderPages; i++)
                  SkeletonBox(
                    width: width,
                    height: height,
                    borderRadius: BorderRadius.zero,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
