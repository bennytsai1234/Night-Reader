import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:night_reader/shared/navigation/app_page_transition.dart';
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
  ),
  MainDestination(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: '發現',
    page: ExplorePage(),
    background: _groupedBackground,
  ),
  MainDestination(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: '我的',
    page: SettingsPage(),
    // 「我的」是 GroupedListView，底色是分組底色。
    background: _groupedBackground,
    scrollsToTopWhenLeft: true,
  ),
];

class MainPage extends StatefulWidget {
  const MainPage({super.key, this.destinations, this.onDestinationDoubleTap});

  final List<MainDestination>? destinations;
  final MainDestinationDoubleTapCallback? onDestinationDoubleTap;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with SingleTickerProviderStateMixin {
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

  /// 分頁的 [PageView]；點分頁換頁時搬進 [AppTransitionSwitch]，靠這個 key
  /// 保住各分頁的狀態，也從這裡拍下換頁前的畫面。
  final GlobalKey _pagesKey = GlobalKey();

  /// 點分頁換頁的進度；換頁中 [_outgoing] 是換頁前畫面的快照。
  late final AnimationController _switch = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status.isCompleted) _endSwitch();
    });
  ui.Image? _outgoing;
  late Color _outgoingBackground;
  late Color _outgoingFade;
  bool _switchForward = true;
  int _switchCount = 0;

  late final List<MainDestination> _destinations =
      widget.destinations ?? _defaultDestinations;

  /// 分頁進入整頁編輯時由分頁設為 true（見 [FloatingTabBarScope]）。
  final ValueNotifier<bool> _tabBarHidden = ValueNotifier(false);

  /// [MainDestination.scrollsToTopWhenLeft] 的分頁各自的捲動 controller。
  late final Map<int, ScrollController> _scrollToTopControllers = {
    for (var i = 0; i < _destinations.length; i++)
      if (_destinations[i].scrollsToTopWhenLeft) i: ScrollController(),
  };

  @override
  void dispose() {
    _splashTimeoutTimer?.cancel();
    _detachSplashShelfListener();
    for (final controller in _scrollToTopControllers.values) {
      controller.dispose();
    }
    _switch.dispose();
    _outgoing?.dispose();
    _pageController.dispose();
    _tabBarHidden.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tabBarHidden.addListener(() => setState(() {}));
    if (_scrollToTopControllers.isNotEmpty) {
      _pageController.addListener(_scrollLeftTabsToTop);
    }
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
    final outgoing = _outgoing;
    final pages = RepaintBoundary(
      key: _pagesKey,
      child: PageView(
        controller: _pageController,
        physics: _tabBarHidden.value
            ? const NeverScrollableScrollPhysics()
            : null,
        onPageChanged: (idx) {
          setState(() => _currentIndex = idx);
        },
        children: List.generate(_destinations.length, (index) {
          Widget page = FloatingTabBarScope(
            hidden: _tabBarHidden,
            child: _destinations[index].page,
          );
          final scroll = _scrollToTopControllers[index];
          if (scroll != null) {
            page = PrimaryScrollController(controller: scroll, child: page);
          }
          return _KeepAliveWrapper(child: page);
        }),
      ),
    );
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
            if (outgoing == null)
              pages
            else
              IgnorePointer(
                child: AppTransitionSwitch(
                  key: ValueKey(_switchCount),
                  transition: AppPageTransition.of(context),
                  animation: _switch,
                  forward: _switchForward,
                  outgoing: ExcludeSemantics(
                    child: RawImage(image: outgoing, fit: BoxFit.fill),
                  ),
                  incoming: pages,
                  outgoingBackground: _outgoingBackground,
                  incomingBackground: _destinations[_currentIndex].backgroundOf(
                    context,
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
                animation: Listenable.merge([_pageController, _switch]),
                builder: (context, _) => FloatingTabBarFade(
                  color: _fadeColor(context),
                  hidden: _tabBarHidden.value,
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
          // 換頁中頁面直接到位，膠囊改照選取的分頁用彈簧滑過去。
          controller: outgoing == null ? _pageController : null,
          currentIndex: _currentIndex,
          hidden: _tabBarHidden.value,
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
            _switchTo(index);
          },
        ),
      ),
    );
  }

  /// 點分頁（或返回鍵回書架）換頁：不滑過中間的分頁，直接換過去，播
  /// 「外觀與主題 → 換頁動畫」選的那一種；往右邊的分頁像開新頁，往左像
  /// 返回。手指左右滑動照舊跟手。
  void _switchTo(int index) {
    _endSwitch();
    final boundary = _pagesKey.currentContext?.findRenderObject();
    if (MediaQuery.disableAnimationsOf(context) ||
        boundary is! RenderRepaintBoundary ||
        !boundary.hasSize) {
      _pageController.jumpToPage(index);
      return;
    }
    // 換頁前的畫面不會再變，拍成一張圖給轉場用，不必兩頁同時活著。點擊
    // 在兩幀之間處理，分頁剛畫完，拍到的就是螢幕上的樣子。
    final image = boundary.toImageSync(
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final from = _pagePosition();
    final fade = _fadeColor(context);
    setState(() {
      _outgoing = image;
      _outgoingBackground = _destinations[from.round()].backgroundOf(context);
      _outgoingFade = fade;
      _switchForward = index > from;
      _switchCount++;
      _currentIndex = index;
    });
    _pageController.jumpToPage(index);
    _switch
      ..duration = AppPageTransition.of(context).duration
      ..forward(from: 0);
  }

  void _endSwitch() {
    final outgoing = _outgoing;
    if (outgoing == null) return;
    _switch.stop();
    setState(() => _outgoing = null);
    outgoing.dispose();
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
    if (_outgoing != null) {
      return Color.lerp(
        _outgoingFade,
        _destinations[_currentIndex].backgroundOf(context),
        _switch.value,
      )!;
    }
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

  /// 分頁完全滑出畫面後才捲回頂端：下次滑進來就從頂端開始，跳動不會被看到。
  void _scrollLeftTabsToTop() {
    final position = _pagePosition();
    _scrollToTopControllers.forEach((index, controller) {
      if ((position - index).abs() >= 1 &&
          controller.hasClients &&
          controller.offset != 0) {
        controller.jumpTo(0);
      }
    });
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
  Future<void> _openSearch() async {
    if (_openingSearch) return;
    _openingSearch = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const SearchPage()),
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
      _switchTo(0);
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
    this.scrollsToTopWhenLeft = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;

  /// 離開這個分頁後捲回頂端，每次來到都從頂端開始。分頁裡沒有指定
  /// controller 的直向清單會接上主頁提供的 [PrimaryScrollController]。
  final bool scrollsToTopWhenLeft;

  /// 分頁的背景色，給分頁列後方的漸隱帶用；預設為 scaffold 背景色。
  final Color Function(BuildContext context)? background;

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
