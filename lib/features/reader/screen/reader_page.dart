import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/features/reader/features/bookmark/reader_bookmarks.dart';
import 'package:night_reader/core/models/reading/highlight.dart';
import 'package:night_reader/core/backup/highlight_export.dart';
import 'package:night_reader/features/reader/features/highlight/reader_highlight_sheet.dart';
import 'package:night_reader/features/reader/features/highlight/reader_highlights.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/storage/books_in_use.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/features/about/external_url_launcher.dart';
import 'package:night_reader/features/settings/appearance_settings_page.dart';
import 'package:night_reader/features/settings/tts_settings_page.dart';
import 'package:night_reader/shared/navigation/status_bar.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/features/reader/text_view/core/progress_snapshot.dart';
import 'package:night_reader/features/reader/text_view/reader_text_view.dart';
import 'package:night_reader/features/reader/screen/reader_controller_host.dart';
import 'package:night_reader/features/reader/screen/reader_chapter_info.dart';
import 'package:night_reader/features/reader/screen/reader_change_source.dart';
import 'package:night_reader/features/reader/screen/reader_borrow_chapter.dart';
import 'package:night_reader/features/reader/screen/reader_menu_pages.dart';
import 'package:night_reader/features/reader/screen/reader_source_remedy.dart';
import 'package:night_reader/features/reader/use_cases/reader_page_coordinator.dart';
import 'package:night_reader/features/reader/use_cases/coordinators/reader_page_exit_coordinator.dart';
import 'package:night_reader/features/reader/session/reader_session_facade.dart';
import 'package:night_reader/features/reader/features/brightness/reader_brightness.dart';
import 'package:night_reader/features/reader/features/brightness/reader_brightness_bar.dart';
import 'package:night_reader/features/reader/features/menu/reader_menu_sheet.dart';
import 'package:night_reader/features/reader/features/menu/reader_bottom_menu.dart';
import 'package:night_reader/features/reader/screen/reader_chapters_drawer.dart';
import 'package:night_reader/features/reader/screen/reader_side_panel.dart';
import 'package:night_reader/features/reader/screen/reader_volume_keys.dart';
import 'package:night_reader/features/reader/features/settings/reader_settings_sheets.dart';
import 'package:night_reader/features/reader/screen/reader_device_channel.dart';
import 'package:night_reader/features/reader/screen/reader_page_shell.dart';
import 'package:night_reader/features/reader/screen/reader_window_settings.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/theme_reveal_scope.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_open_target.dart';
import 'package:night_reader/features/reader/session/reader_progress_sync.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/session/reader_state.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/features/reader/features/tts/reader_tts_phase.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.book,
    this.openTarget,
    this.initialChapters = const <BookChapter>[],
  });

  final Book book;
  final ReaderOpenTarget? openTarget;
  final List<BookChapter> initialChapters;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with WidgetsBindingObserver, TickerProviderStateMixin
    implements ReaderExitFlowDelegate {
  static const ReaderSessionFacade _sessionFacade = ReaderSessionFacade();

  /// 左側的目錄面板。
  final ReaderSidePanelController _chapterPanel = ReaderSidePanelController();
  final ReaderPageExitCoordinator _exitCoordinator =
      ReaderPageExitCoordinator();

  late final ReaderControllerHost _host;
  late final ReaderPageCoordinator _coordinator;

  /// 換源（[ReaderChangeSource]）。
  late final ReaderChangeSource _changeSource = ReaderChangeSource(
    context: () => context,
    mounted: () => mounted,
    book: widget.book,
    host: _host,
    info: _chapterInfo,
  );

  late final ReaderBorrowChapter _borrowChapter = ReaderBorrowChapter(
    context: () => context,
    mounted: () => mounted,
    book: widget.book,
    host: _host,
    showNotice: _showNotice,
  );

  /// 從閱讀選單開出去的頁面與面板（[ReaderMenuPages]）。
  late final ReaderMenuPages _menuPages = ReaderMenuPages(
    context: () => context,
    mounted: () => mounted,
    book: widget.book,
    initialChapters: widget.initialChapters,
    host: _host,
    info: _chapterInfo,
    coordinator: _coordinator,
    remedy: _remedy,
    changeSource: _changeSource,
    showNotice: _showNotice,
    retire: () {
      _host.retire();
      _progressSync.retire();
    },
    resume: () {
      _host.resume();
      _progressSync.resume();
    },
  );

  /// 讀不到正文時的按鈕列、登入與網頁驗證（[ReaderSourceRemedy]）。
  late final ReaderSourceRemedy _remedy = ReaderSourceRemedy(
    context: () => context,
    mounted: () => mounted,
    book: widget.book,
    host: _host,
    info: _chapterInfo,
    changeSource: _changeSource,
    borrowChapter: _borrowChapter,
    showNotice: _showNotice,
    jumpToChapter: _jumpToChapterFromDrawer,
    jumpToChapterAndWait: (index) => _coordinator.jumpToChapter(index),
    exit: _handleExitIntent,
    restoreMenuWhenUncovered: () => _menuPages.restoreMenuWhenUncovered(),
  );

  /// 目前章、章名與頁首頁尾的資訊（[ReaderChapterInfo]）。
  late final ReaderChapterInfo _chapterInfo = ReaderChapterInfo(
    book: widget.book,
    initialChapters: widget.initialChapters,
    openTarget: widget.openTarget,
    runtime: () => _host.runtime,
    chineseConvert: () => _host.settings.chineseConvert,
  );
  late final ReaderProgressSync _progressSync;

  final ValueNotifier<ProgressSnapshot?> _progress =
      ValueNotifier<ProgressSnapshot?>(null);
  Size? _lastViewportSize;
  String? _visibleNoticeMessage;

  /// 畫面上那則提示；收起時只清自己的（被下一則換掉的不清）。
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _visibleNotice;
  bool _rebuildQueued = false;
  StreamSubscription<String>? _settingsSaveFailures;
  StreamSubscription<String>? _hostNotices;

  /// 鏡頭挖孔與曲面邊緣佔掉的上緣高度；隱藏狀態列時頁首只依它決定。
  double? _topCutoutExtent;

  /// 開書的換頁動畫與骨架淡入都播完時完成；載入等它（ADR 0018）。
  final Completer<void> _entrance = Completer<void>();

  /// 從目錄跳章時，等目錄收起的那一下；收到底、目錄從畫面上拿掉時完成。
  Completer<void>? _drawerClosed;

  /// 目錄開著時音量鍵照常調音量。
  final ValueNotifier<bool> _drawerOpen = ValueNotifier(false);

  /// 正文的紙與頁首頁尾的骨架共用的呼吸（[SharedSkeletonBreath]）：誰先
  /// 出現都照同一個相位，紙停住呼吸時頁首頁尾一起停。
  late final SharedSkeletonBreath _skeletonBreath = SharedSkeletonBreath(
    vsync: this,
  );
  bool _entranceWatched = false;

  /// 只拿來計骨架淡入的時長（頁首頁尾骨架與照紀錄畫的正文骨架都是
  /// [AppMotion.fade]）：開書時和這一頁的第一幀同時開始，從目錄跳章時和
  /// 蓋紙同時開始。
  late final AnimationController _skeletonFadeIn = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
  );

  /// 閱讀器開著時，開 App 或還原備份的清理不動這本書（[BooksInUse]）。
  late final BookInUse _inUse;

  @override
  void initState() {
    super.initState();
    _inUse = BooksInUse.hold(widget.book.bookUrl);
    _host = ReaderControllerHost(
      book: widget.book,
      initialChapters: widget.initialChapters,
      openTarget: widget.openTarget,
      entrance: _entrance.future,
      onChanged: _handleControllerChanged,
      isMounted: () => mounted,
      openLocation: (runtime) => _progressSync.openLocation(runtime),
    );
    _coordinator = ReaderPageCoordinator(host: _host, showNotice: _showNotice)
      ..openChapters = _openChapters
      ..toggleDayNight = _toggleDayNight;
    _settingsSaveFailures = _host.settings.saveFailures.listen(_showNotice);
    _hostNotices = _host.notices.listen(_showNotice);
    _progressSync = ReaderProgressSync(
      book: widget.book,
      runtime: () => _host.runtime,
      onJumped: _showSyncHint,
      bookDao: _host.dependencies.bookDao,
      openTarget: widget.openTarget,
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
    final extent = await ReaderDeviceChannel.topCutoutExtent();
    // 取不到時保留上一次的值，避免頁首在暫態中跳回系統內距。
    if (!mounted || extent == null || extent == _topCutoutExtent) return;
    setState(() => _topCutoutExtent = extent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drawerOpen.dispose();
    _chapterPanel.dispose();
    _skeletonBreath.dispose();
    unawaited(_settingsSaveFailures?.cancel());
    unawaited(_hostNotices?.cancel());
    _menuPages.dispose();
    _coordinator.dispose();
    _progress.dispose();
    _host.menu.controlsVisible.removeListener(_dismissSyncHintOnMenu);
    // 在 runtime 釋放前：存好最後的位置再上傳。
    _progressSync.dispose();
    _host.dispose();
    _skeletonFadeIn.dispose();
    _inUse.release();
    super.dispose();
  }

  /// 跳到另一台的進度後，提示顯示期間停在的位置；一翻頁、捲動就收起提示。
  ReaderLocation? _syncHintAt;

  static const String _syncHintMessage = '已接上另一台的進度';

  void _showSyncHint(ReaderLocation previous) {
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
    _remedy.drainNotice();
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
    final navigation = ReaderChapterNavigationState(
      chapterCount: runtime?.chapterCount ?? widget.initialChapters.length,
      // 換章不通知閱讀頁：用到目前章的小元件各自聽它。
      current:
          runtime?.visibleChapterIndex ??
          _NoChapterYet(_chapterInfo.openChapterIndex),
      scrub: menu.scrub,
      titleFor: _chapterInfo.displayTitleAt,
    );

    final customBrightness =
        !settings.brightnessAuto &&
        ReaderDeviceChannel.supportsWindowBrightness;
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
        child: ReaderWindowSettings(
          keepScreenOn: settings.keepScreenOn,
          backlight: customBrightness
              ? ReaderBrightness.backlightFor(settings.brightness)
              : null,
          orientation: settings.orientation,
          child: ReaderVolumeKeys(
            enabled: settings.volumeKeyPage && !(_host.tts?.isPlaying ?? false),
            blockers: [menu.controlsVisible, _drawerOpen],
            onKey: (volumeDown) => unawaited(
              _coordinator.movePage(
                forward: volumeDown != settings.volumeKeyReversed,
              ),
            ),
            child: _DimOverlay(
              dim: customBrightness
                  ? ReaderBrightness.dimFor(
                      settings.brightness,
                      maxDim: settings.maxDim,
                    )
                  : 0,
              // 頁首頁尾的骨架和正文的紙同一口呼吸。
              child: SharedSkeletonBreathScope(
                breath: _skeletonBreath,
                child: ReaderPageShell(
                  book: widget.book,
                  content: _buildContent(context),
                  chapterPanelController: _chapterPanel,
                  chapterPanel: ReaderChaptersDrawer(
                    shown: _chapterPanel.shown,
                    chapters: runtime?.chapters ?? widget.initialChapters,
                    currentChapter: navigation.current,
                    titleFor: _chapterInfo.chapterTitleAt,
                    listenable: runtime,
                    onChapterTap: _jumpToChapterFromDrawer,
                    bookmarks: _host.bookmarks.available
                        ? _host.bookmarks
                        : null,
                    bookmarkChapter: (bookmark) =>
                        ReaderBookmarks.chapterIndexIn(
                          bookmark,
                          runtime?.chapters ?? widget.initialChapters,
                        ),
                    onBookmarkTap: _jumpToBookmarkFromDrawer,
                    onBookmarkDelete: _deleteBookmark,
                    highlights: _host.highlights.available
                        ? _host.highlights
                        : null,
                    highlightChapter: (highlight) =>
                        ReaderHighlights.chapterIndexIn(
                          highlight,
                          runtime?.chapters ?? widget.initialChapters,
                        ),
                    onHighlightTap: _jumpToHighlightFromDrawer,
                    onHighlightDelete: _coordinator.deleteHighlight,
                    onHighlightExport: (items) => unawaited(
                      shareHighlights([
                        (
                          bookName: widget.book.name,
                          bookAuthor: widget.book.author,
                          items: items,
                        ),
                      ]),
                    ),
                  ),
                  onChapterPanelClosed: _handleDrawerClosed,
                  backgroundColor: palette.readerBackground,
                  infoColor: palette.readerInfo,
                  textColor: palette.readerText,
                  controlsVisible: menu.controlsVisible,
                  showReadTitleAddition: settings.showReadTitleAddition,
                  infoState: _chapterInfo.infoStateOf(runtime),
                  loadingTarget: _chapterInfo.infoTargetOf(runtime),
                  originName: widget.book.originName,
                  onOpenOrigin: widget.book.isLocal ? null : _openChapterWeb,
                  progressListenable: _progress,
                  navigation: navigation,
                  isAutoPaging: _host.autoPage?.isRunning ?? false,
                  hideStatusBar: settings.hideStatusBar,
                  headerInfo: settings.headerInfo,
                  footerInfo: settings.footerInfo,
                  // 正文區橫向佔滿畫面，和正文用同一個寬度算。
                  paddingHorizontal: settings.paddingHorizontalFor(
                    MediaQuery.sizeOf(context).width,
                  ),
                  menuInset: settings.menuInsetFor(
                    MediaQuery.sizeOf(context).width,
                  ),
                  paddingTop: settings.paddingTop,
                  paddingBottom: settings.paddingBottom,
                  footerOffset: settings.footerOffset,
                  infoFontSize: settings.infoFontSize,
                  fontFamily: settings.readerFontFamily,
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
                  onMore: () => unawaited(_menuPages.showMore()),
                  onOpenDrawer: _openChapters,
                  onTts: () => _menuPages.openPanel(_menuPages.showTts),
                  onTimedTts: () => unawaited(_host.tts?.toggleTimed()),
                  onInterface: () => _menuPages.openPanel(
                    () => ReaderSettingsSheets.showInterfaceSettings(
                      context,
                      settings,
                    ),
                  ),
                  onSettings: () =>
                      unawaited(_menuPages.openReadingPreferences()),
                  onAutoPage: _coordinator.toggleAutoPage,
                  onToggleDayNight: _toggleDayNight,
                  onReplaceRule: () => _menuPages.openPanel(
                    () => _coordinator.openReplaceRule(context),
                  ),
                  onAutoPageSettings: () =>
                      unawaited(_menuPages.openReadingPreferences()),
                  onReplaceRuleSettings: () =>
                      unawaited(_menuPages.openReplaceRulePage()),
                  onTimedTtsSettings: () => unawaited(
                    _menuPages.openSettingsPage(const TtsSettingsPage()),
                  ),
                  onDayNightSettings: () => unawaited(
                    _menuPages.openSettingsPage(const AppearanceSettingsPage()),
                  ),
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
                    final drag = menu.onScrubEnd(percent);
                    unawaited(_commitScrub(percent, drag));
                  },
                  brightnessControl:
                      ReaderDeviceChannel.supportsWindowBrightness
                      ? ReaderBrightnessBar(
                          auto: settings.brightnessAuto,
                          level: settings.brightness,
                          onAutoChanged: settings.setBrightnessAuto,
                          onChanged: (level) =>
                              settings.setBrightness(level, persist: false),
                          onChangeEnd: settings.setBrightness,
                        )
                      : null,
                  sleepTimer: _host.tts?.sleepTimer,
                  ttsPhase: _host.tts?.phase ?? ReaderTtsPhase.idle,
                  onMenuHidden: _menuPages.menusHidden,
                  onChapterPanelChanged: (open) => _drawerOpen.value = open,
                ),
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
          viewportWidth: size.width,
          topInfoReservedExternally: true,
          bottomInfoReservedExternally: _host.settings.showReadTitleAddition,
        );
        final runtime = _host.ensureRuntime(size, style);
        _host.syncRuntimeConfiguration(runtime, size, style);

        final palette = StylePalette.of(context);
        return Stack(
          fit: StackFit.expand,
          // 正文會畫出這一區，由閱讀頁框架裁切（見 ReaderTextView）。
          clipBehavior: Clip.none,
          children: [
            ReaderTextView(
              skeletonBreath: _skeletonBreath,
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
              onReplaceText: (selection) =>
                  unawaited(_coordinator.replaceText(context, selection)),
              onBookmarkText: _host.bookmarks.available
                  ? (selection) =>
                        unawaited(_coordinator.addBookmark(selection))
                  : null,
              marks: _host.bookmarks.marks,
              onHighlightText: _host.highlights.available
                  ? (selection) =>
                        unawaited(_coordinator.addHighlight(selection))
                  : null,
              highlights: _host.highlights.marks,
              onHighlightTap: _host.highlights.available
                  ? (id) => unawaited(_showHighlight(id))
                  : null,
              highlightColor: _host.settings.highlightColor.resolve(palette),
              highlightStrength: _host.settings.highlightStrength,
              onContentTapUp: _handleContentTap,
              progressListenable: _progress,
              bookUrl: widget.book.bookUrl,
              skeletonPages: _host.dependencies.skeletonPages,
              pageTurnOverlap: _host.settings.pageTurnOverlap,
              pageTurnDuration: _host.settings.pageTurnSpeed.duration,
            ),
            if (runtime.state.lifecycle == ReaderLifecycle.unavailable)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.all(24),
                  child: _remedy.errorActions(runtime),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openChapters() => _chapterPanel.open();

  /// 深淺是整個 App 共用的設定，閱讀器切換後其他畫面一併跟著換。
  void _toggleDayNight() {
    final dark = StylePalette.of(context).brightness == Brightness.dark;
    // 暈開中連按時這一下排到暈完才執行，那時閱讀器可能已經關掉：設定先取好。
    final settings = context.read<SettingsProvider>();
    ThemeRevealScope.of(context).run(
      change: () =>
          settings.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
    );
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
  /// （ADR 0018）。取不到正文時紙掀開回到原處，提示原因。付費章節不跳，
  /// 目錄留著、只提示（ADR 0057）。
  void _jumpToChapterFromDrawer(int index) {
    if (_host.runtime?.chapterAt(index)?.isLocked ?? false) {
      _showNotice(lockedChapterNotice);
      return;
    }
    final settled = _closeDrawerForJump();
    unawaited(_coordinator.jumpToChapter(index, settled: settled));
  }

  void _jumpToBookmarkFromDrawer(Bookmark bookmark) {
    final settled = _closeDrawerForJump();
    unawaited(_coordinator.jumpToBookmark(bookmark, settled: settled));
  }

  void _jumpToHighlightFromDrawer(Highlight highlight) {
    final settled = _closeDrawerForJump();
    unawaited(_coordinator.jumpToHighlight(highlight, settled: settled));
  }

  /// 點正文上已畫的標註：打開標註面板，換顏色、樣子或刪掉。
  Future<void> _showHighlight(int id) async {
    final highlights = _host.highlights;
    final highlight = highlights.byId(id);
    if (highlight == null) return;
    await ReaderMenuSheet.show<void>(
      context,
      settings: _host.settings,
      builder: (_) => ReaderHighlightSheet(
        highlight: highlight,
        onChanged: (next) => unawaited(highlights.save(next)),
        onDelete: _coordinator.deleteHighlight,
      ),
    );
  }

  /// 從目錄面板跳過去：收起面板與選單、蓋上紙；傳回面板收完、紙蓋好的
  /// 時候，跳轉等它才開始載入（ADR 0018）。
  Future<void> _closeDrawerForJump() {
    final drawerClosed = _chapterPanel.isOpen
        ? (_drawerClosed ??= Completer<void>()).future
        : Future<void>.value();
    _chapterPanel.close();
    _host.menu.dismissControls();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // 目錄收起途中又點了一章：骨架淡入照原本那次的時間走完，不重算。
    if (!reduceMotion && !_skeletonFadeIn.isAnimating) {
      unawaited(_skeletonFadeIn.forward(from: 0));
    }
    return Future.wait([
      drawerClosed,
      if (!reduceMotion)
        TransitionSettled.until(_skeletonFadeIn, (s) => s.isCompleted),
    ]);
  }

  void _deleteBookmark(Bookmark bookmark) {
    final bookmarks = _host.bookmarks;
    unawaited(bookmarks.remove(bookmark));
    _showNotice(
      '已刪除書籤',
      action: (
        label: '復原',
        onPressed: () => unawaited(bookmarks.restore(bookmark)),
      ),
    );
  }

  void _handleDrawerClosed() {
    _drawerClosed?.complete();
    _drawerClosed = null;
  }

  void _showNotice(
    String message, {
    ReaderNoticeAction? action,
    Duration duration = const Duration(milliseconds: 4000),
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    // 同樣的字還在畫面上就不再跳（同一個錯一直重複時）；帶按鈕的提示（例如
    // 「復原」）每一則綁著不同的資料，照樣換上這一則。
    if (action == null && _visibleNoticeMessage == message) return;
    _visibleNoticeMessage = message;
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: UiText(message),
        action: action == null
            ? null
            : SnackBarAction(
                label: context.ui(action.label),
                onPressed: action.onPressed,
              ),
        // 帶按鈕的提示預設不會自己收起，會一直蓋在正文上。
        persist: false,
        duration: duration,
      ),
    );
    _visibleNotice = controller;
    unawaited(
      controller.closed.then<void>((_) {
        if (!identical(_visibleNotice, controller)) return;
        _visibleNotice = null;
        _visibleNoticeMessage = null;
      }),
    );
  }

  void _handleExitIntent() {
    unawaited(
      _exitCoordinator.handleExitIntent(
        context: context,
        provider: this,
        // 閱讀器一律從書架以 App 層級的路由打開。
        popNavigator: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    );
  }

  /// 拖動條放開：跳到選定位置。正文排到新位置的那一幀才發布頁尾進度，
  /// 所以等跳轉做完再過一幀，拖動條才改回跟閱讀進度。
  /// [drag] 是這一次拖動的編號：連續放開兩次時，先做完的舊跳轉不解除
  /// 新一次的停留。
  Future<void> _commitScrub(double percent, int drag) async {
    try {
      await _coordinator.commitChapterPercent(percent);
    } finally {
      if (mounted) {
        WidgetsBinding.instance
          ..addPostFrameCallback((_) {
            // 排進來之後、這一幀之前閱讀器可能已經關掉。
            if (mounted) _host.menu.onScrubSettled(drag);
          })
          ..ensureVisualUpdate();
      }
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
        ReaderLocation(
          chapterIndex: widget.book.chapterIndex,
          charOffset: widget.book.charOffset,
          visualOffsetPx: widget.book.visualOffsetPx,
        );
    final chapters = runtime?.chapters ?? widget.initialChapters;
    await _sessionFacade.addCurrentBookToBookshelf(
      book: widget.book,
      chapters: chapters,
      location: location,
      chapterTitle: _chapterInfo.chapterTitleAt(location.chapterIndex),
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

  /// 點書源膠囊：用瀏覽器開正在讀的這一章（同 Legado 點章節網址）。
  void _openChapterWeb() {
    final runtime = _host.runtime;
    final index = _chapterInfo.currentChapterIndex(runtime);
    final chapter = _chapterInfo.chapterAt(index);
    final url = chapter?.webPageUrl;
    if (url == null) {
      _showNotice('這一章沒有網頁可以開');
      return;
    }
    unawaited(launchExternalUrlWithFeedback(context, url));
  }
}

/// 第一幀還沒有 Runtime 時的目前章：要開的那一章，不會變。
/// Runtime 建好後開書會通知閱讀頁重建，改聽
/// [ReaderRuntime.visibleChapterIndex]。
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
