import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/use_cases/reader_v2_page_coordinator.dart';
import 'package:night_reader/features/reader_v2/use_cases/coordinators/reader_v2_page_exit_coordinator.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_session_facade.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sheet.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sheets.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';

class ReaderV2Page extends StatefulWidget {
  const ReaderV2Page({
    super.key,
    required this.book,
    this.openTarget,
    this.initialChapters = const <BookChapter>[],
    @visibleForTesting this.sourceSwitchService,
  });

  final Book book;
  final ReaderV2OpenTarget? openTarget;
  final List<BookChapter> initialChapters;

  /// Test-only service injection. Normal app routes leave this null and keep
  /// constructing the same concrete service in the page state.
  @visibleForTesting
  final SourceSwitchService? sourceSwitchService;

  @override
  State<ReaderV2Page> createState() => _ReaderV2PageState();
}

class _ReaderV2PageState extends State<ReaderV2Page>
    implements ReaderV2ExitFlowDelegate {
  static const ReaderV2SessionFacade _sessionFacade = ReaderV2SessionFacade();

  late final SourceSwitchService _sourceSwitchService;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ReaderV2PageExitCoordinator _exitCoordinator =
      ReaderV2PageExitCoordinator();

  late final ReaderV2ControllerHost _host;
  late final ReaderV2PageCoordinator _coordinator;

  final ValueNotifier<HybridProgressSnapshot?> _progress =
      ValueNotifier<HybridProgressSnapshot?>(null);
  Size? _lastViewportSize;
  String? _visibleNoticeMessage;
  bool _rebuildQueued = false;

  /// Integration workload 的語意 probe 入口；正式頁面不透過它驅動畫面。
  @visibleForTesting
  ReaderV2Runtime? get debugRuntime => _host.runtime;

  @visibleForTesting
  ReaderV2SettingsController get debugSettings => _host.settings;

  @visibleForTesting
  SourceSwitchService get debugSourceSwitchService => _sourceSwitchService;

  @visibleForTesting
  Future<ChangeSourceOutcome> debugSelectSourceForTesting(
    SearchBook candidate,
  ) {
    return _handleChangeSourceSelected(candidate);
  }

  /// Test-only equivalent of the successful reader source-switch route.
  ///
  /// The normal UI calls the same replacement helper after the source sheet
  /// closes; keeping this seam in the page lets widget tests exercise the
  /// actual replacement/dispose ordering without opening a network-backed
  /// source sheet.
  @visibleForTesting
  Future<ChangeSourceOutcome> debugSelectSourceAndReplaceForTesting(
    SearchBook candidate,
  ) async {
    PreparedSourceSwitch? preparedSwitch;
    final outcome = await _handleChangeSourceSelected(
      candidate,
      onSuccess: (value) => preparedSwitch = value,
    );
    if (mounted && outcome.success && preparedSwitch != null) {
      _pushReplacementForPreparedSwitch(preparedSwitch!);
    }
    return outcome;
  }

  @override
  void initState() {
    super.initState();
    _sourceSwitchService =
        widget.sourceSwitchService ??
        SourceSwitchService(
          operationQuiescer: (oldBook) =>
              DownloadService().quiesceForSourceSwitch(oldBook),
          assetRetirer: BookCoverStorageService().handoffSourceSwitchAssets,
        );
    _host = ReaderV2ControllerHost(
      book: widget.book,
      initialChapters: widget.initialChapters,
      openTarget: widget.openTarget,
      onChanged: _handleControllerChanged,
      isMounted: () => mounted,
    );
    _coordinator = ReaderV2PageCoordinator(
      host: _host,
      showNotice: _showNotice,
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _coordinator.dispose();
    _progress.dispose();
    _host.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    _drainRuntimeNotice();
    _drainAutoPageNotice();
    _coordinator.maybeFollowTtsHighlight();
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    if (!mounted || _rebuildQueued) return;
    _rebuildQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _host.settings;
    final menu = _host.menu;
    final runtime = _host.runtime;
    final theme = settings.currentTheme;
    final menuTheme = settings.currentMenuTheme;
    final isDarkBackground = theme.backgroundColor.computeLuminance() < 0.5;
    final chapterIndex = _currentChapterIndex(runtime);
    final navigation = ReaderV2ChapterNavigationState(
      chapterCount: runtime?.chapterCount ?? widget.initialChapters.length,
      currentIndex: chapterIndex,
      isScrubbing: menu.isScrubbing,
      scrubPercent: menu.scrubPercent,
      titleFor: _chapterTitleAt,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDarkBackground
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: isDarkBackground
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDarkBackground
            ? Brightness.light
            : Brightness.dark,
      ),
      child: ReaderV2PageShell(
        book: widget.book,
        scaffoldKey: _scaffoldKey,
        content: _buildContent(context),
        drawer: ReaderV2ChaptersDrawer(
          chapters: runtime?.chapters ?? widget.initialChapters,
          currentChapterIndex: chapterIndex,
          titleFor: _chapterTitleAt,
          listenable: runtime,
          onChapterTap: _jumpToChapterFromDrawer,
        ),
        backgroundColor: theme.backgroundColor,
        textColor: theme.textColor,
        menuBackgroundColor: menuTheme.backgroundColor,
        menuTextColor: menuTheme.textColor,
        controlsVisible: menu.controlsVisible,
        showReadTitleAddition: settings.showReadTitleAddition,
        hasVisibleContent:
            runtime != null && runtime.state.phase == ReaderV2Phase.ready,
        isLoading:
            runtime == null || runtime.state.phase != ReaderV2Phase.ready,
        chapterTitle: _chapterTitleAt(chapterIndex),
        chapterUrl: _chapterUrlAt(chapterIndex),
        originName: widget.book.originName,
        displayPageLabel: _displayChapterLabel(runtime),
        displayChapterPercentLabel: _displayChapterPercentLabel(runtime),
        progressListenable: _progress,
        navigation: navigation,
        isAutoPaging: _host.autoPage?.isRunning ?? false,
        dayNightIcon: settings.dayNightToggleIcon,
        dayNightTooltip: settings.dayNightToggleTooltip,
        onExitIntent: _handleExitIntent,
        onMore: _showMore,
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        onTts: _showTts,
        onInterface: () =>
            ReaderV2SettingsSheets.showInterfaceSettings(context, settings),
        onSettings: () => ReaderV2SettingsSheets.showAdvancedSettings(
          context,
          settings,
          onChangeSource: widget.book.isLocal ? null : _showChangeSource,
        ),
        onAutoPage: _coordinator.toggleAutoPage,
        onToggleDayNight: settings.toggleDayNightTheme,
        onReplaceRule: () => _coordinator.openReplaceRule(context),
        onShowControls: menu.showControls,
        onDismissControls: menu.dismissControls,
        onPrevChapter: () => unawaited(_coordinator.jumpRelativeChapter(-1)),
        onNextChapter: () => unawaited(_coordinator.jumpRelativeChapter(1)),
        onScrubStart: menu.onScrubStart,
        onScrubbing: (percent) {
          menu.onScrubbing(percent);
          _coordinator.previewChapterPercent(percent);
        },
        onScrubEnd: (percent) {
          menu.onScrubEnd(percent);
          unawaited(_coordinator.commitChapterPercent(percent));
        },
        showTts: true,
        showAutoPage: true,
        showReplaceRule: true,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final mediaPadding = MediaQuery.paddingOf(context);
        _lastViewportSize = size;

        final style = _host.settings.readStyleFor(
          mediaPadding,
          topInfoReservedExternally: true,
          bottomInfoReservedExternally: _host.settings.showReadTitleAddition,
        );
        final runtime = _host.ensureRuntime(size, style);
        _host.syncRuntimeConfiguration(runtime, size, style);

        final theme = _host.settings.currentTheme;
        return Stack(
          fit: StackFit.expand,
          children: [
            HybridReaderScreen(
              runtime: runtime,
              backgroundColor: theme.backgroundColor,
              textColor: theme.textColor,
              style: style,
              viewportController: _host.viewportController,
              ttsHighlight: _host.tts?.currentHighlight,
              onContentTapUp: _handleContentTap,
              progressListenable: _progress,
              bookUrl: widget.book.bookUrl,
            ),
            if (runtime.state.phase == ReaderV2Phase.error)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.all(24),
                  child: _buildReaderErrorActions(runtime),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildReaderErrorActions(ReaderV2Runtime runtime) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => unawaited(_retryReader(runtime)),
          icon: const Icon(Icons.refresh),
          label: const Text('重試'),
        ),
        if (!widget.book.isLocal)
          OutlinedButton.icon(
            onPressed: _showChangeSource,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('換源'),
          ),
        TextButton.icon(
          onPressed: _handleExitIntent,
          icon: const Icon(Icons.arrow_back),
          label: const Text('返回'),
        ),
      ],
    );
  }

  Future<void> _retryReader(ReaderV2Runtime runtime) async {
    if (runtime.chapterCount <= 0) {
      await runtime.openBook();
      return;
    }
    await runtime.reloadContentPreservingLocation();
  }

  void _handleContentTap(TapUpDetails details) {
    if (_host.menu.controlsVisible) {
      _host.menu.dismissControls();
      return;
    }
    _coordinator.handleTap(details, _lastViewportSize);
  }

  Future<bool> _jumpToChapterFromDrawer(int index) async {
    final runtime = _host.runtime;
    if (runtime == null) return false;
    await _coordinator.jumpToChapter(index);
    final succeeded =
        mounted &&
        identical(_host.runtime, runtime) &&
        runtime.state.phase == ReaderV2Phase.ready &&
        runtime.state.visibleLocation.chapterIndex == index;
    return succeeded;
  }

  void _drainRuntimeNotice() {
    final notice = _host.runtime?.takeUserNotice();
    if (!mounted || notice == null || notice.isEmpty) return;
    _showNotice(notice);
  }

  void _drainAutoPageNotice() {
    final notice = _host.autoPage?.takeUserNotice();
    if (!mounted || notice == null || notice.isEmpty) return;
    _showNotice(notice);
  }

  void _showNotice(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!mounted || messenger == null) return;
    if (_visibleNoticeMessage == message) return;
    _visibleNoticeMessage = message;
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(SnackBar(content: Text(message)));
    unawaited(
      controller.closed.then<void>((_) {
        if (_visibleNoticeMessage == message) {
          _visibleNoticeMessage = null;
        }
      }),
    );
  }

  void _handleExitIntent() {
    unawaited(
      _exitCoordinator.handleExitIntent(
        context: context,
        provider: this,
        isDrawerOpen: () => _scaffoldKey.currentState?.isDrawerOpen ?? false,
        // The reader is always opened as an app-level route from the
        // bookshelf.  A Scaffold drawer can leave a LocalHistoryEntry on the
        // reader route while its closing animation settles; popUntil applies
        // the predicate to the same route again until that local history is
        // consumed, then removes only the reader route itself.
        popNavigator: () {
          final navigator = Navigator.of(context, rootNavigator: true);
          final readerRoute = ModalRoute.of(context);
          if (readerRoute == null) {
            navigator.pop();
            return;
          }
          navigator.popUntil((route) => !identical(route, readerRoute));
        },
      ),
    );
  }

  void _showMore() {
    AppBottomSheet.show(
      context: context,
      title: '更多操作',
      icon: Icons.more_horiz_rounded,
      children: [
        ListTile(
          leading: const Icon(Icons.settings_suggest_rounded),
          title: const Text('全域系統設定'),
          subtitle: const Text('備份、還原與解析引擎配置'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          },
        ),
      ],
    );
  }

  void _showTts() {
    final tts = _host.tts;
    if (tts == null) return;
    ReaderV2TtsSheet.show(context, tts: tts);
  }

  Future<void> _showChangeSource() async {
    if (widget.book.isLocal) return;
    PreparedSourceSwitch? preparedSwitch;
    await AppBottomSheet.showCustom<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ChangeSourceSheet(
        book: widget.book,
        onSelectSource: (candidate) => _handleChangeSourceSelected(
          candidate,
          onSuccess: (prepared) => preparedSwitch = prepared,
        ),
      ),
    );

    final prepared = preparedSwitch;
    if (!mounted || prepared == null) return;
    _pushReplacementForPreparedSwitch(prepared);
  }

  Future<ChangeSourceOutcome> _handleChangeSourceSelected(
    SearchBook candidate, {
    void Function(PreparedSourceSwitch prepared)? onSuccess,
  }) async {
    try {
      // The flush returns the exact snapshot that was captured and persisted.
      // Use that snapshot for source alignment; reading runtime state after
      // the await would allow a scroll/TTS update during the DAO write to
      // disagree with the progress that is authoritative for this switch.
      final flushedLocation = await _host.flushProgress();
      final runtime = _host.runtime;
      final currentLocation = flushedLocation ?? runtime?.state.visibleLocation;
      final currentIndex =
          currentLocation?.chapterIndex ?? _currentChapterIndex(runtime);
      final currentTitle = _chapterTitleAt(currentIndex);
      final switchingBook = widget.book.copyWith(
        chapterIndex: currentIndex,
        durChapterTitle: currentTitle.isEmpty
            ? widget.book.durChapterTitle
            : currentTitle,
        charOffset: currentLocation?.charOffset ?? widget.book.charOffset,
        visualOffsetPx:
            currentLocation?.visualOffsetPx ?? widget.book.visualOffsetPx,
      );
      final prepared = await _sourceSwitchService.prepareSwitch(
        switchingBook,
        candidate,
        targetChapterIndex: currentIndex,
        targetChapterTitle: currentTitle.isEmpty ? null : currentTitle,
      );
      await _sourceSwitchService.commitSwitch(
        widget.book,
        prepared,
        bookDao: _host.dependencies.bookDao,
        chapterDao: _host.dependencies.chapterDao,
      );
      AppEventBus().fire(AppEventBus.upBookshelf);
      onSuccess?.call(prepared);
      return (
        success: true,
        message: '已切換到 ${prepared.source.bookSourceName}',
      );
    } catch (e) {
      return (success: false, message: '換源失敗: $e');
    }
  }

  void _pushReplacementForPreparedSwitch(PreparedSourceSwitch prepared) {
    Navigator.of(context).pushReplacement(
      BookOpenRoute(
        book: prepared.migratedBook,
        openTarget: ReaderV2OpenTarget.resume(prepared.migratedBook),
        initialChapters: prepared.chapters,
      ),
    );
  }

  @override
  Book get book => widget.book;

  @override
  bool shouldPromptAddToBookshelfOnExit() {
    return !widget.book.isInBookshelf && _host.settings.showAddToShelfAlert;
  }

  @override
  Future<void> persistExitProgress() async {
    await _host.flushProgress();
  }

  @override
  Future<void> addCurrentBookToBookshelf() async {
    final runtime = _host.runtime;
    final location =
        runtime?.state.visibleLocation ??
        ReaderV2Location(
          chapterIndex: widget.book.chapterIndex,
          charOffset: widget.book.charOffset,
          visualOffsetPx: widget.book.visualOffsetPx,
        );
    final chapters = runtime?.chapters ?? widget.initialChapters;
    await _sessionFacade.addCurrentBookToBookshelf(
      book: widget.book,
      chapters: chapters,
      location: location,
      chapterTitle: _chapterTitleAt(location.chapterIndex),
      bookDao: _host.dependencies.bookDao,
      chapterDao: _host.dependencies.chapterDao,
    );
    if (mounted) setState(() {});
  }

  @override
  Future<void> discardUnkeptBookStorage() {
    return _host.bookStorageService.discardBook(widget.book);
  }

  int _currentChapterIndex(ReaderV2Runtime? runtime) {
    final count = runtime?.chapterCount ?? widget.initialChapters.length;
    if (runtime == null || count <= 0) return 0;
    return runtime.state.visibleLocation.chapterIndex
        .clamp(0, count - 1)
        .toInt();
  }

  String _chapterTitleAt(int index) {
    final runtime = _host.runtime;
    if (runtime != null) return runtime.titleFor(index);
    if (index < 0 || index >= widget.initialChapters.length) return '';
    return widget.initialChapters[index].title;
  }

  String _chapterUrlAt(int index) {
    final runtime = _host.runtime;
    if (runtime != null) return runtime.chapterUrlAt(index);
    if (index < 0 || index >= widget.initialChapters.length) return '';
    return widget.initialChapters[index].url;
  }

  String _displayChapterLabel(ReaderV2Runtime? runtime) {
    final snapshot = _progress.value;
    if (snapshot != null) return snapshot.chapterLabel;
    if (runtime == null || runtime.chapterCount <= 0) {
      return '第 ... 章 · 本章 ...';
    }
    return '第 ${_currentChapterIndex(runtime) + 1}/${runtime.chapterCount} 章 · 本章 ...';
  }

  String _displayChapterPercentLabel(ReaderV2Runtime? runtime) {
    return _progress.value?.percentLabel ?? '全書 ...%';
  }
}
