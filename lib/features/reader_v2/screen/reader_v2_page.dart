import 'dart:async';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/navigation/status_bar.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/use_cases/reader_v2_page_coordinator.dart';
import 'package:night_reader/features/reader_v2/use_cases/coordinators/reader_v2_page_exit_coordinator.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_session_facade.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness_bar.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sheet.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sheets.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_device_channel.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_window_settings.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/theme_reveal_scope.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:provider/provider.dart';

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
    with WidgetsBindingObserver
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
  StreamSubscription<String>? _settingsSaveFailures;

  /// 鏡頭挖孔與曲面邊緣佔掉的上緣高度；隱藏狀態列時頁首只依它決定。
  double? _topCutoutExtent;

  @override
  void initState() {
    super.initState();
    _sourceSwitchService = SourceSwitchService(
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
    _settingsSaveFailures = _host.settings.saveFailures.listen(_showNotice);
    HardwareKeyboard.instance.addHandler(_handleVolumeKey);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshTopCutoutExtent());
  }

  @override
  void didChangeMetrics() {
    // 旋轉或折疊會改變挖孔位置；狀態列顯示與否不影響查到的值。
    unawaited(_refreshTopCutoutExtent());
  }

  Future<void> _refreshTopCutoutExtent() async {
    final extent = await ReaderV2DeviceChannel.topCutoutExtent();
    // 取不到時保留上一次的值，避免頁首在暫態中跳回系統內距。
    if (!mounted || extent == null || extent == _topCutoutExtent) return;
    setState(() => _topCutoutExtent = extent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleVolumeKey);
    unawaited(_settingsSaveFailures?.cancel());
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

  /// 音量鍵翻頁。回傳 true 時這一下不會再交給系統調音量；選單開著、
  /// 正在朗讀、上面蓋著別的頁面或面板，或設定關閉時照常調音量。
  bool _handleVolumeKey(KeyEvent event) {
    final forward = switch (event.logicalKey) {
      LogicalKeyboardKey.audioVolumeDown => true,
      LogicalKeyboardKey.audioVolumeUp => false,
      _ => null,
    };
    if (forward == null) return false;
    if (!mounted ||
        !_host.settings.volumeKeyPage ||
        _host.menu.controlsVisible ||
        (_host.tts?.isPlaying ?? false) ||
        !(ModalRoute.of(context)?.isCurrent ?? false) ||
        (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
      return false;
    }
    // 按住不放的重複事件也翻頁；放開不做事，但一樣攔下，系統才不會調音量。
    if (event is! KeyUpEvent) {
      unawaited(_coordinator.movePage(forward: forward));
    }
    return true;
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
    final palette = StylePalette.of(context);
    final isDarkBackground = palette.brightness == Brightness.dark;
    final chapterIndex = _currentChapterIndex(runtime);
    final navigation = ReaderV2ChapterNavigationState(
      chapterCount: runtime?.chapterCount ?? widget.initialChapters.length,
      currentIndex: chapterIndex,
      isScrubbing: menu.isScrubbing,
      scrubPercent: menu.scrubPercent,
      titleFor: _chapterTitleAt,
    );

    final customBrightness =
        !settings.brightnessAuto &&
        ReaderV2DeviceChannel.supportsWindowBrightness;
    return StatusBarHidden(
      hidden: settings.hideStatusBar,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
        child: ReaderV2WindowSettings(
          backlight: customBrightness
              ? ReaderV2Brightness.backlightFor(settings.brightness)
              : null,
          child: _DimOverlay(
            dim: customBrightness
                ? ReaderV2Brightness.dimFor(settings.brightness)
                : 0,
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
              backgroundColor: palette.readerBackground,
              infoColor: palette.readerInfo,
              textColor: palette.readerText,
              controlsVisible: menu.controlsVisible,
              showReadTitleAddition: settings.showReadTitleAddition,
              infoState: _infoStateOf(runtime),
              chapterTitle: _chapterTitleAt(chapterIndex),
              chapterUrl: _chapterUrlAt(chapterIndex),
              originName: widget.book.originName,
              progressListenable: _progress,
              navigation: navigation,
              isAutoPaging: _host.autoPage?.isRunning ?? false,
              hideStatusBar: settings.hideStatusBar,
              headerInfo: settings.headerInfo,
              footerInfo: settings.footerInfo,
              paddingTop: settings.paddingTop,
              paddingBottom: settings.paddingBottom,
              footerOffset: settings.footerOffset,
              topCutoutExtent: _topCutoutExtent,
              dayNightIcon: isDarkBackground
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              dayNightTooltip: isDarkBackground ? '切換淺色模式' : '切換深色模式',
              onExitIntent: _handleExitIntent,
              onSystemBack: _handleSystemBack,
              onMore: () => unawaited(_showMore()),
              onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
              onTts: _showTts,
              onTimedTts: () => unawaited(_host.tts?.toggleTimed()),
              onInterface: () => ReaderV2SettingsSheets.showInterfaceSettings(
                context,
                settings,
              ),
              onSettings: () => ReaderV2SettingsSheets.showAdvancedSettings(
                context,
                settings,
              ),
              onAutoPage: _coordinator.toggleAutoPage,
              // 深淺是整個 App 共用的設定，閱讀器切換後其他畫面一併跟著換。
              onToggleDayNight: () => ThemeRevealScope.of(context).run(
                change: () => context.read<SettingsProvider>().setThemeMode(
                  isDarkBackground ? ThemeMode.light : ThemeMode.dark,
                ),
              ),
              onReplaceRule: () => _coordinator.openReplaceRule(context),
              onShowControls: menu.showControls,
              onDismissControls: menu.dismissControls,
              onPrevChapter: () =>
                  unawaited(_coordinator.jumpRelativeChapter(-1)),
              onNextChapter: () =>
                  unawaited(_coordinator.jumpRelativeChapter(1)),
              onScrubStart: menu.onScrubStart,
              onScrubbing: (percent) {
                menu.onScrubbing(percent);
                _coordinator.previewChapterPercent(percent);
              },
              onScrubEnd: (percent) {
                menu.onScrubEnd(percent);
                unawaited(_coordinator.commitChapterPercent(percent));
              },
              brightnessControl: ReaderV2DeviceChannel.supportsWindowBrightness
                  ? ReaderV2BrightnessBar(
                      auto: settings.brightnessAuto,
                      level: settings.brightness,
                      onAutoChanged: settings.setBrightnessAuto,
                      onChanged: (level) =>
                          settings.setBrightness(level, persist: false),
                      onChangeEnd: settings.setBrightness,
                    )
                  : null,
              sleepTimer: _host.tts?.sleepTimer,
              isTtsPlaying: _host.tts?.isPlaying ?? false,
              showTts: true,
              showAutoPage: true,
              showReplaceRule: true,
            ),
          ),
        ),
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

        final palette = StylePalette.of(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            HybridReaderScreen(
              runtime: runtime,
              backgroundColor: palette.readerBackground,
              textColor: palette.readerText,
              style: style,
              viewportController: _host.viewportController,
              ttsHighlight: _host.tts?.currentHighlight,
              textSelectionEnabled:
                  !_host.menu.controlsVisible &&
                  !(_host.autoPage?.isRunning ?? false) &&
                  !(_host.tts?.isPlaying ?? false),
              highlightColor: _host.settings.highlightColor.resolve(palette),
              highlightStrength: _host.settings.highlightStrength,
              // 選單開著時，點正文只收起選單（由選單的收起層處理）。
              onContentTapUp: _host.menu.controlsVisible
                  ? null
                  : _handleContentTap,
              progressListenable: _progress,
              bookUrl: widget.book.bookUrl,
            ),
            if (runtime.state.lifecycle == ReaderV2Lifecycle.unavailable)
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
    _coordinator.handleTap(details, _lastViewportSize);
  }

  /// 系統返回先收掉正在操作的東西（目錄由頁面框架先處理），都沒有才
  /// 離開閱讀器。
  void _handleSystemBack() {
    if (_host.viewportController.dismissSelection?.call() ?? false) return;
    if (_host.menu.controlsVisible) {
      _host.menu.dismissControls();
      return;
    }
    _handleExitIntent();
  }

  Future<bool> _jumpToChapterFromDrawer(int index) async {
    final runtime = _host.runtime;
    if (runtime == null) return false;
    await _coordinator.jumpToChapter(index);
    final succeeded =
        mounted &&
        identical(_host.runtime, runtime) &&
        runtime.state.hasStableWorld &&
        runtime.state.visibleLocation.chapterIndex == index;
    return succeeded;
  }

  void _drainRuntimeNotice() {
    final notice = _host.runtime?.takeUserNotice();
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

  Future<void> _showMore() async {
    final isLocal = widget.book.isLocal;
    final action = await showAppActionSheet<_ReaderMoreAction>(
      context: context,
      actions: [
        if (!isLocal) ...const [
          AppSheetAction(
            label: '換源',
            icon: Icons.swap_horiz_rounded,
            value: _ReaderMoreAction.changeSource,
          ),
          AppSheetAction(
            label: '重新取得本章',
            icon: Icons.refresh_rounded,
            value: _ReaderMoreAction.refetchChapter,
          ),
        ],
        const AppSheetAction(
          label: '書籍詳情',
          icon: Icons.info_outline_rounded,
          value: _ReaderMoreAction.bookDetail,
        ),
        const AppSheetAction(
          label: '全域系統設定',
          icon: Icons.settings_suggest_rounded,
          value: _ReaderMoreAction.globalSettings,
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _ReaderMoreAction.changeSource:
        _host.menu.dismissControls();
        await _showChangeSource();
      case _ReaderMoreAction.refetchChapter:
        _host.menu.dismissControls();
        await _refetchCurrentChapter();
      case _ReaderMoreAction.bookDetail:
        await _showBookDetail();
      case _ReaderMoreAction.globalSettings:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
        // 「閱讀偏好」頁以自己的 controller 寫入同一組偏好設定；
        // 回到閱讀器時重新載入，正文才會反映在那裡做的調整。
        if (mounted) unawaited(_host.settings.loadSettings());
    }
  }

  /// 書源回了擋爬蟲頁或不完整的正文時，向書源重抓這一章、停在原位；
  /// 抓不到時保留原本的正文並顯示原因。
  Future<void> _refetchCurrentChapter() async {
    final runtime = _host.runtime;
    if (runtime == null || !runtime.state.hasStableWorld) return;
    _showNotice('正在重新取得本章…');
    final succeeded = await runtime.reloadContentPreservingLocation(
      refetch: true,
    );
    if (mounted && succeeded) _showNotice('已重新取得本章');
  }

  /// 從閱讀器開的詳情：點章節回來跳到那一章（見 [resolveDetailChapter]），
  /// 按閱讀鈕直接回來。
  Future<void> _showBookDetail() async {
    final flushed = await _host.flushProgress();
    if (!mounted) return;
    final chapterDao = _host.dependencies.chapterDao;
    final index = flushed?.chapterIndex ?? _currentChapterIndex(_host.runtime);
    final storedIndex = await chapterDao.indexOfUrl(
      widget.book.bookUrl,
      _chapterUrlAt(index),
    );
    if (!mounted) return;
    final book = widget.book.copyWith(
      chapterIndex: storedIndex ?? index,
      durChapterTitle: _rawChapterTitleAt(index),
    );
    final targetUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BookDetailPage(book: book, fromReader: true),
      ),
    );
    if (!mounted || targetUrl == null) return;
    _host.menu.dismissControls();
    final target = await resolveDetailChapter(
      url: targetUrl,
      readerChapters: _host.runtime?.chapters ?? widget.initialChapters,
      loadLatest: () async {
        await _host.flushProgress();
        return chapterDao.getByBook(widget.book.bookUrl);
      },
    );
    if (!mounted || target == null) return;
    final latest = target.latest;
    if (latest == null) {
      await _coordinator.jumpToChapter(target.index);
      return;
    }
    unawaited(
      Navigator.of(context).pushReplacement(
        BookOpenRoute(
          book: widget.book,
          openTarget: ReaderV2OpenTarget.chapterStart(target.index),
          initialChapters: latest,
        ),
      ),
    );
  }

  void _showTts() {
    final tts = _host.tts;
    if (tts == null) return;
    ReaderV2MenuSheet.show<void>(
      context,
      settings: _host.settings,
      builder: (_) => ReaderV2TtsPanel(tts: tts, settings: _host.settings),
    );
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
      return (success: true, message: '已切換到 ${prepared.source.bookSourceName}');
    } catch (error) {
      if (!isSourceSwitchUnavailable(error)) rethrow;
      return (success: false, message: failureMessage('換源', error));
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
    // 加入書架的書整本下載（ADR 0008）。
    unawaited(DownloadService().keepShelfBookDownloaded(widget.book.bookUrl));
    if (mounted) setState(() {});
  }

  @override
  Future<void> discardUnkeptBookStorage() {
    return _host.bookStorageService.discardBook(widget.book);
  }

  /// 頁首頁尾資訊列跟著正文：開書、跳到別章、改排版與重載內容時畫骨架，
  /// 開書取不到正文時不畫。同一章內的跳轉（例如拖進度條預覽）資訊列留在
  /// 原處。
  ReaderV2InfoState _infoStateOf(ReaderV2Runtime? runtime) {
    if (runtime == null) return ReaderV2InfoState.loading;
    if (runtime.state.lifecycle == ReaderV2Lifecycle.unavailable) {
      return ReaderV2InfoState.hidden;
    }
    if (!runtime.state.hasStableWorld ||
        runtime.isJumpingToAnotherChapter ||
        runtime.isRebuildingText) {
      return ReaderV2InfoState.loading;
    }
    return ReaderV2InfoState.ready;
  }

  int _currentChapterIndex(ReaderV2Runtime? runtime) {
    final count = runtime?.chapterCount ?? widget.initialChapters.length;
    if (runtime == null || count <= 0) return 0;
    return runtime.state.visibleLocation.chapterIndex
        .clamp(0, count - 1)
        .toInt();
  }

  /// 目錄、選單與資訊列顯示用的章節標題，套用閱讀設定的繁簡轉換。
  String _chapterTitleAt(int index) {
    return ChineseDisplay.convert(
      _rawChapterTitleAt(index),
      convertType: _host.settings.chineseConvert,
    );
  }

  String _rawChapterTitleAt(int index) {
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
}

/// 從閱讀器開的詳情點了章節 [url]，閱讀器要開哪一章。
///
/// 閱讀器整段閱讀都用開書時的目錄 [readerChapters]；詳情頁讀的是資料庫裡
/// 的目錄，可能已經被書架檢查或詳情的「檢查更新」換過，序號對不上，所以
/// 兩邊用章節網址對應：閱讀器的目錄裡有這一章就原地跳（`latest` 為 null）；
/// 沒有（新章節）就到 [loadLatest] 讀到的最新目錄裡找，找到就用最新目錄
/// 重開；都沒有回傳 null。
@visibleForTesting
Future<({int index, List<BookChapter>? latest})?> resolveDetailChapter({
  required String url,
  required List<BookChapter> readerChapters,
  required Future<List<BookChapter>> Function() loadLatest,
}) async {
  final index = readerChapters.indexWhere((c) => c.url == url);
  if (index >= 0) return (index: index, latest: null);
  final latest = await loadLatest();
  final latestIndex = latest.indexWhere((c) => c.url == url);
  if (latestIndex < 0) return null;
  return (index: latestIndex, latest: latest);
}

enum _ReaderMoreAction {
  changeSource,
  refetchChapter,
  bookDetail,
  globalSettings,
}

/// 亮度拉進加暗段時疊在整個閱讀畫面（含選單）上的黑色；不攔點擊。
class _DimOverlay extends StatelessWidget {
  const _DimOverlay({required this.dim, required this.child});

  final double dim;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (dim <= 0) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
        ),
      ],
    );
  }
}
