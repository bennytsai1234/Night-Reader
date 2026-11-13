import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:night_reader/features/source_login/source_failure_remedy.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'comic_page_images.dart';

import 'package:night_reader/shared/widgets/drag_overflow_text.dart';

/// 條漫上的一張圖：已經解碼好的直接畫；還沒到時畫骨架（照骨架呼吸），
/// 到了淡入；載不到時寫原因，下面「重試」與「用網頁開啟」，其他張照常
/// （`docs/design/comics.md`）。圖從 [ComicPageImages] 來，這裡不讀檔。
class ComicPageView extends StatefulWidget {
  const ComicPageView({
    super.key,
    required this.images,
    required this.imageKey,
    required this.width,
    required this.height,
    required this.onFailed,
    this.onOpenWeb,
    this.remedyFor,
  });

  final ComicPageImages images;
  final ComicImageKey imageKey;

  /// 這張畫的寬高（邏輯像素），由條漫決定。
  final double width;
  final double height;

  /// 載入失敗或重試時呼叫：失敗那一張要佔約八成螢幕高。
  final ValueChanged<bool> onFailed;

  /// 「用網頁開啟」；沒有網址時不顯示這個鈕。
  final VoidCallback? onOpenWeb;

  /// 載入失敗時能解決它的那一步（登入、前往驗證）；沒有時是 null。有的話
  /// 「用網頁開啟」讓位給它。
  final SourceFailureRemedy? Function(Object error)? remedyFor;

  @override
  State<ComicPageView> createState() => _ComicPageViewState();
}

class _ComicPageViewState extends State<ComicPageView> {
  ui.Image? _image;
  Object? _error;

  /// 圖到的時候這張在畫面上才淡入；畫上去時已經解碼好、或在畫面外解碼
  /// 好的直接顯示。
  bool _fadeIn = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(ComicPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.images, widget.images) ||
        oldWidget.imageKey != widget.imageKey) {
      oldWidget.images.removeListener(oldWidget.imageKey, _onChanged);
      _image?.dispose();
      _image = null;
      _error = null;
      _fadeIn = false;
      _attach();
    }
  }

  /// 開始畫 [ComicPageView.imageKey]：好了的直接拿，沒好的登記等通知。這裡
  /// 不回報失敗（建構中不能改條漫的高度）；失敗的高度條漫在通知時已經改過。
  void _attach() {
    final images = widget.images;
    final key = widget.imageKey;
    images.addListener(key, _onChanged);
    _image = images.image(key);
    _error = _image == null ? images.error(key) : null;
    if (_image == null && _error == null) images.want(key);
  }

  void _onChanged() {
    if (!mounted) return;
    final images = widget.images;
    final key = widget.imageKey;
    final image = _image == null ? images.image(key) : null;
    final error = images.error(key);
    if (image != null) {
      setState(() {
        _image = image;
        _error = null;
        _fadeIn = images.isVisible(key);
      });
    } else if (error != null && _error == null) {
      setState(() => _error = error);
      widget.onFailed(true);
    }
  }

  void _retry() {
    setState(() => _error = null);
    widget.onFailed(false);
    widget.images.retry(widget.imageKey);
  }

  /// 登入或驗證回來：登入資料有變才重試這一張。
  Future<void> _runRemedy(SourceFailureRemedy remedy) async {
    if (await remedy.run(context) && mounted) _retry();
  }

  @override
  void dispose() {
    widget.images.removeListener(widget.imageKey, _onChanged);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.height);
    if (_error case final error?) {
      final remedy = widget.remedyFor?.call(error);
      return SizedBox.fromSize(
        size: size,
        child: _PageError(
          error: error,
          onRetry: _retry,
          onOpenWeb: widget.onOpenWeb,
          remedy: remedy,
          onRemedy: remedy == null ? null : () => unawaited(_runRemedy(remedy)),
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
      image: image,
      width: size.width,
      height: size.height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    if (!_fadeIn) return picture;
    // 淡入播完就拿掉底下的骨架：不然它一直在呼吸、每幀重畫。
    return Stack(
      children: [
        skeleton,
        _FadeIn(
          onDone: () {
            if (mounted) setState(() => _fadeIn = false);
          },
          child: picture,
        ),
      ],
    );
  }
}

/// 圖到了以 [AppMotion.fade] 淡入，播完不再動。
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.onDone, required this.child});
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
  )..forward().whenCompleteOrCancel(() => widget.onDone());
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
    this.remedy,
    this.onRemedy,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onOpenWeb;

  /// 有解法（登入、前往驗證）時排第一，「用網頁開啟」不顯示。
  final SourceFailureRemedy? remedy;
  final VoidCallback? onRemedy;

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
            DragOverflowText(
              child: Text(
                ComicLoadError.describe(error),
                textAlign: TextAlign.center,
                maxLines: 3,
                style: AppTextStyles.labelSm.copyWith(
                  color: color?.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (remedy case final remedy?)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(onPressed: onRemedy, child: Text(remedy.label)),
                  const SizedBox(width: AppSpacing.md),
                  TextButton(onPressed: onRetry, child: const Text('重試')),
                ],
              )
            else
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
