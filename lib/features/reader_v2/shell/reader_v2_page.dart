import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/application/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/application/reader_v2_page_coordinator.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:night_reader/features/reader_v2/application/coordinators/reader_v2_display_coordinator.dart';
import 'package:night_reader/features/reader_v2/application/coordinators/reader_v2_page_exit_coordinator.dart';
import 'package:night_reader/features/reader_v2/application/session/reader_v2_session_facade.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sheet.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/shell/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sheets.dart';
import 'package:night_reader/features/reader_v2/shell/reader_v2_page_shell.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/runtime/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_screen.dart';

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
  static const ReaderV2DisplayCoordinator _displayCoordinator =
      ReaderV2DisplayCoordinator();
  static const ReaderV2SessionFacade _sessionFacade = ReaderV2SessionFacade();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ReaderV2PageExitCoordinator _exitCoordinator =
      ReaderV2PageExitCoordinator();

  late final ReaderV2ControllerHost _host;
  late final ReaderV2PageCoordinator _coordinator;
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
    final page = _currentPage(runtime);
    final chapterIndex = _currentChapterIndex(runtime);
    final navigation = ReaderV2ChapterNavigationState(
      chapterCount: runtime?.chapterCount ?? widget.initialChapters.length,
      currentIndex: chapterIndex,
      isScrubbing: menu.isScrubbing,
      scrubIndex: menu.scrubIndex,
      pendingIndex: menu.pendingChapterNavigationIndex,
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
        hasVisibleContent: page != null,
        isLoading:
            runtime == null || runtime.state.phase != ReaderV2Phase.ready,
        chapterTitle: _chapterTitleAt(chapterIndex),
        chapterUrl: _chapterUrlAt(chapterIndex),
        originName: widget.book.originName,
        displayPageLabel: _displayPageLabel(runtime, page),
        displayChapterPercentLabel: _displayChapterPercentLabel(runtime, page),
        navigation: navigation,
        isAutoPaging: _host.autoPage?.isRunning ?? false,
        autoPageSpeed: settings.autoPageSpeed,
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
            () =>
                ReaderV2SettingsSheets.showAdvancedSettings(context, settings),
        onAutoPage: _coordinator.toggleAutoPage,
        onAutoPageSpeedChanged: settings.setAutoPageSpeed,
        onToggleDayNight: settings.toggleDayNightTheme,
        onReplaceRule: () => _coordinator.openReplaceRule(context),
        onShowControls: menu.showControls,
        onDismissControls: menu.dismissControls,
        onPrevChapter: () => unawaited(_coordinator.jumpRelativeChapter(-1)),
        onNextChapter: () => unawaited(_coordinator.jumpRelativeChapter(1)),
        onScrubStart: () => menu.onScrubStart(chapterIndex),
        onScrubbing: menu.onScrubbing,
        onScrubEnd: (index) {
          menu.onScrubEnd(index);
          unawaited(_coordinator.jumpToChapter(index));
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
        return EngineReaderV2Screen(
          runtime: runtime,
          backgroundColor: theme.backgroundColor,
          textColor: theme.textColor,
          style: style,
          viewportController: _host.viewportController,
          ttsHighlight: _host.tts?.currentHighlight,
          onContentTapUp: _handleContentTap,
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

  ReaderV2RenderPage? _currentPage(ReaderV2Runtime? runtime) {
    if (runtime == null) return null;
    return runtime.state.pageWindow?.current ?? runtime.state.currentSlidePage;
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

  String _displayPageLabel(ReaderV2Runtime? runtime, ReaderV2RenderPage? page) {
    if (runtime == null) return '0/0';
    if (runtime.state.mode == ReaderV2Mode.scroll) {
      final visiblePage = _visiblePageForScroll(runtime);
      if (visiblePage != null && visiblePage.pageSize > 0) {
        return _displayCoordinator.formatPageLabel(
          visiblePage.pageIndex,
          visiblePage.pageSize,
        );
      }
      return '0/0';
    }
    if (page == null || page.pageSize <= 0) return '0/0';
    return _displayCoordinator.formatPageLabel(page.pageIndex, page.pageSize);
  }

  String _displayChapterPercentLabel(
    ReaderV2Runtime? runtime,
    ReaderV2RenderPage? page,
  ) {
    if (runtime == null) return '0.0%';
    if (runtime.state.mode == ReaderV2Mode.scroll) {
      return _visiblePageForScroll(runtime)?.readProgress ?? '0.0%';
    }
    if (page == null) return '0.0%';
    return page.readProgress;
  }

  ReaderV2RenderPage? _visiblePageForScroll(ReaderV2Runtime runtime) {
    final location = runtime.state.visibleLocation.normalized(
      chapterCount: runtime.chapterCount,
    );
    final layout = runtime.debugResolver.cachedLayout(location.chapterIndex);
    if (layout == null || layout.pages.isEmpty) return null;
    return layout.pageForCharOffset(location.charOffset);
  }
}
