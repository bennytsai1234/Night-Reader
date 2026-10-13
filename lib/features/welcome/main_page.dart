import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/default_data.dart';
import 'package:night_reader/features/about/update_check_runner.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/shared/navigation/expand_route.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

Color _groupedBackground(BuildContext context) =>
    AppChrome.of(context).groupedBackground;

const List<MainDestination> _defaultDestinations = [
  MainDestination(
    icon: Icons.auto_stories_outlined,
    selectedIcon: Icons.auto_stories,
    label: '書架',
    page: BookshelfPage(),
    hidesTabBarOnScroll: true,
  ),
  MainDestination(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: '發現',
    page: ExplorePage(),
    background: _groupedBackground,
    hidesTabBarOnScroll: true,
  ),
  MainDestination(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: '我的',
    page: SettingsPage(),
    // 「我的」是 GroupedListView，底色是分組底色。
    background: _groupedBackground,
  ),
];

class MainPage extends StatefulWidget {
  const MainPage({super.key, this.destinations, this.onDestinationDoubleTap});

  final List<MainDestination>? destinations;
  final MainDestinationDoubleTapCallback? onDestinationDoubleTap;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  DateTime _lastTapTime = DateTime(0);
  DateTime? _lastBackPressedAt;

  bool _nativeSplashReleaseScheduled = false;
  bool _showStartupLoadingOverlay = false;
  DateTime? _splashHeldAt;
  BookshelfProvider? _splashShelfProvider;
  VoidCallback? _splashShelfListener;
  Timer? _splashTimeoutTimer;

  static const _splashMinDisplay = Duration(milliseconds: 900);
  static const _splashShelfTimeout = Duration(seconds: 2);

  late final PageController _pageController = PageController(
    initialPage: _currentIndex,
  );

  static const _exitBackInterval = Duration(seconds: 2);
  static const _tabAnimationDuration = AppMotion.spring;
  static const _tabAnimationCurve = AppMotion.springCurve;

  late final List<MainDestination> _destinations =
      widget.destinations ?? _defaultDestinations;

  /// 分頁進入整頁編輯時由分頁設為 true（見 [FloatingTabBarScope]）。
  final ValueNotifier<bool> _tabBarHidden = ValueNotifier(false);

  /// 往下捲時分頁列與漸隱帶沉下讓出畫面。和 [_tabBarHidden] 不同：不鎖
  /// 左右換頁，返回鍵也照常。
  bool _scrollHidden = false;

  /// 手指拖曳或拖曳後的慣性捲動中；程式捲動（例如展開書源後自動捲到它）
  /// 不算方向。
  bool _userScrolling = false;

  /// 同一方向累計的捲動距離，正值往下。
  double _scrollIntent = 0;

  /// 捲過這段距離後才會因往下捲而讓出：根分頁的大標題正好收完，不會在頁首
  /// 還在收合時分頁列也跟著動。
  static const double _scrollHideStart = AppGlass.largeTitleHeight;

