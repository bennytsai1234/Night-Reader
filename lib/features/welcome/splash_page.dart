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
  late final AnimationController _exitController;
  late final AnimationController _breathController;

  late final Animation<double> _iconOpacity;
  late final Animation<double> _iconScale;
  late final Animation<double> _iconTranslateY;
  late final Animation<double> _arcSweep;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleTranslateY;
  late final Animation<double> _ruleScaleX;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _statusOpacity;
  late final Animation<double> _statusTranslateY;

  late final Animation<double> _exitFade;
  late final Animation<double> _exitScale;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _iconOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.00, 0.24, curve: Curves.easeOut),
    );
    _iconScale = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.00, 0.36, curve: Curves.easeOutBack),
      ),
    );
    _iconTranslateY = Tween<double>(begin: 32.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.00, 0.30, curve: Curves.easeOutCubic),
      ),
    );

    _arcSweep = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.14, 0.52, curve: Curves.easeOutCubic),
      ),
    );

    _titleOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.28, 0.50, curve: Curves.easeOut),
    );
    _titleTranslateY = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.28, 0.50, curve: Curves.easeOutCubic),
      ),
    );

    _ruleScaleX = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.40, 0.58, curve: Curves.easeOut),
    );

    _taglineOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.48, 0.68, curve: Curves.easeOut),
    );

    _statusOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.62, 0.82, curve: Curves.easeOut),
    );
    _statusTranslateY = Tween<double>(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.62, 0.82, curve: Curves.easeOutCubic),
      ),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );
    _exitScale = Tween<double>(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeIn));

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat(reverse: true);


    _entranceController.forward();
    _initApp();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _exitController.dispose();
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
    Future.delayed(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      _exitController.forward().then((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const MainPage(),
            transitionDuration: const Duration(milliseconds: 350),
            reverseTransitionDuration: const Duration(milliseconds: 250),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              );
            },
          ),
        );
      });
    });
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
        animation: Listenable.merge([
          _entranceController,
          _exitController,
          _breathController,
        ]),
        builder: (context, _) {
          final exitOpacity = _isExiting ? _exitFade.value : 1.0;
          final exitScale = _isExiting ? _exitScale.value : 1.0;
          final breath = math.sin(_breathController.value * math.pi);

          return Opacity(
            opacity: exitOpacity,
            child: Transform.scale(
              scale: exitScale,
              child: _buildContent(
                context,
                isDarkMode: isDarkMode,
                showIcon: showIcon,
                showText: showText,
                accent: accent,
                accentStrong: accentStrong,
                muted: muted,
                breath: breath,
              ),
            ),
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
                  offset: Offset(0, _iconTranslateY.value),
                  child: Opacity(
                    opacity: _iconOpacity.value,
                    child: Transform.scale(
                      scale: _iconScale.value + breath * 0.013,
                      child: _IconWithArc(
                        arcSweep: _arcSweep.value,
                        accent: accent,
                        isDarkMode: isDarkMode,
                      ),
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
    required this.accent,
    required this.isDarkMode,
  });

  final double arcSweep;
  final Color accent;
  final bool isDarkMode;

  @override
  Widget build(BuildContext context) {
    final shadowColor =
        isDarkMode
            ? Colors.black.withValues(alpha: 0.5)
            : const Color(0x1A14110D);

    return SizedBox(
      width: 156,
      height: 156,
      child: CustomPaint(
        painter: _ArcRingPainter(sweep: arcSweep, color: accent),
        child: Center(
          child: Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/app-icon.png', fit: BoxFit.cover),
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
