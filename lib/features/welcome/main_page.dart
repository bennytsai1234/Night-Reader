import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/default_data.dart';
import 'package:night_reader/features/about/update_check_runner.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';

const List<MainDestination> _defaultDestinations = [
  MainDestination(
    icon: Icons.book_outlined,
    selectedIcon: Icons.book,
    label: '書架',
    page: BookshelfPage(),
  ),
  MainDestination(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore,
    label: '發現',
    page: ExplorePage(),
  ),
  MainDestination(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: '我的',
    page: SettingsPage(),
  ),
];

class MainPage extends StatefulWidget {
  const MainPage({super.key, this.destinations, this.onDestinationDoubleTap});

  /// 自訂分頁清單;測試時用以避免拉入真實 page 的 deps。預設為 [_defaultDestinations]。
  final List<MainDestination>? destinations;

  /// 同一個 destination 被快速連點兩次時觸發。預設邏輯:書架 → loadBooks()。
  final MainDestinationDoubleTapCallback? onDestinationDoubleTap;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  DateTime _lastTapTime = DateTime(0);
  DateTime? _lastBackPressedAt;

  // 一段式啟動:main.dart 的 FlutterNativeSplash.preserve() 延後首幀,讓原生
  // splash(主題色純色底 + AVD 動畫圖示)從點圖標一路撐到書架首批書載完才放行,
  // 使用者一看到書架就是填好的清單。全程只有原生這一層,無 Flutter 端轉場圖。
  bool _splashReleaseScheduled = false;
  DateTime? _splashHeldAt;
  BookshelfProvider? _splashShelfProvider;
  VoidCallback? _splashShelfListener;

  // 最短顯示時間讓原生圖示動畫(約 1000ms,首幀回呼前已播一段)不被腰斬;
  // 逾時保險避免書架查詢異常卡住開機。
  static const _splashMinDisplay = Duration(milliseconds: 900);
  static const _splashShelfTimeout = Duration(seconds: 2);

  late final PageController _pageController = PageController(
    initialPage: _currentIndex,
  );

  static const _exitBackInterval = Duration(seconds: 2);
  static const _tabAnimationDuration = Duration(milliseconds: 250);
  static const _tabAnimationCurve = Curves.easeInOut;

  late final List<MainDestination> _destinations =
      widget.destinations ?? _defaultDestinations;

  @override
  void dispose() {
    _detachSplashShelfListener();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initDeferredStartupData());
      if (widget.destinations == null) {
        // 僅真實 app 路徑;測試注入 destinations 時不觸碰 platform channel。
        _releaseSplashWhenShelfReady();
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
        body: PageView(
          controller: _pageController,
          onPageChanged: (idx) {
            setState(() => _currentIndex = idx);
          },
          children: List.generate(
            _destinations.length,
            (index) => _KeepAliveWrapper(child: _destinations[index].page),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
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
          destinations:
              _destinations
                  .map(
                    (destination) => NavigationDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: destination.label,
                    ),
                  )
                  .toList(),
        ),
      ),
    );
  }

  void _handleDoubleTap(int index) {
    final cb = widget.onDestinationDoubleTap ?? _defaultDoubleTap;
    cb(context, index);
  }

  void _defaultDoubleTap(BuildContext context, int index) {
    // 預設 double-tap 行為僅針對預設 destinations(書架在 index 0)
    if (widget.destinations != null) return;
    if (index == 0) {
      context.read<BookshelfProvider>().loadBooks();
    }
  }

  // 書架首批書載完(或逾時)才呼叫 FlutterNativeSplash.remove() 放行首幀,
  // 原生 splash 一路把持畫面,首幀即為填好的書架、不閃轉圈。
  void _releaseSplashWhenShelfReady() {
    _splashHeldAt = DateTime.now();
    final shelf = context.read<BookshelfProvider>();
    if (!shelf.isLoading) {
      _releaseSplashOnce();
      return;
    }
    void listener() {
      if (!shelf.isLoading) _releaseSplashOnce();
    }

    _splashShelfProvider = shelf;
    _splashShelfListener = listener;
    shelf.addListener(listener);
    Future<void>.delayed(_splashShelfTimeout, _releaseSplashOnce);
  }

  // 書架就緒後放行;若距首幀回呼未滿 _splashMinDisplay 則補足,
  // 讓原生圖示動畫播完、不因小書架瞬間載完而腰斬。
  void _releaseSplashOnce() {
    if (_splashReleaseScheduled) return;
    _splashReleaseScheduled = true;
    _detachSplashShelfListener();
    final heldAt = _splashHeldAt;
    final remaining =
        heldAt == null
            ? Duration.zero
            : _splashMinDisplay - DateTime.now().difference(heldAt);
    if (remaining > Duration.zero) {
      Future<void>.delayed(remaining, FlutterNativeSplash.remove);
    } else {
      FlutterNativeSplash.remove();
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

  Future<void> _handleBackIntent() async {
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

typedef MainDestinationDoubleTapCallback =
    void Function(BuildContext context, int index);

class MainDestination {
  const MainDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.page,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;
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
