import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/core/services/resource_service.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';

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
          child: ClipRRect(
            borderRadius: effectiveBorderRadius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 網格以 double.infinity 撐滿格子，解碼尺寸要用實際版面大小。
                LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildCover(context, constraints),
                ),
                // Book Spine and tactile lighting overlay
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: effectiveBorderRadius,
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0x33000000), // Left spine dark edge
                            Color(0x14000000), // Spine crease
                            Color(0x00000000), // Main book face
                            Color(0x00000000), // Main book face
                            Color(0x0F000000), // Right page edge shadow
                          ],
                          stops: [0.0, 0.05, 0.16, 0.94, 1.0],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                // Subtle spine hinge highlight line (1px white glint near left edge)
                Positioned(
                  left: 3.0,
                  top: 0,
                  bottom: 0,
                  width: 0.75,
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                ),
              ],
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
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => _buildPlaceholder(context),
      errorWidget: (context, url, error) {
        _failedCoverSources.add(source);
        return _buildDefaultCover();
      },
    );
  }

  /// 載入中只鋪一層安靜的紙色，不在每張縮圖上轉圈。
  Widget _buildPlaceholder(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
