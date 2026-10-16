import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/core/services/resource_service.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
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
          if (bytes == null || bytes.isEmpty) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildPlaceholder(context);
            }
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
            frameBuilder: _fadeInFrame,
            errorBuilder: (context, error, stackTrace) {
              _failedCoverSources.add(source);
              return _buildDefaultCover();
            },
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
        frameBuilder: _fadeInFrame,
        errorBuilder: (context, error, stackTrace) {
          _failedCoverSources.add(source);
          return _buildDefaultCover();
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: source,
      fit: BoxFit.cover,
      width: width,
      height: height,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      fadeInDuration: AppMotion.fade,
      fadeOutDuration: AppMotion.fade,
      placeholder: (context, url) => _buildPlaceholder(context),
      errorWidget: (context, url, error) {
        _failedCoverSources.add(source);
        return _buildDefaultCover();
      },
    );
  }

  /// 載入中鋪一層與載入骨架同色的底（[Skeleton.colorOf]），不在每張縮圖上
  /// 轉圈；骨架換成書卡時封面位置的顏色不跳。
  Widget _buildPlaceholder(BuildContext context) {
    return ColoredBox(color: Skeleton.colorOf(context));
  }

  /// 檔案與記憶體封面要非同步解碼，解碼好之前什麼都不畫，圖一到就突然
  /// 跳出來；改成先鋪 [_buildPlaceholder]，圖以 [AppMotion.fade] 淡入，
  /// 與網路封面一樣。已經在快取、同一幀就畫得出來的不淡入。
  Widget _fadeInFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildPlaceholder(context),
        AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.fade,
          curve: AppMotion.fadeCurve,
          child: child,
        ),
      ],
    );
  }

  /// 沒有封面或載不到時畫預設封面（[DefaultBookCover]）。
  Widget _buildDefaultCover() => DefaultBookCover(bookName: bookName);

  /// 載入失敗的封面：清單每次重建都會重新建立圖片，不記下來會一直重抓。
  static final Set<String> _failedCoverSources = <String>{};

  /// 忘掉失敗過的封面，下次顯示時再試。搜尋時上百個書源同時連線，封面常
  /// 只是一時逾時；每次新搜尋都重來一次，不會整個 App 開著都不再試。
  static void forgetFailedCovers() => _failedCoverSources.clear();
}
