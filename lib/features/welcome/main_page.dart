import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';

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

/// 在其他分頁用 Android 手勢返回回書架時，換頁跟著拖曳走到哪一段。
enum _Follow { none, dragging, committing, cancelling }

class _MainPageState extends State<MainPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = 0;
  DateTime _lastTapTime = DateTime(0);
  DateTime? _lastBackPressedAt;

  BookshelfProvider? _launchShelf;
  VoidCallback? _launchShelfListener;

  late final PageController _pageController = PageController(
    initialPage: _currentIndex,
  );

  static const _exitBackInterval = Duration(seconds: 2);

  /// 分頁的 [PageView]；點分頁換頁時搬進 [AppTransitionSwitch]，靠這個 key
  /// 保住各分頁的狀態，也從這裡拍下換頁前的畫面。
  final GlobalKey _pagesKey = GlobalKey();

  /// 換頁的進度；換頁中 [_outgoing] 是換頁前畫面的快照。跟著返回手勢時
  /// 進度由手勢寫入，結束由 [handleCommitBackGesture]／
  /// [handleCancelBackGesture] 處理。
  late final AnimationController _switch = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status.isCompleted && _follow == _Follow.none) _endSwitch();
    });
  ui.Image? _outgoing;
  late Color _outgoingBackground;
  late Color _outgoingFade;
  int _outgoingIndex = 0;
  bool _switchForward = true;
  int _switchCount = 0;
  _Follow _follow = _Follow.none;
  final PredictiveBackTracker _back = PredictiveBackTracker();

  /// 跟著返回手勢時，每一格把換頁放到重新取樣後的進度。
  late final Ticker _backTicker = createTicker((_) {
    if (_follow != _Follow.dragging) return;
    final progress = _back.progress;
    if (progress != null) _switch.value = progress;
  });

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
    WidgetsBinding.instance.removeObserver(this);
    _detachLaunchShelfListener();
    for (final controller in _scrollToTopControllers.values) {
      controller.dispose();
    }
    _backTicker.dispose();
    _switch.dispose();
    _outgoing?.dispose();
    _pageController.dispose();
    _tabBarHidden.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabBarHidden.addListener(() => setState(() {}));
    if (_scrollToTopControllers.isNotEmpty) {
      _pageController.addListener(_scrollLeftTabsToTop);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initDeferredStartupData());
      if (widget.destinations == null) {
        _refreshShelfOnceLoaded();
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
    final page = PopScope<void>(
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
                  follow: _follow != _Follow.none,
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
          ],
        ),
        extendBody: true,
        bottomNavigationBar: _EntranceSlideUp(
          child: FloatingTabBar(
            // 換頁中頁面直接到位，膠囊改照選取的分頁用彈簧滑過去。
            controller: outgoing == null ? _pageController : null,
            // 返回手勢還沒確定返回前，膠囊留在原本的分頁。
            currentIndex:
                _follow == _Follow.dragging || _follow == _Follow.cancelling
                ? _outgoingIndex
                : _currentIndex,
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
      ),
    );
    // 開 App 的進場只在真正的主頁面播（ADR 0025）。
    return widget.destinations == null ? LaunchEntrance(child: page) : page;
  }

  /// 點分頁（或返回鍵回書架）換頁：不滑過中間的分頁，直接換過去，播
  /// 「外觀與主題 → 換頁動畫」選的那一種；往右邊的分頁像開新頁，往左像
  /// 返回。手指左右滑動照舊跟手。
  void _switchTo(int index) {
    _endSwitch();
    if (!_beginSwitch(index)) {
      _pageController.jumpToPage(index);
      return;
    }
    _switch
      ..duration = AppPageTransition.of(context).duration
      ..forward(from: 0);
  }

  /// 拍下換頁前的畫面、把分頁換到 [index]，交給 [AppTransitionSwitch]；
  /// 關閉動畫或還沒畫出來時不開始，回傳 false。
  bool _beginSwitch(int index, {bool follow = false}) {
    final boundary = _pagesKey.currentContext?.findRenderObject();
    if (MediaQuery.disableAnimationsOf(context) ||
        boundary is! RenderRepaintBoundary ||
        !boundary.hasSize) {
      return false;
    }
    // 換頁前的畫面不會再變，拍成一張圖給轉場用，不必兩頁同時活著。點擊
    // 與返回手勢在兩幀之間處理，分頁剛畫完，拍到的就是螢幕上的樣子。
    final image = boundary.toImageSync(
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final from = _pagePosition();
    final fade = _fadeColor(context);
    setState(() {
      _outgoing = image;
      _outgoingIndex = from.round();
      _outgoingBackground = _destinations[_outgoingIndex].backgroundOf(context);
      _outgoingFade = fade;
      _switchForward = index > from;
      _switchCount++;
      _currentIndex = index;
      _follow = follow ? _Follow.dragging : _Follow.none;
    });
    _pageController.jumpToPage(index);
    return true;
  }

  void _endSwitch() {
    _stopFollowingBack();
    final outgoing = _outgoing;
    if (outgoing == null) return;
    _switch.stop();
    setState(() {
      _outgoing = null;
      _follow = _Follow.none;
    });
    outgoing.dispose();
    // 跟著手勢時暫停的回頂，換頁結束後補做。
    _scrollLeftTabsToTop();
  }

  // ---------- 在其他分頁用 Android 手勢返回回書架 ----------
  //
  // 和一般頁面的預測返回一樣，拖曳中照選定的換頁動畫跟著進度走，返回與否
  // 由系統決定，放開後照 [BackSwipe] 的時長送完或彈回。

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent ||
        _currentIndex == 0 ||
        _tabBarHidden.value ||
        _outgoing != null ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      return false;
    }
    if (!_beginSwitch(0, follow: true)) return false;
    _back
      ..clear()
      ..record(backEvent, MediaQuery.devicePixelRatioOf(context));
    _switch.value = backEvent.progress;
    _backTicker.start();
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_follow != _Follow.dragging) return;
    _back.record(backEvent, MediaQuery.devicePixelRatioOf(context));
  }

  void _stopFollowingBack() {
    if (_backTicker.isActive) _backTicker.stop();
  }

  @override
  void handleCommitBackGesture() {
    if (_follow != _Follow.dragging) return;
    _stopFollowingBack();
    setState(() => _follow = _Follow.committing);
    _switch
        .animateTo(
          1,
          duration: BackSwipe.finishDuration(
            distance: (1 - _switch.value) * MediaQuery.sizeOf(context).width,
            velocity: _back.pixelsPerSecond,
          ),
          curve: BackSwipe.curve,
        )
        .whenCompleteOrCancel(() {
          if (_follow == _Follow.committing) _endSwitch();
        });
  }

  @override
  void handleCancelBackGesture() {
    if (_follow != _Follow.dragging) return;
    _stopFollowingBack();
    setState(() => _follow = _Follow.cancelling);
    _switch
        .animateBack(
          0,
          duration: BackSwipe.cancelDuration,
          curve: BackSwipe.curve,
        )
        .whenCompleteOrCancel(() {
          if (_follow != _Follow.cancelling) return;
          _pageController.jumpToPage(_outgoingIndex);
          _endSwitch();
        });
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
    // 返回手勢可能取消、回到原分頁，結束前不動它的捲動位置。
    if (_follow != _Follow.none) return;
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

  /// 書架第一次讀完書才在背景補排下載、檢查書架更新，不和首幀與書架載入
  /// 搶時間。
  void _refreshShelfOnceLoaded() {
    final shelf = context.read<BookshelfProvider?>();
    if (shelf == null) return;
    if (!shelf.isLoading) {
      unawaited(_runAutomaticShelfRefresh(shelf));
      return;
    }
    void listener() {
      if (shelf.isLoading) return;
      _detachLaunchShelfListener();
      unawaited(_runAutomaticShelfRefresh(shelf));
    }

    _launchShelf = shelf;
    _launchShelfListener = listener;
    shelf.addListener(listener);
  }

  void _detachLaunchShelfListener() {
    final listener = _launchShelfListener;
    if (listener != null) _launchShelf?.removeListener(listener);
    _launchShelf = null;
    _launchShelfListener = null;
  }

  Future<void> _runAutomaticShelfRefresh(BookshelfProvider shelf) async {
    try {
      await shelf.onAppLaunch();
    } catch (e, stack) {
      AppLog.e('Bookshelf refresh failed: $e', error: e, stackTrace: stack);
    }
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

/// 開 App 進場時分頁列從下緣滑進來（[LaunchEntrance]）；沒有進場時原樣畫。
class _EntranceSlideUp extends StatelessWidget {
  const _EntranceSlideUp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final entrance = LaunchEntrance.maybeOf(context);
    if (entrance == null) return child;
    return AnimatedBuilder(
      animation: entrance.tabBar,
      child: child,
      builder: (context, child) => GlassSlide(
        shown: entrance.tabBar.value,
        edge: AxisDirection.down,
        child: child!,
      ),
    );
  }
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
