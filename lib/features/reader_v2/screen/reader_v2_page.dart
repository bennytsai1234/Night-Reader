import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
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
  });

  final Book book;
  final ReaderV2OpenTarget? openTarget;
  final List<BookChapter> initialChapters;

  @override
  State<ReaderV2Page> createState() => _ReaderV2PageState();
}

class _ReaderV2PageState extends State<ReaderV2Page>
    implements ReaderV2ExitFlowDelegate {
  static const ReaderV2SessionFacade _sessionFacade = ReaderV2SessionFacade();

  final SourceSwitchService _sourceSwitchService = SourceSwitchService();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ReaderV2PageExitCoordinator _exitCoordinator =
      ReaderV2PageExitCoordinator();

  late final ReaderV2ControllerHost _host;
  late final ReaderV2PageCoordinator _coordinator;

  /// D6：hybrid 引擎回報的「章序 + 章內百分比」，取代舊分頁模型頁碼。
  final ValueNotifier<HybridProgressSnapshot?> _progress =
      ValueNotifier<HybridProgressSnapshot?>(null);
  Size? _lastViewportSize;
  bool _rebuildQueued = false;

  @override
  void initState() {
    super.initState();
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
    // A pure tap may be the only event; do not wait for a drag animation to
    // provide the next frame that drains the post-frame rebuild.
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
        statusBarIconBrightness:
            isDarkBackground ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            isDarkBackground ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDarkBackground ? Brightness.light : Brightness.dark,
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
          onChapterTap: _coordinator.jumpToChapter,
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
        onInterface:
            () =>
                ReaderV2SettingsSheets.showInterfaceSettings(context, settings),
        onSettings:
            () => ReaderV2SettingsSheets.showAdvancedSettings(
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
        return HybridReaderScreen(
          runtime: runtime,
          backgroundColor: theme.backgroundColor,
          textColor: theme.textColor,
          style: style,
          viewportController: _host.viewportController,
          ttsHighlight: _host.tts?.currentHighlight,
          onContentTapUp: _handleContentTap,
          progressListenable: _progress,
          bookUrl: widget.book.bookUrl,
        );
      },
    );
  }

  void _handleContentTap(TapUpDetails details) {
    if (_host.menu.controlsVisible) {
      _host.menu.dismissControls();
      return;
    }
    _coordinator.handleTap(details, _lastViewportSize);
  }

  void _drainRuntimeNotice() {
    final notice = _host.runtime?.takeUserNotice();
    if (!mounted || notice == null || notice.isEmpty) return;
    _showNotice(notice);
  }

  void _showNotice(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!mounted || messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _handleExitIntent() {
    unawaited(
      _exitCoordinator.handleExitIntent(
        context: context,
        provider: this,
        isDrawerOpen: () => _scaffoldKey.currentState?.isDrawerOpen ?? false,
        popNavigator: () => Navigator.of(context).pop(),
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

  void _showChangeSource() {
    if (widget.book.isLocal) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => ChangeSourceSheet(
            book: widget.book,
            onSelectSource: _handleChangeSourceSelected,
          ),
    );
  }

  /// 閱讀器情境的換源回呼。
  ///
  /// 成功:對齊目前章節 → 持久化 → flush 進度 → pushReplacement 以新書重開整頁。
  /// 失敗:回傳失敗訊息,**不 pop、不動 runtime**,完整停留在原源。
  Future<ChangeSourceOutcome> _handleChangeSourceSelected(
    SearchBook candidate,
  ) async {
    final runtime = _host.runtime;
    final currentIndex = _currentChapterIndex(runtime);
    final currentTitle = _chapterTitleAt(currentIndex);
    try {
      final resolution = await _sourceSwitchService.resolveSwitch(
        widget.book,
        candidate,
        targetChapterIndex: currentIndex,
        targetChapterTitle: currentTitle.isEmpty ? null : currentTitle,
        validateTargetContent: true,
      );
      await _sourceSwitchService.persistSwitch(
        widget.book,
        resolution,
        bookDao: _host.dependencies.bookDao,
        chapterDao: _host.dependencies.chapterDao,
      );
      // 持久化成功後再 flush 舊源進度,避免換源失敗時污染原書狀態。
      await _host.flushProgress();
      AppEventBus().fire(AppEventBus.upBookshelf);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          BookOpenRoute(
            book: resolution.migratedBook,
            openTarget: ReaderV2OpenTarget.resume(resolution.migratedBook),
            initialChapters: resolution.chapters,
          ),
        );
      }
      return (
        success: true,
        message: '已切換到 ${resolution.source.bookSourceName}',
      );
    } catch (e) {
      return (success: false, message: '換源失敗: $e');
    }
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

  /// D6：廢除頁碼，狀態列顯示「章序」。
  String _displayChapterLabel(ReaderV2Runtime? runtime) {
    final snapshot = _progress.value;
    if (snapshot != null) return snapshot.chapterLabel;
    if (runtime == null || runtime.chapterCount <= 0) return '...';
    return '第 ${_currentChapterIndex(runtime) + 1}/${runtime.chapterCount} 章';
  }

  /// D6：章內百分比（未達書尾封頂 99.9%，由 HybridProgress 保證）。
  String _displayChapterPercentLabel(ReaderV2Runtime? runtime) {
    return _progress.value?.percentLabel ?? '...%';
  }
}
