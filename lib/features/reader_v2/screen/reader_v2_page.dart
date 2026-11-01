import 'dart:async';

import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_cover_storage_service.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/navigation/status_bar.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/use_cases/reader_v2_page_coordinator.dart';
import 'package:night_reader/features/reader_v2/use_cases/coordinators/reader_v2_page_exit_coordinator.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_session_facade.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness_bar.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_departure.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sheet.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_volume_keys.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sheets.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_device_channel.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_window_settings.dart';
import 'package:night_reader/features/source_login/source_browser_page.dart';
import 'package:night_reader/features/source_login/source_login_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/theme_reveal_scope.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_sync.dart';
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin
    implements ReaderV2ExitFlowDelegate {
  static const ReaderV2SessionFacade _sessionFacade = ReaderV2SessionFacade();

  late final SourceSwitchService _sourceSwitchService;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ReaderV2PageExitCoordinator _exitCoordinator =
      ReaderV2PageExitCoordinator();

  late final ReaderV2ControllerHost _host;
  late final ReaderV2PageCoordinator _coordinator;
  late final ReaderV2ProgressSync _progressSync;

  final ValueNotifier<HybridProgressSnapshot?> _progress =
      ValueNotifier<HybridProgressSnapshot?>(null);
  Size? _lastViewportSize;
  String? _visibleNoticeMessage;
  bool _rebuildQueued = false;
  StreamSubscription<String>? _settingsSaveFailures;

  /// 鏡頭挖孔與曲面邊緣佔掉的上緣高度；隱藏狀態列時頁首只依它決定。
  double? _topCutoutExtent;

  /// 開書的換頁動畫與骨架淡入都播完時完成；載入等它（ADR 0018）。
  final Completer<void> _entrance = Completer<void>();

  /// 從目錄跳章時，等目錄收起的那一下；收到底、目錄從畫面上拿掉時完成。
  Completer<void>? _drawerClosed;

  /// 目錄開著時音量鍵照常調音量。
  final ValueNotifier<bool> _drawerOpen = ValueNotifier(false);
  bool _entranceWatched = false;

  /// 從選單推一整頁時，等選單滑出畫面（見 [_pushOverMenu]）。
  late final ReaderV2MenuDeparture _menuDeparture = ReaderV2MenuDeparture(
    _host.menu,
  );

  /// 只拿來計骨架淡入的時長（頁首頁尾骨架與照紀錄畫的正文骨架都是
  /// [AppMotion.fade]）：開書時和這一頁的第一幀同時開始，從目錄跳章時和
  /// 蓋紙同時開始。
  late final AnimationController _skeletonFadeIn = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
  );

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
      entrance: _entrance.future,
      onChanged: _handleControllerChanged,
      isMounted: () => mounted,
    );
    _coordinator = ReaderV2PageCoordinator(
      host: _host,
      showNotice: _showNotice,
    );
    _settingsSaveFailures = _host.settings.saveFailures.listen(_showNotice);
    _progressSync = ReaderV2ProgressSync(
      book: widget.book,
      runtime: () => _host.runtime,
      onJumped: _showSyncHint,
    )..start();
    unawaited(_host.opened.then((_) => _progressSync.bookOpened()));
    _host.menu.controlsVisible.addListener(_dismissSyncHintOnMenu);
    _progress.addListener(_dismissSyncHintIfMoved);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshTopCutoutExtent());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceWatched) return;
    _entranceWatched = true;
    unawaited(_awaitEntrance());
  }

  /// 開書的換頁動畫與骨架淡入都播完才放行載入：載入在主執行緒上的工作
  /// 不和這兩段動畫搶同一幀。系統關閉動畫時骨架直接到位，只等換頁。
  Future<void> _awaitEntrance() async {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion) unawaited(_skeletonFadeIn.forward());
    await Future.wait([
      TransitionSettled.entered(context),
      if (!reduceMotion)
        TransitionSettled.until(_skeletonFadeIn, (s) => s.isCompleted),
    ]);
    if (mounted && !_entrance.isCompleted) _entrance.complete();
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
    _drawerOpen.dispose();
    unawaited(_settingsSaveFailures?.cancel());
    _menuDeparture.dispose();
    _coordinator.dispose();
    _progress.dispose();
    _host.menu.controlsVisible.removeListener(_dismissSyncHintOnMenu);
    // 在 runtime 釋放前：存好最後的位置再上傳。
    _progressSync.dispose();
    _host.dispose();
    _skeletonFadeIn.dispose();
    super.dispose();
  }

  /// 跳到另一台的進度後，提示顯示期間停在的位置；一翻頁、捲動就收起提示。
  ReaderV2Location? _syncHintAt;

  static const String _syncHintMessage = '已接上另一台的進度';

  void _showSyncHint(ReaderV2Location previous) {
    final runtime = _host.runtime;
    if (!mounted || runtime == null) return;
    _syncHintAt = runtime.state.visibleLocation;
    _showNotice(
      _syncHintMessage,
      action: (
        label: '回到原處',
        onPressed: () => unawaited(runtime.jumpToLocation(previous)),
      ),
      duration: const Duration(seconds: 3),
    );
  }

  void _dismissSyncHint() {
    _syncHintAt = null;
    if (_visibleNoticeMessage != _syncHintMessage) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }

  void _dismissSyncHintOnMenu() {
    if (_syncHintAt != null && _host.menu.controlsVisible.value) {
      _dismissSyncHint();
    }
  }

  /// 同一章裡捲動、翻頁不通知整頁，只發布頁尾的進度（[_progress]）；發布
  /// 之前正文已經把讀到的位置交給 runtime，這時比得出動了沒有。
  void _dismissSyncHintIfMoved() {
    final hintAt = _syncHintAt;
    if (hintAt != null && _host.runtime?.state.visibleLocation != hintAt) {
      _dismissSyncHint();
    }
  }

  void _handleControllerChanged() {
    _dismissSyncHintIfMoved();
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
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _host.settings;
    final menu = _host.menu;
    final runtime = _host.runtime;
    final palette = StylePalette.of(context);
    final isDarkBackground = palette.brightness == Brightness.dark;
    final navigation = ReaderV2ChapterNavigationState(
      chapterCount: runtime?.chapterCount ?? widget.initialChapters.length,
      // 換章不通知閱讀頁：用到目前章的小元件各自聽它。
      current: runtime?.visibleChapterIndex ?? _NoChapterYet(_openChapterIndex),
      scrub: menu.scrub,
      titleFor: _chapterTitleAt,
    );

    final customBrightness =
        !settings.brightnessAuto &&
        ReaderV2DeviceChannel.supportsWindowBrightness;
    return StatusBarHidden(
      hidden: settings.hideStatusBar,
      hideNavigationBar: settings.hideNavigationBar,
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
          keepScreenOn: settings.keepScreenOn,
          backlight: customBrightness
              ? ReaderV2Brightness.backlightFor(settings.brightness)
              : null,
          orientation: settings.orientation,
          child: ReaderV2VolumeKeys(
            enabled: settings.volumeKeyPage && !(_host.tts?.isPlaying ?? false),
            blockers: [menu.controlsVisible, _drawerOpen],
            onKey: (volumeDown) => unawaited(
              _coordinator.movePage(
                forward: volumeDown != settings.volumeKeyReversed,
              ),
            ),
            child: _DimOverlay(
              dim: customBrightness
                  ? ReaderV2Brightness.dimFor(
                      settings.brightness,
                      maxDim: settings.maxDim,
                    )
                  : 0,
              child: ReaderV2PageShell(
                book: widget.book,
                scaffoldKey: _scaffoldKey,
                content: _buildContent(context),
                drawer: ReaderV2ChaptersDrawer(
                  chapters: runtime?.chapters ?? widget.initialChapters,
                  currentChapter: navigation.current,
                  titleFor: _chapterTitleAt,
                  listenable: runtime,
                  onChapterTap: _jumpToChapterFromDrawer,
                  onClosed: _handleDrawerClosed,
                ),
                backgroundColor: palette.readerBackground,
                infoColor: palette.readerInfo,
                textColor: palette.readerText,
                controlsVisible: menu.controlsVisible,
                showReadTitleAddition: settings.showReadTitleAddition,
                infoState: _infoStateOf(runtime),
                loadingTarget: _infoTargetOf(runtime),
                originName: widget.book.originName,
                progressListenable: _progress,
                navigation: navigation,
                isAutoPaging: _host.autoPage?.isRunning ?? false,
                hideStatusBar: settings.hideStatusBar,
                headerInfo: settings.headerInfo,
                footerInfo: settings.footerInfo,
                paddingHorizontal: settings.paddingHorizontal,
                paddingTop: settings.paddingTop,
                paddingBottom: settings.paddingBottom,
                footerOffset: settings.footerOffset,
                edgeFade: settings.edgeFade,
                use24HourClock: settings.use24HourClock,
                progressFractionDigits: settings.progressFractionDigits,
                topCutoutExtent: _topCutoutExtent,
                dayNightIcon: isDarkBackground
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                dayNightTooltip: isDarkBackground ? '切換淺色模式' : '切換深色模式',
                onExitIntent: _handleExitIntent,
                onSystemBack: _handleSystemBack,
                onMore: () => unawaited(_showMore()),
                onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                onTts: () => _openPanel(_showTts),
                onTimedTts: () => unawaited(_host.tts?.toggleTimed()),
                onInterface: () => _openPanel(
                  () => ReaderV2SettingsSheets.showInterfaceSettings(
                    context,
                    settings,
                  ),
                ),
                onSettings: () => unawaited(_openReadingPreferences()),
                onAutoPage: _coordinator.toggleAutoPage,
                // 深淺是整個 App 共用的設定，閱讀器切換後其他畫面一併跟著換。
                onToggleDayNight: () => ThemeRevealScope.of(context).run(
                  change: () => context.read<SettingsProvider>().setThemeMode(
                    isDarkBackground ? ThemeMode.light : ThemeMode.dark,
                  ),
                ),
                onReplaceRule: () =>
                    _openPanel(() => _coordinator.openReplaceRule(context)),
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
                brightnessControl:
                    ReaderV2DeviceChannel.supportsWindowBrightness
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
                onMenuHidden: _handleMenuHidden,
                onDrawerChanged: (open) => _drawerOpen.value = open,
              ),
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
          // 正文會畫出這一區，由閱讀頁框架裁切（見 HybridReaderScreen）。
          clipBehavior: Clip.none,
          children: [
            HybridReaderScreen(
              runtime: runtime,
              backgroundColor: palette.readerBackground,
              textColor: palette.readerText,
              style: style,
              viewportController: _host.viewportController,
              ttsHighlight: _host.tts?.currentHighlight,
              controlsVisible: _host.menu.controlsVisible,
              textSelectionEnabled:
                  !(_host.autoPage?.isRunning ?? false) &&
                  !(_host.tts?.isPlaying ?? false),
              onHideText: (selection) =>
                  unawaited(_coordinator.hideText(selection)),
              highlightColor: _host.settings.highlightColor.resolve(palette),
              highlightStrength: _host.settings.highlightStrength,
              onContentTapUp: _handleContentTap,
              progressListenable: _progress,
              bookUrl: widget.book.bookUrl,
              skeletonPages: _host.dependencies.skeletonPages,
              pageTurnOverlap: _host.settings.pageTurnOverlap,
              pageTurnDuration: _host.settings.pageTurnSpeed.duration,
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
    final message = runtime.state.unavailableMessage ?? '';
    if (_verificationFor(message) case final request?) {
      // 書源要在網頁上驗證：「前往驗證」排第一，關掉就重開（ADR 0038）。
      return _readerErrorActions(
        runtime,
        first: (
          label: '前往驗證',
          icon: Icons.open_in_browser_rounded,
          onPressed: () => unawaited(_verify(request)),
        ),
      );
    }
    if (LoginCheckException.describes(message)) {
      // 要登入才讀得到：「登入」排第一，登入完自動重開（ADR 0038）。
      return FutureBuilder<BookSource?>(
        future: _loginSource(),
        builder: (context, snapshot) => _readerErrorActions(
          runtime,
          first: switch (snapshot.data) {
            final source? => (
              label: '登入',
              icon: Icons.login_rounded,
              onPressed: () => unawaited(_login(source)),
            ),
            null => null,
          },
        ),
      );
    }
    return _readerErrorActions(runtime);
  }

  /// 開書失敗的按鈕列；[first] 是能解決這次失敗的那一顆（登入、前往驗證），
  /// 有的話排第一、重試退成次要。
  Widget _readerErrorActions(
    ReaderV2Runtime runtime, {
    ({String label, IconData icon, VoidCallback onPressed})? first,
  }) {
    void retry() => unawaited(_retryReader(runtime));
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (first != null) ...[
          FilledButton.icon(
            onPressed: first.onPressed,
            icon: Icon(first.icon),
            label: Text(first.label),
          ),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('重試'),
          ),
        ] else
          FilledButton.icon(
            onPressed: retry,
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
    if (_host.menu.controlsVisible.value) {
      _host.menu.dismissControls();
      return;
    }
    _handleExitIntent();
  }

  /// 點目錄的一章（登入或驗證回來、取不到的是別章時也走這裡）：目錄與選單
  /// 馬上收起、紙蓋上、頁首頁尾淡入骨架，這幾段動畫都播完才開始載入
  /// （ADR 0018）。取不到正文時紙掀開回到原處，提示原因。
  void _jumpToChapterFromDrawer(int index) {
    final scaffold = _scaffoldKey.currentState;
    final drawerClosed = scaffold != null && scaffold.isDrawerOpen
        ? (_drawerClosed ??= Completer<void>()).future
        : Future<void>.value();
    scaffold?.closeDrawer();
    _host.menu.dismissControls();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!reduceMotion) unawaited(_skeletonFadeIn.forward(from: 0));
    unawaited(
      _coordinator.jumpToChapter(
        index,
        settled: Future.wait([
          drawerClosed,
          if (!reduceMotion)
            TransitionSettled.until(_skeletonFadeIn, (s) => s.isCompleted),
        ]),
      ),
    );
  }

  void _handleDrawerClosed() {
    _drawerClosed?.complete();
    _drawerClosed = null;
  }

  void _drainRuntimeNotice() {
    final notice = _host.runtime?.takeUserNotice();
    if (!mounted || notice == null || notice.message.isEmpty) return;
    final (:message, :chapterIndex) = notice;
    if (_verificationFor(message) case final request?) {
      // 書源要在網頁上驗證：提示旁給「前往驗證」，關掉就重抓取不到的那一章。
      _showNotice(
        message,
        action: (
          label: '前往驗證',
          onPressed: () =>
              unawaited(_verify(request, failedChapter: chapterIndex)),
        ),
      );
      return;
    }
    if (!LoginCheckException.describes(message)) {
      _showNotice(message);
      return;
    }
    // 要登入才讀得到：提示旁給「登入」，登入完重抓取不到的那一章（ADR 0038）。
    unawaited(
      _loginSource().then((source) {
        if (!mounted) return;
        _showNotice(
          message,
          action: source == null
              ? null
              : (
                  label: '登入',
                  onPressed: () =>
                      unawaited(_login(source, failedChapter: chapterIndex)),
                ),
        );
      }),
    );
  }

  /// 這本書的書源，有登入（ADR 0038）時才有；換源會換掉整個閱讀頁，所以
  /// 一頁查一次。
  Future<BookSource?> _loginSource() => _loginSourceLookup ??= () async {
    if (widget.book.isLocal) return null;
    final source = await _host.dependencies.sourceDao.getByUrl(
      widget.book.origin,
    );
    return source != null && source.hasLogin ? source : null;
  }();
  Future<BookSource?>? _loginSourceLookup;

  /// 開書源的登入；登入資料變了就重抓（[_refetchFailed]）。[ticket] 是從
  /// 選單開的那一次：等選單滑出才推頁，回來後選單滑回來。
  Future<void> _login(
    BookSource source, {
    ReaderV2MenuDepartureTicket? ticket,
    int? failedChapter,
  }) async {
    final changed = await openSourceLogin(
      context,
      source,
      beforePush: ticket == null
          ? null
          : () async {
              final ready =
                  await ticket.menusGone &&
                  mounted &&
                  ticket.canDepart &&
                  (pageRouteOf(context)?.isCurrent ?? false);
              if (!ready && mounted) _host.releaseAutoPage();
              return ready;
            },
    );
    if (!mounted) return;
    if (ticket != null) _restoreMenuWhenUncovered();
    if (!changed) return;
    await _refetchFailed(failedChapter);
  }

  /// 失敗是因為書源要在網頁上驗證時，書源要開的那一頁（ADR 0038）。
  SourceBrowseRequest? _verificationFor(String message) {
    if (widget.book.isLocal ||
        !SourceVerificationException.describes(message)) {
      return null;
    }
    return SourceInteraction.verificationFor(widget.book.origin);
  }

  /// 「前往驗證」：開書源要的那一頁，關掉就重抓（[_refetchFailed]；不論
  /// 有沒有按完成，網頁的 Cookie 都存了）。
  Future<void> _verify(
    SourceBrowseRequest request, {
    int? failedChapter,
  }) async {
    await openSourceVerification(
      context,
      sourceUrl: widget.book.origin,
      sourceName: widget.book.originName,
      request: request,
    );
    if (mounted) await _refetchFailed(failedChapter);
  }

  /// 登入或驗證回來之後重抓：開書失敗的重開；取不到的是別章
  /// （[failedChapter]，例如跳章或捲到下一章時）就跳過去；否則重抓這一章、
  /// 停在原位。
  Future<void> _refetchFailed([int? failedChapter]) async {
    final runtime = _host.runtime;
    if (runtime == null) return;
    if (runtime.state.lifecycle == ReaderV2Lifecycle.unavailable) {
      await _retryReader(runtime);
    } else if (failedChapter != null &&
        failedChapter != _currentChapterIndex(runtime)) {
      _jumpToChapterFromDrawer(failedChapter);
    } else {
      await _refetchCurrentChapter();
    }
  }

  void _showNotice(
    String message, {
    ReaderV2NoticeAction? action,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!mounted || messenger == null) return;
    if (_visibleNoticeMessage == message) return;
    _visibleNoticeMessage = message;
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action == null
            ? null
            : SnackBarAction(label: action.label, onPressed: action.onPressed),
        // 帶按鈕的提示預設不會自己收起，會一直蓋在正文上。
        persist: false,
        duration: duration,
      ),
    );
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
          final readerRoute = pageRouteOf(context);
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
    final loginSource = await _loginSource();
    if (!mounted) return;
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
        if (loginSource != null)
          const AppSheetAction(
            label: '登入',
            icon: Icons.login_rounded,
            value: _ReaderMoreAction.login,
          ),
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
      case _ReaderMoreAction.login:
        if (loginSource != null) {
          await _login(loginSource, ticket: _departMenu());
        }
      case _ReaderMoreAction.bookDetail:
        await _showBookDetail();
      case _ReaderMoreAction.globalSettings:
        final pushed = await _pushOverMenu(
          _departMenu(),
          MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
        );
        if (!mounted || pushed == null) return;
        // 「閱讀偏好」頁以自己的 controller 寫入同一組偏好設定；
        // 回到閱讀器時重新載入，正文才會反映在那裡做的調整。等返回動畫
        // 播完才載入：設定變了會重排正文，不和返回動畫疊在一起（ADR 0018）。
        _restoreMenuWhenUncovered(
          beforeMenu: () => unawaited(_host.settings.loadSettings()),
        );
    }
  }

  /// 下方選單的「進階」：自動翻頁、繁簡、點擊區域、音量鍵這些不常邊讀邊
  /// 調的設定只在「閱讀偏好」一個地方（ADR 0030），不另開一個內容相同的
  /// 面板。和全域系統設定一樣等返回動畫播完才重讀設定（ADR 0018）。
  Future<void> _openReadingPreferences() async {
    final pushed = await _pushOverMenu(
      _departMenu(),
      MaterialPageRoute<void>(builder: (_) => const ReadingSettingsPage()),
    );
    if (!mounted || pushed == null) return;
    _restoreMenuWhenUncovered(
      beforeMenu: () => unawaited(_host.settings.loadSettings()),
    );
  }

  void _handleMenuHidden() => _menuDeparture.menusHidden();

  /// 收起選單、開一張推頁請求；推頁期間自動捲動保持暫停，選單再打開時
  /// 解除（見 [ReaderV2ControllerHost.holdAutoPageWhileAway]）。
  ReaderV2MenuDepartureTicket _departMenu() {
    _host.holdAutoPageWhileAway();
    return _menuDeparture.depart();
  }

  /// 從選單推一整頁（書籍詳情、全域設定）：等選單滑出畫面才推（見
  /// [ReaderV2MenuDeparture]）。推之前再確認這次請求沒有作廢（選單又打開、
  /// 改選了別的、離開閱讀器）、閱讀器仍是最上面的一頁、選單完全收著；
  /// 沒有推頁時回傳 null，推了就回傳那一頁關掉時的結果。
  Future<(T?,)?> _pushOverMenu<T>(
    ReaderV2MenuDepartureTicket ticket,
    Route<T> route,
  ) async {
    if (!await ticket.menusGone ||
        !mounted ||
        !ticket.canDepart ||
        !(pageRouteOf(context)?.isCurrent ?? false)) {
      if (mounted) _host.releaseAutoPage();
      return null;
    }
    return (await Navigator.of(context).push(route),);
  }

  /// 推上去的頁關掉後，等返回動畫播完再把選單滑回來，回到打開選單的
  /// 樣子；滑入不和返回動畫疊在一起，也不在淡入中的閱讀器裡出現。
  /// [beforeMenu] 在返回動畫播完、選單滑回之前呼叫（閱讀器已經被別頁
  /// 蓋住時也照樣呼叫）。
  void _restoreMenuWhenUncovered({VoidCallback? beforeMenu}) {
    unawaited(
      TransitionSettled.uncovered(context).then((_) {
        if (!mounted) return;
        beforeMenu?.call();
        if (!(pageRouteOf(context)?.isCurrent ?? false)) return;
        _host.menu.showControls();
      }),
    );
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
    final departure = _departMenu();
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
    // 寫入進度、查章節的期間選單可能又被打開：推之前由 [_pushOverMenu]
    // 再確認一次。
    final pushed = await _pushOverMenu(
      departure,
      MaterialPageRoute<String>(
        builder: (_) => BookDetailPage(book: book, fromReader: true),
      ),
    );
    if (!mounted || pushed == null) return;
    final (targetUrl,) = pushed;
    if (targetUrl == null) {
      _restoreMenuWhenUncovered();
      return;
    }
    // 點了章節回來：直接跳過去、不滑回選單，自動捲動照常接著捲。
    _host.releaseAutoPage();
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

  /// 從選單開面板：開著時上下選單與亮度條收起，正文整頁露出來（排版面板
  /// 沒有暗色遮罩，邊調邊看）；面板關掉後回到選單打開的樣子。
  ///
  /// 選單從面板滑上來的下一格才開始滑出：面板的第一格要建整個面板的骨架，
  /// 選單開始滑出那一格要重算整組選單的讀屏資訊，兩件事錯開一格（ADR 0029
  /// 做法 4；擠在同一格時那一格多 1–2ms）。
  void _openPanel(Future<void> Function() open) {
    var closed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !closed) _host.menu.dismissControls();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    unawaited(
      open().whenComplete(() {
        closed = true;
        if (!mounted || !(pageRouteOf(context)?.isCurrent ?? false)) return;
        _host.menu.showControls();
      }),
    );
  }

  Future<void> _showTts() async {
    final tts = _host.tts;
    if (tts == null) return;
    await ReaderV2MenuSheet.show<void>(
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

  /// 目錄還沒載入時（從書架開書，目錄在開書途中才從資料庫讀出），上次讀到
  /// 的那一章用書的閱讀紀錄裡的章名：開書時頁首頁尾的骨架照它量。
  String _rawChapterTitleAt(int index) {
    final runtime = _host.runtime;
    final title = runtime != null
        ? runtime.titleFor(index)
        : index >= 0 && index < widget.initialChapters.length
        ? widget.initialChapters[index].title
        : '';
    if (title.isNotEmpty || index != widget.book.chapterIndex) return title;
    return widget.book.durChapterTitle ?? '';
  }

  /// 要開的那一章：指定了開哪裡（例如書籍詳情點某一章）就是它，否則是書的
  /// 閱讀紀錄。和 Runtime 選開書位置的順序一樣。
  int get _openChapterIndex =>
      widget.openTarget?.location.chapterIndex ?? widget.book.chapterIndex;

  /// 載入期間頁首頁尾描述的位置（[ReaderV2InfoTarget]）：跳章時是要跳去
  /// 的那一章，開書時是要開的那一章（[_openChapterIndex]）。目錄還沒載入時
  /// 章數照書的紀錄。
  ReaderV2InfoTarget _infoTargetOf(ReaderV2Runtime? runtime) {
    final chapterIndex =
        runtime?.pendingLocation?.chapterIndex ??
        runtime?.state.visibleLocation.chapterIndex ??
        _openChapterIndex;
    final loaded = runtime?.chapterCount ?? widget.initialChapters.length;
    return ReaderV2InfoTarget(
      chapterIndex: chapterIndex,
      chapterCount: loaded > 0 ? loaded : widget.book.totalChapterNum,
      title: _chapterTitleAt(chapterIndex),
    );
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
  login,
  bookDetail,
  globalSettings,
}

/// 第一幀還沒有 Runtime 時的目前章：要開的那一章，不會變。
/// Runtime 建好後開書會通知閱讀頁重建，改聽
/// [ReaderV2Runtime.visibleChapterIndex]。
class _NoChapterYet implements ValueListenable<int> {
  const _NoChapterYet(this.value);

  @override
  final int value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
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
