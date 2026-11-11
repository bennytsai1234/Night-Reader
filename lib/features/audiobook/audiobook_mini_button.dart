import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import 'audiobook_player.dart';

/// 離開播放器還在播時，書架、發現、我的在搜尋鈕上方浮的圓鈕
/// （`docs/design/audiobook.md`「離開播放器還在播：圓鈕」）：封面縮圖、外圈
/// 是本集收聽進度、中間是暫停／播放。點一下暫停／繼續，往上滑展開成播放器，
/// 往下滑停止播放。
///
/// 從螢幕右緣滑進來、收起時往右滑出去（使用者 2026-11-09 在動畫儀表板上
/// 選）；玻璃只滑動、不淡入（ADR 0022）。被別的頁面蓋著時出現的（從播放器
/// 返回），等露出來、換頁動畫播完，先在畫面外畫好一次、停
/// [AppMotion.stillGap]，再滑進來：第一次畫封面與玻璃的成本落在靜止的
/// 畫面上（ADR 0037 靜止時準備）。播放器停了就收起。
class AudiobookMiniButton extends StatefulWidget {
  const AudiobookMiniButton({super.key, this.player, this.hidden = false});

  /// 測試換成自己的播放器；平常是 [AudiobookPlayer.instance]。
  final AudiobookPlayer? player;

  /// 分頁列收起時（整頁編輯）跟著沉下。
  final bool hidden;

  /// 圓鈕的直徑，和搜尋鈕一樣大。
  static const double size = AppGlass.tabBarHeight;

  /// 和下面的搜尋鈕之間的距離。
  static const double gap = AppSpacing.md;

  /// 疊在主頁上時離螢幕底緣的距離：搜尋鈕上緣再空 [gap]。
  static double bottomOf(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom +
      AppGlass.tabBarBottomGap +
      AppGlass.tabBarHeight +
      gap;

  @override
  State<AudiobookMiniButton> createState() => _AudiobookMiniButtonState();
}

class _AudiobookMiniButtonState extends State<AudiobookMiniButton>
    with SingleTickerProviderStateMixin {
  late final AudiobookPlayer _player =
      widget.player ?? AudiobookPlayer.instance;
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: AppMotion.menu,
  );

  /// 最後一次有書的那本：收起動畫播的時候播放器已經沒有書了，封面照它畫。
  Book? _book;
  bool _waiting = false;

  /// 滑進來之前那一段：在畫面外畫好、等一下。
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_onPlayer);
    _book = _player.book;
    if (_book != null) _shown.value = 1;
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayer);
    _shown.dispose();
    super.dispose();
  }

  void _onPlayer() {
    final book = _player.book;
    if (book != null) {
      if (_book?.bookUrl != book.bookUrl) setState(() => _book = book);
      if (_shown.status.isForwardOrCompleted || _waiting) return;
      _waiting = true;
      unawaited(_enter());
    } else if (_shown.value > 0 &&
        !(_shown.status == AnimationStatus.reverse)) {
      _shown.animateBack(0, curve: Curves.easeInCubic);
    }
  }

  Future<void> _enter() async {
    await TransitionSettled.uncovered(context);
    if (!mounted || _player.book == null) {
      _waiting = false;
      return;
    }
    setState(() => _preparing = true);
    await Future<void>.delayed(AppMotion.stillGap);
    _waiting = false;
    if (!mounted) return;
    setState(() => _preparing = false);
    if (_player.book != null) _shown.animateTo(1, curve: AppMotion.menuCurve);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final book = _player.book;
    if (book == null) return;
    if (velocity < -200) {
      unawaited(Navigator.of(context).push(BookOpenRoute(book: book)));
    } else if (velocity > 200) {
      unawaited(_player.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    if (book == null) return const SizedBox.shrink();
    final button = Semantics(
      button: true,
      label: '有聲書：${book.name}',
      hint: '點兩下暫停或繼續，往上滑打開播放器，往下滑停止（記住聽到哪裡）',
      child: GestureDetector(
        onTap: () => unawaited(_player.toggle()),
        onVerticalDragEnd: _onVerticalDragEnd,
        child: SizedBox.square(
          dimension: AudiobookMiniButton.size,
          child: GlassSurface(
            shape: BoxShape.circle,
            child: _MiniFace(player: _player, book: book),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _shown,
      child: button,
      builder: (context, child) {
        final shown = widget.hidden ? 0.0 : _shown.value;
        // 準備那一段：畫在螢幕右緣外，看不到，但封面與玻璃都畫過一次。
        if (_preparing && shown <= 0) {
          return IgnorePointer(
            child: Transform.translate(
              offset: Offset(MediaQuery.sizeOf(context).width, 0),
              child: child,
            ),
          );
        }
        if (shown <= 0) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: shown < 1,
          child: GlassSlide(
            shown: shown,
            edge: AxisDirection.right,
            gap: MediaQuery.paddingOf(context).right + AppSpacing.lg,
            child: child!,
          ),
        );
      },
    );
  }
}

/// 圓鈕裡面：封面縮圖、外圈本集進度、中間暫停／播放。
class _MiniFace extends StatelessWidget {
  const _MiniFace({required this.player, required this.book});

  final AudiobookPlayer player;
  final Book book;

  static const double _ring = 2.5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = UnifiedCovers.coverOf(book);
    const inner = AudiobookMiniButton.size - _ring * 4;
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipOval(
          child: SizedBox.square(
            dimension: inner,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: inner,
                height: inner * 7 / 5,
                child: cover != null && cover.trim().isNotEmpty
                    ? BookCoverWidget(
                        coverUrl: cover,
                        bookName: book.name,
                        width: inner,
                        height: inner * 7 / 5,
                      )
                    : DefaultBookCover(
                        bookName: book.name,
                        kind: BookSourceKind.audio,
                      ),
              ),
            ),
          ),
        ),
        // 封面上墊一層暗色，圖示在任何封面上都看得清楚。
        Container(
          width: inner,
          height: inner,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x66000000),
          ),
        ),
        ListenableBuilder(
          listenable: player,
          builder: (context, _) => Icon(
            player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 26,
            color: Colors.white,
          ),
        ),
        ValueListenableBuilder<Duration>(
          valueListenable: player.position,
          builder: (context, at, _) {
            final total = player.duration?.inMilliseconds ?? 0;
            final progress = total <= 0
                ? 0.0
                : (at.inMilliseconds / total).clamp(0.0, 1.0);
            return CustomPaint(
              size: const Size.square(AudiobookMiniButton.size - _ring * 2),
              painter: _RingPainter(
                progress: progress,
                color: scheme.primary,
                track: scheme.onSurface.withValues(alpha: 0.12),
                width: _ring,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.width,
  });

  final double progress;
  final Color color;
  final Color track;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(width / 2),
      0,
      math.pi * 2,
      false,
      paint..color = track,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      rect.deflate(width / 2),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
