import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:reader/core/services/resource_service.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';

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

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: effectiveBorderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: _buildCover(context),
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

    if (source.startsWith('memory://')) {
      return FutureBuilder<Uint8List?>(
        future: ResourceService().getMemoryResource(source),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildPlaceholder();
            }
            _failedCoverSources.add(source);
            return _buildTextCover();
          }
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: width,
            height: height,
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
      if (!file.existsSync()) {
        _failedCoverSources.add(source);
        return _buildTextCover();
      }
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: width,
        height: height,
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
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => _buildPlaceholder(),
      errorWidget: (context, url, error) {
        _failedCoverSources.add(source);
        return _buildTextCover();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.withValues(alpha: 0.1),
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
    // 根據書名生成隨機但固定的背景色
    final int colorIndex = bookName.hashCode.abs() % _coverColors.length;
    final Color color = _coverColors[colorIndex];
    final String displayChar = bookName.isNotEmpty ? bookName[0] : '書';

    return Container(
      color: color,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              displayChar,
              style: AppTextStyles.titleSm.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 2),
            Text(
              'No Image',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<Color> _coverColors = [
    Color(0xFFE57373),
    Color(0xFFF06292),
    Color(0xFFBA68C8),
    Color(0xFF9575CD),
    Color(0xFF7986CB),
    Color(0xFF64B5F6),
    Color(0xFF4FC3F7),
    Color(0xFF4DB6AC),
    Color(0xFF81C784),
    Color(0xFFAED581),
    Color(0xFFFFB74D),
    Color(0xFFD4E157),
  ];

  static final Set<String> _failedCoverSources = <String>{};
}
