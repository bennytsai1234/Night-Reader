import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/core/services/resource_service.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 書的封面：只畫圖片本身加底下的陰影（ADR 0021）。
///
/// 換成另一張封面時（換封面、打勾或取消「統一封面」），舊封面留著，新封面
/// 解碼好才以 [AppMotion.fade] 淡入蓋過去；不會先空一下或一幀換掉。
class BookCoverWidget extends StatefulWidget {
  final String? coverUrl;
  final String bookName;
  final String? author;
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const BookCoverWidget({
    super.key,
    this.coverUrl,
    required this.bookName,
    this.author,
    this.width = 50,
    this.height = 70,
    this.borderRadius,
  });

  /// 載入失敗的封面：清單每次重建都會重新建立圖片，不記下來會一直重抓。
  static final Set<String> _failedCoverSources = <String>{};

  /// 忘掉失敗過的封面，下次顯示時再試。搜尋時上百個書源同時連線，封面常
  /// 只是一時逾時；每次新搜尋都重來一次，不會整個 App 開著都不再試。
  static void forgetFailedCovers() => _failedCoverSources.clear();

  @override
  State<BookCoverWidget> createState() => _BookCoverWidgetState();
}

/// 封面來源；null 是預設封面。
String? _sourceOf(String? coverUrl) {
  final source = coverUrl?.trim();
  return source == null || source.isEmpty ? null : source;
}

