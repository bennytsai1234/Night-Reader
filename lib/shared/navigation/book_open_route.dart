import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_read_time_scope.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 「封面放大翻開」的起點：被點的封面在螢幕上的範圍，以及照它在版面上的
/// 原尺寸畫好的封面。
class BookOpenCover {
  const BookOpenCover({
    required this.rect,
    required this.size,
    required this.child,
  });

  /// 量測 [coverContext] 底下的封面。[rect] 含按壓微縮等變形，是封面此刻
  /// 在螢幕上的範圍；[child] 由 [builder] 以未變形的版面尺寸畫出，解碼
  /// 尺寸與書架上的封面相同，能直接取用記憶體裡的圖，不會閃過佔位色。
  factory BookOpenCover.measure(
    BuildContext coverContext,
    Widget Function(Size size) builder,
  ) {
    final box = coverContext.findRenderObject()! as RenderBox;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    return BookOpenCover(rect: rect, size: box.size, child: builder(box.size));
  }

  final Rect rect;
  final Size size;
  final Widget child;
}

/// 開書轉場。
///
/// 從書架點書（帶 [cover]）時是「封面放大翻開」：封面從它在螢幕上的位置
/// 放大到整頁，接著淡出露出閱讀頁。拿不到封面位置的入口（書籍詳情、
/// 閱讀器換源等）維持短促的淡入加輕微上滑。返回一律用淡出加輕微下滑：
/// 回到書架時書會依最近閱讀重排，開書時記下的位置可能已經不是那本書。
///
/// 每幀都保持便宜：目的地 [ReaderV2Page] 的重排版已由
/// `_openRuntimeAfterFirstFrame` 延後到第一幀後；放大時閱讀頁只被裁在
/// 封面的範圍裡（裁切層，不需離屏合成），封面本身是一張 transform 的
/// 小圖層，淡出也只作用在封面這一層，不對整頁做 `Opacity`(saveLayer)
/// 或 3D 透視 overlay。
class BookOpenRoute extends PageRouteBuilder {
  BookOpenRoute({
    required this.book,
    this.openTarget,
    this.initialChapters = const <BookChapter>[],
    this.cover,
  }) : super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             ReaderV2ReadTimeScope(
               book: book,
               child: ReaderV2Page(
                 book: book,
                 openTarget: openTarget,
                 initialChapters: initialChapters,
               ),
             ),
         transitionDuration: cover == null
             ? const Duration(milliseconds: 280)
             : AppMotion.bookOpen,
         reverseTransitionDuration: const Duration(milliseconds: 220),
         transitionsBuilder: (context, animation, secondaryAnimation, child) =>
             _BookOpenTransition(
               animation: animation,
               cover: cover,
               child: child,
             ),
       );

  final Book book;
  final ReaderV2OpenTarget? openTarget;
  final List<BookChapter> initialChapters;

  /// 被點的封面；null 時用一般的淡入上滑。
  final BookOpenCover? cover;
}

class _BookOpenTransition extends StatelessWidget {
  const _BookOpenTransition({
    required this.animation,
    required this.cover,
    required this.child,
  });

  final Animation<double> animation;
  final BookOpenCover? cover;
  final Widget child;

  /// 放大結束、淡出開始的時間點（佔整段轉場的比例）。
  static final double _expandEnd =
      AppMotion.bookOpenExpand.inMicroseconds /
      AppMotion.bookOpen.inMicroseconds;
  static final double _fadeStart =
      1 - AppMotion.fade.inMicroseconds / AppMotion.bookOpen.inMicroseconds;

  @override
  Widget build(BuildContext context) {
    final cover = this.cover;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    // 樹的結構在進場與返回之間保持不變，閱讀頁的狀態才不會因換轉場而重建。
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, page) {
        final t = animation.value;
        final reversing = animation.status == AnimationStatus.reverse;
        final zooming = cover != null && !reversing;

        // 一般轉場：淡入加輕微上滑；返回時淡出加輕微下滑。
        var pageOpacity = 1.0;
        var pageShift = 0.0;
        if (!zooming) {
          final eased = reversing
              ? Curves.easeInCubic.transform(t)
              : Curves.easeOutCubic.transform(t);
          pageOpacity = eased;
          pageShift = 0.04 * (1 - eased);
        }

        Widget content = Opacity(
          opacity: pageOpacity,
          child: FractionalTranslation(
            translation: Offset(0, pageShift),
            child: page,
          ),
        );
        if (cover == null) return content;

        // 封面放大：可見範圍從封面的位置長到整頁，封面以等比填滿方式跟著
        // 放大（超出的部分被裁掉），閱讀頁在封面底下、同一個範圍裡。
        final expand = zooming
            ? AppMotion.bookOpenExpandCurve.transform(
                (t / _expandEnd).clamp(0.0, 1.0),
              )
            : 1.0;
        final fade = zooming
            ? AppMotion.fadeCurve.transform(
                ((t - _fadeStart) / (1 - _fadeStart)).clamp(0.0, 1.0),
              )
            : 1.0;
        final frame = Rect.lerp(cover.rect, screen, expand)!;
        final scale = math.max(
          frame.width / cover.size.width,
          frame.height / cover.size.height,
        );
        final coverTransform = Matrix4.identity()
          ..translateByDouble(
            frame.center.dx - cover.size.width * scale / 2,
            frame.center.dy - cover.size.height * scale / 2,
            0,
            1,
          )
          ..scaleByDouble(scale, scale, 1, 1);
        final radius = Radius.circular(AppRadius.xs * (1 - expand));

        return ClipRRect(
          clipper: _FrameClipper(RRect.fromRectAndRadius(frame, radius)),
          // 放大完成後不再裁切，閱讀期間不多一層裁切圖層。
          clipBehavior: expand < 1 ? Clip.antiAlias : Clip.none,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              Positioned(
                left: 0,
                top: 0,
                width: cover.size.width,
                height: cover.size.height,
                child: IgnorePointer(
                  child: Transform(
                    transform: coverTransform,
                    child: Opacity(
                      opacity: 1 - fade,
                      child: RepaintBoundary(child: cover.child),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 轉場中的可見範圍；座標以整個畫面為準（開書路由佔滿根 Navigator）。
class _FrameClipper extends CustomClipper<RRect> {
  const _FrameClipper(this.frame);

  final RRect frame;

  @override
  RRect getClip(Size size) => frame;

  @override
  bool shouldReclip(_FrameClipper oldClipper) => oldClipper.frame != frame;
}