  @override
  void dispose() {
    _splashTimeoutTimer?.cancel();
    _detachSplashShelfListener();
    _pageController.dispose();
    _tabBarHidden.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 整頁編輯時由編輯工具列佔用分頁列的位置，捲動讓出的狀態歸零。
    _tabBarHidden.addListener(() => setState(_resetScrollHidden));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initDeferredStartupData());
      final hasShelfProvider = context.read<BookshelfProvider?>() != null;
      if (widget.destinations == null || hasShelfProvider) {
        _releaseSplashWhenShelfReady();
      }
      if (widget.destinations == null) {
        unawaited(_runAutomaticUpdateCheck());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackIntent();
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView(
              controller: _pageController,
              physics: _tabBarHidden.value
                  ? const NeverScrollableScrollPhysics()
                  : null,
              onPageChanged: (idx) {
                setState(() {
                  _currentIndex = idx;
                  _resetScrollHidden();
                });
              },
              children: List.generate(
                _destinations.length,
                (index) => _KeepAliveWrapper(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _destinations[index].hidesTabBarOnScroll
                        ? (notification) => _onPageScroll(index, notification)
                        : null,
                    child: FloatingTabBarScope(
                      hidden: _tabBarHidden,
                      child: _destinations[index].page,
                    ),
                  ),
                ),
              ),
            ),
            // 分頁列後方的漸隱帶，顏色跟著頁面位置在相鄰分頁的背景色間過渡。
            // 整頁編輯時收掉，由分頁墊在自己的編輯工具列後面。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, _) => FloatingTabBarFade(
                  color: _fadeColor(context),
                  hidden: _tabBarHidden.value || _scrollHidden,
                ),
              ),
            ),
            // 啟動載入遮罩只蓋書架分頁；顯示時擋住點擊，不讓點擊穿到底下
            // 看不見的按鈕。
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !(_showStartupLoadingOverlay && _currentIndex == 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _showStartupLoadingOverlay && _currentIndex == 0
                      ? ColoredBox(
                          key: const ValueKey('startup-loading-overlay'),
                          color: Theme.of(context).scaffoldBackgroundColor
                              .withValues(alpha: 0.96),
                          child: Center(
                            child: Semantics(
                              liveRegion: true,
                              label: '正在載入書架',
                              child: ExcludeSemantics(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: AppSpacing.lg),
                                    Text('正在載入書架…'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('startup-loading-overlay-hidden'),
                        ),
                ),
              ),
            ),
          ],
        ),
        extendBody: true,
        bottomNavigationBar: FloatingTabBar(
          controller: _pageController,
          currentIndex: _currentIndex,
          hidden: _tabBarHidden.value || _scrollHidden,
          items: [
            for (final destination in _destinations)
              FloatingTabItem(
                icon: destination.icon,
                selectedIcon: destination.selectedIcon,
                label: destination.label,
              ),
          ],
          onSearch: widget.destinations == null ? _openSearch : null,
          onTap: (index) {
            if (_currentIndex == index) {
              if (DateTime.now().difference(_lastTapTime).inMilliseconds <
                  300) {
                _handleDoubleTap(index);
              }
              _lastTapTime = DateTime.now();
              return;
            }
            _pageController.animateToPage(
              index,
              duration: _tabAnimationDuration,
              curve: _tabAnimationCurve,
            );
          },
        ),
      ),
    );
  }

  void _resetScrollHidden() {
    _scrollHidden = false;
    _userScrolling = false;
    _scrollIntent = 0;
  }

  void _setScrollHidden(bool value) {
    if (_scrollHidden == value) return;
    setState(() => _scrollHidden = value);
  }

  /// 往下捲（同一方向累計超過 [kTouchSlop]，也就是 Flutter 判定手指真的在
  /// 拖、不是手抖的距離）且已捲過 [_scrollHideStart] 時讓出；往上捲同樣距離、
  /// 回到頂端或捲到底時浮回來。只看目前分頁本身的直向清單。
  bool _onPageScroll(int index, ScrollNotification notification) {
    final metrics = notification.metrics;
    if (index != _currentIndex ||
        _tabBarHidden.value ||
        notification.depth != 0 ||
        metrics.axis != Axis.vertical) {
      return false;
    }
    switch (notification) {
      case UserScrollNotification(:final direction):
        _userScrolling = direction != ScrollDirection.idle;
        _scrollIntent = 0;
      case ScrollUpdateNotification(:final scrollDelta?) when _userScrolling:
        // 換方向就重新累計。
        if (scrollDelta.sign != _scrollIntent.sign) _scrollIntent = 0;
        _scrollIntent += scrollDelta;
        if (_scrollIntent > kTouchSlop && metrics.pixels > _scrollHideStart) {
          _setScrollHidden(true);
        } else if (_scrollIntent < -kTouchSlop) {
          _setScrollHidden(false);
        }
      default:
        break;
    }
    if (metrics.extentBefore <= 0 || metrics.extentAfter <= 0) {
      _setScrollHidden(false);
    }
    return false;
  }

  /// 頁面位置（以分頁索引為單位，滑動中是小數）。
  double _pagePosition() {
    if (_pageController.hasClients &&
        _pageController.position.hasContentDimensions) {
      return _pageController.page ?? _currentIndex.toDouble();
    }
    return _currentIndex.toDouble();
  }

  Color _fadeColor(BuildContext context) {
    final position = _pagePosition().clamp(
      0.0,
      (_destinations.length - 1).toDouble(),
    );
    final lower = position.floor();
    final upper = position.ceil();
    return Color.lerp(
      _destinations[lower].backgroundOf(context),
      _destinations[upper].backgroundOf(context),
      position - lower,
    )!;
  }

  void _handleDoubleTap(int index) {
    final cb = widget.onDestinationDoubleTap ?? _defaultDoubleTap;
    cb(context, index);
  }

  void _defaultDoubleTap(BuildContext context, int index) {
    if (widget.destinations != null) return;
    if (index == 0) {
      context.read<BookshelfProvider>().loadBooks();
    }
  }

  void _releaseSplashWhenShelfReady() {
    _splashHeldAt = DateTime.now();
    final shelf = context.read<BookshelfProvider?>();
    if (shelf == null) return;
    if (!shelf.isLoading) {
      _completeSplashShelfWait();
      return;
    }
    void listener() {
      if (!shelf.isLoading) _completeSplashShelfWait();
    }

    _splashShelfProvider = shelf;
    _splashShelfListener = listener;
    shelf.addListener(listener);
    _splashTimeoutTimer?.cancel();
    _splashTimeoutTimer = Timer(_splashShelfTimeout, _handleSplashShelfTimeout);
  }

  void _handleSplashShelfTimeout() {
    _splashTimeoutTimer = null;
    final shelf = _splashShelfProvider;
    if (shelf == null || !shelf.isLoading) {
      _completeSplashShelfWait();
      return;
    }

    if (!mounted) {
      _releaseNativeSplashOnce();
      return;
    }
    setState(() => _showStartupLoadingOverlay = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _releaseNativeSplashOnce();
    });
  }

  void _completeSplashShelfWait() {
    _splashTimeoutTimer?.cancel();
    _splashTimeoutTimer = null;
    _detachSplashShelfListener();
    if (mounted && _showStartupLoadingOverlay) {
      setState(() => _showStartupLoadingOverlay = false);
    }
    _releaseNativeSplashOnce();
  }

  void _releaseNativeSplashOnce() {
    if (_nativeSplashReleaseScheduled) return;
    _nativeSplashReleaseScheduled = true;
    if (widget.destinations != null) return;
    final heldAt = _splashHeldAt;
    final remaining = heldAt == null
        ? Duration.zero
        : _splashMinDisplay - DateTime.now().difference(heldAt);
    if (remaining > Duration.zero) {
      Future<void>.delayed(remaining, _onShelfShown);
    } else {
      _onShelfShown();
    }
  }

  /// 啟動畫面收起、書架露出後才在背景補排下載、檢查書架更新，不和首幀與
  /// 書架載入搶時間。
  void _onShelfShown() {
    FlutterNativeSplash.remove();
    if (!mounted) return;
    final shelf = context.read<BookshelfProvider?>();
    if (shelf == null) return;
    unawaited(_runAutomaticShelfRefresh(shelf));
  }

  Future<void> _runAutomaticShelfRefresh(BookshelfProvider shelf) async {
    try {
      await shelf.onAppLaunch();
    } catch (e, stack) {
      AppLog.e('Bookshelf refresh failed: $e', error: e, stackTrace: stack);
    }
  }

  void _detachSplashShelfListener() {
    final provider = _splashShelfProvider;
    final listener = _splashShelfListener;
    if (provider != null && listener != null) {
      provider.removeListener(listener);
    }
    _splashShelfProvider = null;
    _splashShelfListener = null;
  }

  Future<void> _initDeferredStartupData() async {
    try {
      await DefaultData.initDeferred();
    } catch (e, stack) {
      AppLog.e('Deferred init error: $e', error: e, stackTrace: stack);
    }
  }

  Future<void> _runAutomaticUpdateCheck() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    try {
      await UpdateCheckRunner().runAutomatic(() => mounted ? context : null);
    } catch (e, stack) {
      AppLog.e('Update check failed: $e', error: e, stackTrace: stack);
    }
  }

  bool _openingSearch = false;

  /// 換頁動畫期間舊頁面還能點，連點兩下會疊兩個搜尋頁；開啟中就忽略。
  /// 搜尋頁從搜尋鈕的位置展開，返回時縮回按鈕。
  Future<void> _openSearch(Rect buttonRect) async {
    if (_openingSearch) return;
    _openingSearch = true;
    try {
      await Navigator.push(
        context,
        ExpandFromRectRoute<void>(
          sourceRect: buttonRect,
          backgroundColor: AppChrome.of(context).groupedBackground,
          builder: (_) => const SearchPage(),
        ),
      );
    } finally {
      _openingSearch = false;
    }
  }

  Future<void> _handleBackIntent() async {
    // 路由會通知所有 PopScope；主頁先於分頁註冊，此時分頁仍在整頁編輯中，
    // 返回鍵留給分頁的 PopScope 退出編輯。
    if (_tabBarHidden.value) return;
    if (_currentIndex != 0) {
      _pageController.animateToPage(
        0,
        duration: _tabAnimationDuration,
        curve: _tabAnimationCurve,
      );
      return;
    }

    final now = DateTime.now();
    if (_lastBackPressedAt == null ||
        now.difference(_lastBackPressedAt!) > _exitBackInterval) {
      _lastBackPressedAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('再按一次退出')));
      return;
    }

    await SystemNavigator.pop();
  }
}

typedef MainDestinationDoubleTapCallback = void Function(
  BuildContext context,
  int index,
);

class MainDestination {
  const MainDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.page,
    this.background,
    this.hidesTabBarOnScroll = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;

  /// 分頁的背景色，給分頁列後方的漸隱帶用；預設為 scaffold 背景色。
  final Color Function(BuildContext context)? background;

  /// 往下捲時分頁列與漸隱帶沉下讓出畫面（見 [_MainPageState._onPageScroll]）。
  final bool hidesTabBarOnScroll;

  Color backgroundOf(BuildContext context) =>
      background?.call(context) ?? Theme.of(context).scaffoldBackgroundColor;
}

class _KeepAliveWrapper extends StatefulWidget {
  const _KeepAliveWrapper({required this.child});
  final Widget child;
  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
