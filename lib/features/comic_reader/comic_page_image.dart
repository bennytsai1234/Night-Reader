import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'comic_page_source.dart';

/// 一張漫畫圖，照畫面寬度解碼（比畫面寬的圖縮小，省記憶體），放進 Flutter
/// 的圖片快取，捲回來不用再讀檔。
@immutable
class ComicPageImage extends ImageProvider<ComicPageImage> {
  const ComicPageImage({
    required this.source,
    required this.chapterIndex,
    required this.page,
    required this.targetWidth,
  });

  final ComicPageSource source;
  final int chapterIndex;
  final ComicPage page;

  /// 解碼寬度（實體像素）。
  final int targetWidth;

  @override
  Future<ComicPageImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ComicPageImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ComicPageImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: '${page.name}@$chapterIndex',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await source.bytesOf(chapterIndex, page);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(
      buffer,
      getTargetSize: (width, height) => width > targetWidth
          ? ui.TargetImageSize(width: targetWidth)
          : const ui.TargetImageSize(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ComicPageImage &&
      identical(other.source, source) &&
      other.chapterIndex == chapterIndex &&
      other.page.name == page.name &&
      other.targetWidth == targetWidth;

  @override
  int get hashCode => Object.hash(
    identityHashCode(source),
    chapterIndex,
    page.name,
    targetWidth,
  );
}

/// 條漫上的一張圖：還沒到時畫骨架（照骨架呼吸），到了淡入；載不到時寫原因，
/// 下面「重試」與「用網頁開啟」，其他張照常（`docs/design/comics.md`）。
class ComicPageView extends StatefulWidget {
  const ComicPageView({
    super.key,
    required this.source,
    required this.chapterIndex,
    required this.page,
    required this.width,
    required this.height,
    required this.onAspectRatio,
    required this.onFailed,
    this.onOpenWeb,
  });

  final ComicPageSource source;
  final int chapterIndex;
  final ComicPage page;

  /// 這張畫的寬高（邏輯像素），由條漫決定。
  final double width;
  final double height;

  /// 圖到了，回報量到的比例（高 ÷ 寬）。
  final ValueChanged<double> onAspectRatio;

  /// 載入失敗或重試時呼叫：失敗那一張要佔約八成螢幕高。
  final ValueChanged<bool> onFailed;

  /// 「用網頁開啟」；沒有網址時不顯示這個鈕。
  final VoidCallback? onOpenWeb;

  @override
  State<ComicPageView> createState() => _ComicPageViewState();
}

class _ComicPageViewState extends State<ComicPageView> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _image;
  Object? _error;

  /// 第一次解碼時已經在快取裡的圖直接顯示，不淡入。
  bool _fadeIn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ComicPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source) ||
        oldWidget.chapterIndex != widget.chapterIndex ||
        oldWidget.page.name != widget.page.name ||
        _targetWidthChanged(oldWidget)) {
      _resolve();
    }
  }

  int _targetWidth() =>
      (widget.width * MediaQuery.devicePixelRatioOf(context)).ceil();

  bool _targetWidthChanged(ComicPageView oldWidget) =>
      (oldWidget.width - widget.width).abs() > 0.5;

  ComicPageImage _provider() => ComicPageImage(
    source: widget.source,
    chapterIndex: widget.chapterIndex,
    page: widget.page,
    targetWidth: _targetWidth(),
  );

  void _resolve() {
    final stream = _provider().resolve(ImageConfiguration.empty);
    if (stream.key == _stream?.key) return;
    _stopListening();
    _stream = stream;
    var synchronous = true;
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        final first = _image == null;
        setState(() {
          _image?.dispose();
          _image = info;
          _error = null;
          if (first) _fadeIn = !synchronous;
        });
        final image = info.image;
        if (image.width > 0) widget.onAspectRatio(image.height / image.width);
      },
      onError: (error, _) {
        if (!mounted) return;
        setState(() => _error = error);
        widget.onFailed(true);
      },
    );
    _listener = listener;
    stream.addListener(listener);
    synchronous = false;
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
  }

  void _retry() {
    unawaited(_provider().evict());
    setState(() => _error = null);
    widget.onFailed(false);
    _stream = null;
    _resolve();
  }

  @override
  void dispose() {
    _stopListening();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.height);
    if (_error case final error?) {
      return SizedBox.fromSize(
        size: size,
        child: _PageError(
          error: error,
          onRetry: _retry,
          onOpenWeb: widget.onOpenWeb,
        ),
      );
    }
    final image = _image;
    final skeleton = SkeletonBox(
      width: size.width,
      height: size.height,
      borderRadius: BorderRadius.zero,
    );
    if (image == null) return skeleton;
    final picture = RawImage(
      image: image.image,
      width: size.width,
      height: size.height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    if (!_fadeIn) return picture;
    return Stack(
      children: [
        skeleton,
        _FadeIn(child: picture),
      ],
    );
  }
}

/// 圖到了以 [AppMotion.fade] 淡入，播完不再動。
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.child});
  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
  )..forward();
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.fadeCurve,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

/// 一張圖載不到：置中寫原因，下面「重試」與「用網頁開啟」（照 Mihon 的
/// `ReaderPageError`）。
class _PageError extends StatelessWidget {
  const _PageError({
    required this.error,
    required this.onRetry,
    this.onOpenWeb,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onOpenWeb;

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 40, color: color),
            const SizedBox(height: AppSpacing.md),
            Text('這張圖載不到', style: AppTextStyles.titleSm.copyWith(color: color)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              ComicLoadError.describe(error),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSm.copyWith(
                color: color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('重試')),
                if (onOpenWeb case final open?) ...[
                  const SizedBox(width: AppSpacing.md),
                  TextButton(onPressed: open, child: const Text('用網頁開啟')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 載入失敗時給使用者看的原因。
abstract final class ComicLoadError {
  static String describe(Object error) {
    final text = error.toString().replaceFirst(
      RegExp(r'^\w*(Exception|Error): '),
      '',
    );
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }
}