class _BookCoverWidgetState extends State<BookCoverWidget>
    with SingleTickerProviderStateMixin {
  /// 換封面的交叉淡化；第一次換封面時才建立，書架上大多數封面用不到。
  AnimationController? _swapController;
  CurvedAnimation? _swapCurve;

  AnimationController get _swap => _swapController ??=
      AnimationController(vsync: this, duration: AppMotion.fade)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              mounted &&
              _layers.length > 1) {
            setState(_settle);
          }
        });

  Animation<double> get _swapIn =>
      _swapCurve ??= CurvedAnimation(parent: _swap, curve: AppMotion.fadeCurve);

  /// 畫面上疊著的封面，由下而上，最下面那層一定不透明。平常只有一層；換
  /// 封面時要換成的那張疊上去，換到一半又換時，還看得到的幾層都留著。
  late List<_CoverLayer> _layers = [_CoverLayer.still(_target)];

  /// 要換成的封面（null 是預設封面）。
  String? get _target => _sourceOf(widget.coverUrl);

  /// 換封面中，還在等要換成的那張畫得出來（新圖解碼好）才開始淡換。
  bool _waiting = false;

  /// 換封面期間已經畫得出來的封面。
  final Set<String?> _drawable = {};

  @override
  void didUpdateWidget(BookCoverWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _target;
    if (_sourceOf(oldWidget.coverUrl) == next) return;
    _swapController?.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      _settle();
      return;
    }
    // 從畫面上實際的樣子接著換：每一層停在此刻的濃淡。被上面不透明的一層
    // 整個蓋住的、已經全透明的都看不到，拿掉；要換成的那張一定留著。
    final held = [
      for (final layer in _layers)
        (source: layer.source, opacity: layer.opacity.value),
    ];
    final covered = held.lastIndexWhere((layer) => layer.opacity >= 1);
    final kept = [
      for (final layer in held.skip(covered < 0 ? 0 : covered))
        if (layer.opacity > 0 || layer.source == next) layer,
    ];
    if (!kept.any((layer) => layer.source == next)) {
      kept.add((source: next, opacity: 0));
    }
    if (kept.length == 1 && kept.single.opacity >= 1) {
      // 要換成的正是畫面上整張不透明的那張（例如新圖還沒解碼就切回來）：
      // 取消這次換封面就好，畫面不動。
      _settle();
      return;
    }
    _swap.value = 0;
    _layers = [
      for (final layer in kept)
        _CoverLayer(layer.source, _swapIn, layer.opacity),
    ];
    _drawable.retainAll(kept.map((layer) => layer.source));
    _waiting = true;
    // 換回還看得到的那張（淡到一半又換回來）不必等，直接接著淡。
    final target = kept.firstWhere((layer) => layer.source == next);
    if (target.opacity > 0 || _drawable.contains(next)) _start();
  }

  @override
  void dispose() {
    _swapCurve?.dispose();
    _swapController?.dispose();
    super.dispose();
  }

  /// 開始淡換：要換成的那張淡到不透明，疊在它上面的淡掉，底下的照畫著。
  void _start() {
    _waiting = false;
    final at = _layers.indexWhere((layer) => layer.source == _target);
    for (var i = at; i < _layers.length; i++) {
      _layers[i].opacity.end = i == at ? 1 : 0;
    }
    // 只牽動 [FadeTransition] 的繪製，建構途中也可以開始。
    _swap.forward();
  }

  /// 換完（或不播）：只剩要換成的那一張。
  void _settle() {
    _waiting = false;
    _drawable.clear();
    _layers = [_CoverLayer.still(_target)];
  }

  /// 這張封面畫得出來了（圖解碼好，或改畫預設封面）；是要換成的那張就開始
  /// 淡換。
  void _ready(String? source) {
    if (_layers.length == 1) return;
    _drawable.add(source);
    if (_waiting && source == _target) _start();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = widget.borderRadius ?? AppRadius.cardXs;
    final trimmedAuthor = widget.author?.trim();
    final semanticLabel = trimmedAuthor == null || trimmedAuthor.isEmpty
        ? '《${widget.bookName}》封面'
        : '《${widget.bookName}》封面，作者 $trimmedAuthor';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final swapping = _layers.length > 1;

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: effectiveBorderRadius,
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.45)
                    : const Color(0x1A241C10),
                blurRadius: 5,
                offset: const Offset(1, 2),
              ),
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : const Color(0x0D000000),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          // 只畫圖片本身，不疊書脊陰影或亮線（ADR 0021）。
          child: ClipRRect(
            borderRadius: effectiveBorderRadius,
            // 網格以 double.infinity 撐滿格子，解碼尺寸要用實際版面大小。
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 每張封面以來源當 key：開始換時，原本那張連同已解碼的圖
                // 原封不動變成底下的一層，不重新載入。
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final layer in _layers)
                      KeyedSubtree(
                        key: ValueKey(('cover', layer.source)),
                        child: FadeTransition(
                          opacity: layer.opacity,
                          child: _CoverImage(
                            source: layer.source,
                            bookName: widget.bookName,
                            width: widget.width,
                            height: widget.height,
                            constraints: constraints,
                            // 換封面時由外面這層淡入，圖本身不再淡一次。
                            instant: swapping,
                            onReady: _ready,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 換封面時疊著的一張封面與它的濃淡。
class _CoverLayer {
  _CoverLayer(this.source, Animation<double> progress, double opacity)
    : opacity = _LayerOpacity(progress, opacity);

  /// 不在換封面時唯一的一層：完全不透明。
  _CoverLayer.still(String? source) : this(source, kAlwaysCompleteAnimation, 1);

  final String? source;
  final _LayerOpacity opacity;
}

/// 一層封面的濃淡：隨換封面的進度從 [start] 變到 [end]。還沒開始淡換時
/// 停在 [start]，也就是開始換那一刻畫面上的濃淡。
class _LayerOpacity extends Animation<double>
    with AnimationWithParentMixin<double> {
  _LayerOpacity(this.parent, this.start) : end = start;

  @override
  final Animation<double> parent;

  final double start;
  double end;

  @override
  double get value =>
      (start + (end - start) * parent.value).clamp(0.0, 1.0).toDouble();
}

/// 一張封面圖：網路、檔案、記憶體或預設封面。
class _CoverImage extends StatefulWidget {
  const _CoverImage({
    required this.source,
    required this.bookName,
    required this.width,
    required this.height,
    required this.constraints,
    required this.instant,
    required this.onReady,
  });

  final String? source;
  final String bookName;
  final double width;
  final double height;
  final BoxConstraints constraints;

  /// 圖到了直接出現、不淡入（換封面時由外層淡入）。
  final bool instant;

  /// 這張封面畫得出來了（圖解碼好，或改畫預設封面）。
  final ValueChanged<String?> onReady;

  @override
  State<_CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<_CoverImage> {
  /// 載不到時改畫的預設封面那一層。在圖片元件裡失敗、開始淡入後，之後的
  /// 重建直接在這裡畫它；同一個 key 接手同一段淡入，不會被截斷。
  final GlobalKey _fallbackKey = GlobalKey();

  Set<String> get _failed => BookCoverWidget._failedCoverSources;

  String get bookName => widget.bookName;
  double get width => widget.width;
  double get height => widget.height;
  BoxConstraints get constraints => widget.constraints;
  bool get instant => widget.instant;
  ValueChanged<String?> get onReady => widget.onReady;

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    if (source == null) {
      onReady(null);
      return _buildDefaultCover();
    }
    if (_failed.contains(source)) {
      // 失敗過的不再重抓。剛才在這裡失敗、還在淡入的照原本的淡入接著播；
      // 之前就記下失敗的（新建的封面）直接畫。
      onReady(source);
      return _FadeInOnce(
        key: _fallbackKey,
        instant: true,
        background: _buildPlaceholder(context),
        child: _buildDefaultCover(),
      );
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    int? decodeSize(double extent, double fallback) {
      final value = extent.isFinite ? extent : fallback;
      if (!value.isFinite || value <= 0) return null;
      return (value * devicePixelRatio).ceil();
    }

    final cacheWidth = decodeSize(width, constraints.maxWidth);
    final cacheHeight = decodeSize(height, constraints.maxHeight);

    if (source.startsWith('memory://')) {
      return FutureBuilder<Uint8List?>(
        future: ResourceService().getMemoryResource(source),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          final reveal = CoverRevealScope.waitingOf(context);
          if (bytes == null || bytes.isEmpty) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              reveal?.add(source);
              return _buildPlaceholder(context);
            }
            return _buildFailedCover(context, source);
          }
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: width,
            height: height,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            frameBuilder: (context, child, frame, sync) =>
                _fadeInFrame(context, source, child, frame, sync),
            errorBuilder: (context, error, stackTrace) =>
                _buildFailedCover(context, source),
          );
        },
      );
    }

    if (source.startsWith('local://') || source.startsWith('file://')) {
      final file = source.startsWith('local://')
          ? File(source.replaceFirst('local://', ''))
          : File(Uri.parse(source).toFilePath());
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        frameBuilder: (context, child, frame, sync) =>
            _fadeInFrame(context, source, child, frame, sync),
        errorBuilder: (context, error, stackTrace) =>
            _buildFailedCover(context, source),
      );
    }

    // 與檔案、記憶體封面走同一條淡入（[_fadeInFrame]）；磁碟快取照舊由
    // CachedNetworkImageProvider 負責。
    return Image(
      image: ResizeImage.resizeIfNeeded(
        cacheWidth,
        cacheHeight,
        CachedNetworkImageProvider(source),
      ),
      fit: BoxFit.cover,
      width: width,
      height: height,
      frameBuilder: (context, child, frame, sync) =>
          _fadeInFrame(context, source, child, frame, sync),
      errorBuilder: (context, error, stackTrace) =>
          _buildFailedCover(context, source),
    );
  }

  /// 載入中鋪一層與載入骨架同色的底（[Skeleton.colorOf]），不在每張縮圖上
  /// 轉圈；骨架換成書卡時封面位置的顏色不跳。
  static Widget _buildPlaceholder(BuildContext context) {
    return ColoredBox(color: Skeleton.colorOf(context));
  }

  /// 這次要不要直接出現：換封面中、在等一次淡入（[CoverRevealScope]，
  /// 跟著整頁一起出現），或系統關閉動畫。
  bool _instantIn(BuildContext context, CoverReveal? reveal) =>
      instant || reveal != null || MediaQuery.disableAnimationsOf(context);

  /// 封面要非同步解碼，解碼好之前什麼都不畫，圖一到就突然跳出來；改成
  /// 先鋪 [_buildPlaceholder]，圖以 [AppMotion.fade] 淡入。已經在快取、同一
  /// 幀就畫得出來的不淡入；在等待一次淡入（[CoverRevealScope]）時解碼好的
  /// 也不淡入，跟著整頁一起出現。
  Widget _fadeInFrame(
    BuildContext context,
    String source,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    final reveal = CoverRevealScope.waitingOf(context);
    if (frame == null) {
      reveal?.add(source);
    } else {
      reveal?.remove(source);
      onReady(source);
    }
    if (wasSynchronouslyLoaded) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPlaceholder(context),
        AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: _instantIn(context, reveal)
              ? Duration.zero
              : AppMotion.fade,
          curve: AppMotion.fadeCurve,
          child: child,
        ),
      ],
    );
  }

  /// 載不到的封面記下來、不再讓一次淡入等它，改畫預設封面：鋪在載入底上
  /// 以 [AppMotion.fade] 淡入，不在載入底上一幀冒出來。
  Widget _buildFailedCover(BuildContext context, String source) {
    final reveal = CoverRevealScope.waitingOf(context);
    reveal?.remove(source);
    _failed.add(source);
    onReady(source);
    return _FadeInOnce(
      key: _fallbackKey,
      instant: _instantIn(context, reveal),
      background: _buildPlaceholder(context),
      child: _buildDefaultCover(),
    );
  }

  /// 沒有封面或載不到時畫預設封面（[DefaultBookCover]）。
  Widget _buildDefaultCover() => DefaultBookCover(bookName: bookName);
}

/// 第一次出現時在 [background] 上以 [AppMotion.fade] 淡入 [child]；之後重建
/// 接著播完、不重播（[instant] 只看第一次建立時的值）。
class _FadeInOnce extends StatefulWidget {
  const _FadeInOnce({
    super.key,
    required this.instant,
    required this.background,
    required this.child,
  });

  final bool instant;
  final Widget background;
  final Widget child;

  @override
  State<_FadeInOnce> createState() => _FadeInOnceState();
}

class _FadeInOnceState extends State<_FadeInOnce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: widget.instant ? 1 : 0,
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
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.background,
        FadeTransition(opacity: _opacity, child: widget.child),
      ],
    );
  }
}
