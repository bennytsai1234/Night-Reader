import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/services/default_data.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'main_page.dart';
import 'startup_failure_panel.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  String _status = '正在初始化...';
  String? _error;
  String? _resolvedWelcomeImagePath;
  File? _welcomeImageFile;
  bool _isInitializing = false;
  bool _initComplete = false;
  bool _isExiting = false;

  late final AnimationController _entranceController;
  late final AnimationController _breathController;

  late final Animation<double> _iconTranslateY;
  late final Animation<double> _arcSweep;
  late final Animation<double> _shadowOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleTranslateY;
  late final Animation<double> _ruleScaleX;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _statusOpacity;
  late final Animation<double> _statusTranslateY;

  @override
  void initState() {
    super.initState();

    // 進場總長壓短到 ~1050ms（原 1400ms），讓熱啟動不被動畫綁架。
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );

    // 圖示第一幀＝系統 splash 收尾的定格：scale 固定 1.0、置中、不重複 zoom
    // （系統已做過點擊放大）。先定格約 120ms 接住手感，再由螢幕中央上滑歸位
    // 到最終構圖；實際歸位距離在 build 以螢幕高度推導（見 iconRise）。
    _iconTranslateY = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.12, 0.56, curve: Curves.easeOutCubic),
      ),
    );

    _arcSweep = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.12, 0.46, curve: Curves.easeOutCubic),
      ),
    );

    // 底板陰影第一幀不顯示，隨定格結束淡入；系統 splash 圖示沒有投影，
    // 從無到有淡入可避免接力瞬間的陰影跳階。
    _shadowOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.12, 0.42, curve: Curves.easeOut),
    );

    _titleOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.34, 0.56, curve: Curves.easeOut),
    );
    _titleTranslateY = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.34, 0.56, curve: Curves.easeOutCubic),
      ),
    );

    _ruleScaleX = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.48, 0.66, curve: Curves.easeOut),
    );

    _taglineOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.58, 0.78, curve: Curves.easeOut),
    );

    _statusOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.72, 0.92, curve: Curves.easeOut),
    );
    _statusTranslateY = Tween<double>(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.72, 0.92, curve: Curves.easeOutCubic),
      ),
    );

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);

    FlutterNativeSplash.remove();
    _entranceController.forward();
    _initApp();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<SettingsProvider>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final customPath =
        isDarkMode ? settings.welcomeImageDark : settings.welcomeImage;
    if (customPath == _resolvedWelcomeImagePath) return;
    _resolvedWelcomeImagePath = customPath;
    _welcomeImageFile = null;
    unawaited(_resolveWelcomeImage(customPath));
  }

  Future<void> _initApp() async {
    if (_isInitializing) return;
    try {
      setState(() {
        _error = null;
        _isInitializing = true;
        _status = '正在載入閱讀配置...';
      });
      await DefaultData.initEssential();
      _initComplete = true;
      if (mounted) _triggerExitWhenReady();
    } catch (e, stack) {
      AppLog.e('Init Error: $e', error: e, stackTrace: stack);
      if (mounted) {
        setState(() {
          _error = '$e\n$stack';
          _isInitializing = false;
        });
      }
    }
  }

  // 退場時機＝max(進場動畫播完, initEssential 完成)：兩者皆備才離場，
  // 既不會在資料未就緒時提前露白，也不會在熱啟動時被動畫綁架。
  void _triggerExitWhenReady() {
    if (_isExiting || !mounted) return;
    if (_entranceController.isAnimating) {
      _entranceController.addStatusListener(_onEntranceComplete);
    } else {
      _startExit();
    }
  }

  void _onEntranceComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _entranceController.removeStatusListener(_onEntranceComplete);
      if (_initComplete && mounted) _startExit();
    }
  }

  void _startExit() {
    if (_isExiting || !mounted) return;
    _isExiting = true;
    // 單一連續轉場：品牌頁與書架底色同為 scaffoldBackground，書架於同底色上
    // 純淡入蓋過品牌頁，不再經過「淡出 → 純底色 → 淡入」的空白幀、也不縮放。
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MainPage(),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _resolveWelcomeImage(String path) async {
    if (path.isEmpty) return;
    final file = File(path);
    final exists = await file.exists();
    if (!mounted || _resolvedWelcomeImagePath != path) return;
    setState(() => _welcomeImageFile = exists ? file : null);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final showIcon =
        isDarkMode ? settings.welcomeShowIconDark : settings.welcomeShowIcon;
    final showText =
        isDarkMode ? settings.welcomeShowTextDark : settings.welcomeShowText;

    final base = theme.scaffoldBackgroundColor;
    final accent = isDarkMode ? AppPalette.cinnabarDark : AppPalette.cinnabar;
    final accentStrong = isDarkMode ? AppPalette.ink50 : AppPalette.ink700;
    final muted = isDarkMode ? AppPalette.ink200 : AppPalette.ink300;

    return Scaffold(
      backgroundColor: base,
      body: AnimatedBuilder(
        animation: Listenable.merge([_entranceController, _breathController]),
        builder: (context, _) {
          final breath = math.sin(_breathController.value * math.pi);
          return _buildContent(
            context,
            isDarkMode: isDarkMode,
            showIcon: showIcon,
            showText: showText,
            accent: accent,
            accentStrong: accentStrong,
            muted: muted,
            breath: breath,
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required bool isDarkMode,
    required bool showIcon,
    required bool showText,
    required Color accent,
    required Color accentStrong,
    required Color muted,
    required double breath,
  }) {
    // 圖示第一幀置於螢幕中央（接住系統 splash 收尾），再上滑約 8.5% 螢幕高
    // 歸位到版面上半的最終構圖。此係數依「最終靜止點到螢幕中央的距離」推導，
    // 可依實機觀感微調。
    final double iconRise = MediaQuery.sizeOf(context).height * 0.085;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_welcomeImageFile != null)
          Opacity(
            opacity: 0.08,
            child: Image.file(_welcomeImageFile!, fit: BoxFit.cover),
          ),

        SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),

              if (showIcon)
                Transform.translate(
                  offset: Offset(0, _iconTranslateY.value * iconRise),
                  child: Transform.scale(
                    scale: 1.0 + breath * 0.013,
                    child: _IconWithArc(
                      arcSweep: _arcSweep.value,
                      shadowOpacity: _shadowOpacity.value,
                      accent: accent,
                      isDarkMode: isDarkMode,
                    ),
                  ),
                ),

              if (showIcon) const SizedBox(height: 36),

              if (showText) ...[
                Transform.translate(
                  offset: Offset(0, _titleTranslateY.value),
                  child: Opacity(
                    opacity: _titleOpacity.value,
                    child: Text(
                      '夜讀',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamilySerif,
                        fontSize: 42,
                        fontWeight: FontWeight.w700,
                        color: accentStrong,
                        letterSpacing: 10.0,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Transform.scale(
                  scaleX: _ruleScaleX.value,
                  child: Container(
                    width: 40,
                    height: 1.0,
                    color: accent.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: _taglineOpacity.value,
                  child: Text(
                    '閱讀，從這裡開始',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamilySerif,
                      fontSize: 13,
                      color: muted,
                      letterSpacing: 2.0,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],

              const Spacer(flex: 2),

              Transform.translate(
                offset: Offset(0, _statusTranslateY.value),
                child: Opacity(
                  opacity: _statusOpacity.value,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child:
                        _error != null
                            ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: StartupFailurePanel(
                                details: _error!,
                                onRetry: () => unawaited(_initApp()),
                              ),
                            )
                            : _StatusRow(status: _status, accent: accent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconWithArc extends StatelessWidget {
  const _IconWithArc({
    required this.arcSweep,
    required this.shadowOpacity,
    required this.accent,
    required this.isDarkMode,
  });

  final double arcSweep;
  final double shadowOpacity;
  final Color accent;
  final bool isDarkMode;

  // 圓形底板直徑與外圈 arc 框；底板與遮罩刻意對齊 Android 自適應/系統 splash
  // 圖示（圓遮罩 + 深棕底板 + 前景 inset 16%），讓系統→品牌頁圖示零換圖。
  // _plate 為對齊系統 splash 圖示視覺尺寸的初值，可依實機微調。
  static const double _plate = 120.0;
  static const double _ring = 156.0;
  static const double _foregroundInset = 0.16;

  @override
  Widget build(BuildContext context) {
    final baseShadow = isDarkMode ? Colors.black : const Color(0xFF14110D);
    final shadowAlpha = (isDarkMode ? 0.5 : 0.10) * shadowOpacity;

    return SizedBox(
      width: _ring,
      height: _ring,
      child: CustomPaint(
        painter: _ArcRingPainter(sweep: arcSweep, color: accent),
        child: Center(
          child: Container(
            width: _plate,
            height: _plate,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // 深棕底板對齊 adaptive icon 背景（colors.xml ic_launcher_background）。
              color: AppPalette.ink600,
              boxShadow: [
                if (shadowAlpha > 0.001)
                  BoxShadow(
                    color: baseShadow.withValues(alpha: shadowAlpha),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              // 前景 inset 16%，對齊 mipmap-anydpi-v26/ic_launcher.xml 的 inset。
              padding: const EdgeInsets.all(_plate * _foregroundInset),
              child: Image.asset(
                'assets/app_icon/ic_foreground.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcRingPainter extends CustomPainter {
  const _ArcRingPainter({required this.sweep, required this.color});

  final double sweep;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (sweep <= 0) return;
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - 6) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepAngle = 2 * math.pi * sweep;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.38 * sweep),
    );

    if (sweep > 0.04) {
      final tipAngle = -math.pi / 2 + sweepAngle;
      canvas.drawCircle(
        Offset(
          center.dx + radius * math.cos(tipAngle),
          center.dy + radius * math.sin(tipAngle),
        ),
        2.2,
        Paint()..color = color.withValues(alpha: 0.65 * sweep),
      );
    }
  }

  @override
  bool shouldRepaint(_ArcRingPainter old) =>
      old.sweep != sweep || old.color != color;
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.accent});

  final String status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            valueColor: AlwaysStoppedAnimation<Color>(
              accent.withValues(alpha: 0.65),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          status,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamilySans,
            fontSize: 11,
            color: accent.withValues(alpha: 0.60),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
