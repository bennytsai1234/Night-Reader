import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/core/services/resource_service.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

class BookCoverWidget extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? AppRadius.cardXs;
    final trimmedAuthor = author?.trim();
    final semanticLabel = trimmedAuthor == null || trimmedAuthor.isEmpty
        ? '《$bookName》封面'
        : '《$bookName》封面，作者 $trimmedAuthor';

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          width: width,
          height: height,
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
              builder: (context, constraints) =>
                  _buildCover(context, constraints),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, BoxConstraints constraints) {
    final source = coverUrl?.trim();
    if (source == null || source.isEmpty) {
      return _buildDefaultCover();
    }

    if (_failedCoverSources.contains(source)) {
      return _buildDefaultCover();
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
            reveal?.remove(source);
            _failedCoverSources.add(source);
            return _buildDefaultCover();
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
  Widget _buildPlaceholder(BuildContext context) {
    return ColoredBox(color: Skeleton.colorOf(context));
  }

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
    }
    if (wasSynchronouslyLoaded) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPlaceholder(context),
        AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: reveal != null || MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.fade,
          curve: AppMotion.fadeCurve,
          child: child,
        ),
      ],
    );
  }

  /// 載不到的封面記下來、不再讓一次淡入等它，畫預設封面。
  Widget _buildFailedCover(BuildContext context, String source) {
    CoverRevealScope.waitingOf(context)?.remove(source);
    _failedCoverSources.add(source);
    return _buildDefaultCover();
  }

  /// 沒有封面或載不到時畫預設封面（[DefaultBookCover]）。
  Widget _buildDefaultCover() => DefaultBookCover(bookName: bookName);

  /// 載入失敗的封面：清單每次重建都會重新建立圖片，不記下來會一直重抓。
  static final Set<String> _failedCoverSources = <String>{};

  /// 忘掉失敗過的封面，下次顯示時再試。搜尋時上百個書源同時連線，封面常
  /// 只是一時逾時；每次新搜尋都重來一次，不會整個 App 開著都不再試。
  static void forgetFailedCovers() => _failedCoverSources.clear();
}
