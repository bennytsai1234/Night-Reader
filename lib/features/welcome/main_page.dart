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
  static const _tabAnimationDuration = Duration(milliseconds: 250);
  static const _tabAnimationCurve = Curves.easeInOut;

  late final List<MainDestination> _destinations =
      widget.destinations ?? _defaultDestinations;

  @override
  void dispose() {
    _splashTimeoutTimer?.cancel();
    _detachSplashShelfListener();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
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
    final shelf = context.watch<BookshelfProvider?>();
    final isRealShelfTab = widget.destinations == null && _currentIndex == 0;
    final showShelfLoadError =
        isRealShelfTab &&
        shelf != null &&
        !shelf.isLoading &&
        shelf.loadErrorMessage != null;

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
              onPageChanged: (idx) {
                setState(() => _currentIndex = idx);
              },
              children: List.generate(
                _destinations.length,
                (index) => _KeepAliveWrapper(child: _destinations[index].page),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child:
                      _showStartupLoadingOverlay
                          ? ColoredBox(
                            key: const ValueKey('startup-loading-overlay'),
                            color: Theme.of(
                              context,
                            ).scaffoldBackgroundColor.withValues(alpha: 0.96),
                            child: Center(
                              child: Semantics(
                                liveRegion: true,
                                label: '正在載入書架',
                                child: ExcludeSemantics(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 12),
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
            if (showShelfLoadError)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 32,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              shelf.loadErrorMessage!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: shelf.loadBooks,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('重試'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          height: 64,
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
