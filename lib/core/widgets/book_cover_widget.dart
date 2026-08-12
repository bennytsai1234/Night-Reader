import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:night_reader/core/services/resource_service.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';

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
    final semanticLabel =
        trimmedAuthor == null || trimmedAuthor.isEmpty
            ? '《$bookName》封面'
            : '《$bookName》封面，作者 $trimmedAuthor';

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: effectiveBorderRadius,
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A241C10),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: effectiveBorderRadius,
            child: _buildCover(context),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final source = coverUrl?.trim();
    if (source == null || source.isEmpty) {
      return _buildTextCover();
    }

    if (_failedCoverSources.contains(source)) {
      return _buildTextCover();
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (width * devicePixelRatio).ceil();
    final cacheHeight = (height * devicePixelRatio).ceil();

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
            return _buildTextCover();
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
              return _buildTextCover();
            },
          );
        },
      );
    }

    if (source.startsWith('local://') || source.startsWith('file://')) {
      final file =
          source.startsWith('local://')
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
          return _buildTextCover();
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
        return _buildTextCover();
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// 實作文字封面 (對標 Android 預設文字封面)
  Widget _buildTextCover() {
    final int colorIndex = bookName.hashCode.abs() % _coverColors.length;
    final Color color = _coverColors[colorIndex];
    final Color foregroundColor = _readableForeground(color);
    final String displayChar = bookName.isNotEmpty ? bookName[0] : '書';

    return Container(
      color: color,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              displayChar,
              style: AppTextStyles.titleSm.copyWith(color: foregroundColor),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '無封面',
              style: AppTextStyles.labelXs.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _readableForeground(Color background) {
    const lightForeground = AppPalette.paper50;
    const darkForeground = AppPalette.ink700;

    double contrastRatio(Color foreground) {
      final lighter =
          foreground.computeLuminance() > background.computeLuminance()
              ? foreground.computeLuminance()
              : background.computeLuminance();
      final darker =
          foreground.computeLuminance() > background.computeLuminance()
              ? background.computeLuminance()
              : foreground.computeLuminance();
      return (lighter + 0.05) / (darker + 0.05);
    }

    return contrastRatio(darkForeground) >= contrastRatio(lightForeground)
        ? darkForeground
        : lightForeground;
  }

  static const List<Color> _coverColors = [
    AppPalette.cinnabar,
    AppPalette.rust,
    AppPalette.tea,
    AppPalette.gold,
    AppPalette.azurite,
    AppPalette.moss,
    AppPalette.ink300,
    AppPalette.aubergine,
  ];

  static final Set<String> _failedCoverSources = <String>{};
}
