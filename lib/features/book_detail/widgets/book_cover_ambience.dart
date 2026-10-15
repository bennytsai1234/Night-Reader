import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 書籍詳情頁頂的封面氛圍：封面圖大幅模糊放大，半透明鋪在頁首與封面後面，
/// 往下漸隱成全透明，露出底下分組清單的底色。
///
/// 模糊只做一次：圖以很小的尺寸解碼，[ImageFiltered] 包在
/// [RepaintBoundary] 裡，捲動時只移動圖層，不重畫。強度壓在 [_strength]，
/// 而且呼叫端讓它在書名之前就完全漸隱成底色：書名與作者畫在純底色上，
/// 對比與沒有氛圍時相同（主要文字 7:1、次要 4.5:1）。
class BookCoverAmbience extends StatelessWidget {
  const BookCoverAmbience({super.key, required this.image});

  final ImageProvider image;

  /// 頂端封面色最多透出的比例；其餘是底色。
  static const double _strength = 0.32;

  /// 模糊半徑（邏輯像素）：比詳情頁封面寬度的三分之一還大，鋪滿頁寬後
  /// 只剩色塊，看不出封面的圖案或文字。
  static const double _blurSigma = 36;

  /// 模糊從圖的邊緣淡到看不見的距離（2.5 個標準差，剩不到 1%）。
  static const double _fadeLength = _blurSigma * 2.5;

  /// 解碼寬度：模糊後細節全失，用小圖省記憶體與解碼時間。
  static const int _decodeWidth = 64;

  /// 封面圖的氛圍來源；沒有封面（或是只存在記憶體的資源）時為 null，
  /// 頁面就不顯示氛圍。
  static ImageProvider? imageOf(String? coverUrl) {
    final source = coverUrl?.trim();
    if (source == null || source.isEmpty) return null;
    final ImageProvider provider;
    if (source.startsWith('local://')) {
      provider = FileImage(File(source.replaceFirst('local://', '')));
    } else if (source.startsWith('file://')) {
      provider = FileImage(File(Uri.parse(source).toFilePath()));
    } else if (source.startsWith('http://') || source.startsWith('https://')) {
      provider = CachedNetworkImageProvider(source);
    } else {
      return null;
    }
    return ResizeImage(provider, width: _decodeWidth);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // 圖往上、左右各多鋪 [_fadeLength]，那幾邊的模糊不會淡掉；下緣
                // 提早 [_fadeLength] 結束，模糊自己往下淡成全透明。這一區的
                // 邊界因此沒有任何顏色：往下拉回彈時整頁會被縮放取樣，邊界若是
                // 一層實色蓋在模糊圖上，那一列會透出模糊圖，在書名上方畫出一條線。
                Positioned(
                  left: -_fadeLength,
                  top: -_fadeLength,
                  right: -_fadeLength,
                  bottom: _fadeLength,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: _blurSigma,
                      sigmaY: _blurSigma,
                      tileMode: TileMode.decal,
                    ),
                    child: Image(
                      image: image,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      // 只透出 [_strength]，其餘是底下頁面的底色。
                      color: Colors.white.withValues(alpha: _strength),
                      colorBlendMode: BlendMode.modulate,
                      // 讀不到圖就不顯示氛圍，底下只剩底色。
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                      frameBuilder: (context, child, frame, synchronous) {
                        if (synchronous) return child;
                        return AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: AppMotion.fade,
                          curve: AppMotion.fadeCurve,
                          child: child,
                        );
                      },
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
}
