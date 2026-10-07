import 'package:flutter/material.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';

/// 朗讀高亮：句段淡淡地鋪底，正在朗讀的字詞以燈色實底標出。
///
/// 框貼著字形，不是整行色帶；引擎不回報字詞進度時只有句段鋪底。
final class HybridTtsHighlightOverlay extends StatelessWidget {
  const HybridTtsHighlightOverlay({
    super.key,
    required this.sentence,
    required this.word,
    required this.textColor,
  });

  final List<HybridLineBox> sentence;
  final List<HybridLineBox> word;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    if (sentence.isEmpty && word.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: HybridTtsHighlightPainter(
            sentence: sentence,
            word: word,
            highlightColor: readerHighlightColor(textColor),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// 閱讀區的強調色（朗讀高亮、選字）；依正文色判斷日夜，讀使用者自訂色。
Color readerHighlightColor(Color textColor) {
  final darkReader = textColor.computeLuminance() > 0.5;
  final custom = ThemeSettingsProvider.resolveReaderAreaColors(
    dark: darkReader,
    menu: false,
  );
  return custom?.highlight ?? const Color(0xFFFFC857);
}

final class HybridTtsHighlightPainter extends CustomPainter {
  const HybridTtsHighlightPainter({
    required this.sentence,
    required this.word,
    required this.highlightColor,
  });

  final List<HybridLineBox> sentence;
  final List<HybridLineBox> word;
  final Color highlightColor;

  static const double _sentenceAlpha = 0.16;
  static const double _wordAlpha = 0.42;
  static const Radius _radius = Radius.circular(4);

  /// 框略為外擴，讓色塊包住字形而不是切齊字緣。
  static Rect rectOf(HybridLineBox box) =>
      Rect.fromLTRB(box.left - 2, box.top, box.right + 2, box.bottom);

  @override
  void paint(Canvas canvas, Size size) {
    final sentencePaint = Paint()
      ..color = highlightColor.withValues(alpha: _sentenceAlpha);
    for (final box in sentence) {
      canvas.drawRRect(RRect.fromRectAndRadius(rectOf(box), _radius), sentencePaint);
    }
    final wordPaint = Paint()
      ..color = highlightColor.withValues(alpha: _wordAlpha);
    for (final box in word) {
      canvas.drawRRect(RRect.fromRectAndRadius(rectOf(box), _radius), wordPaint);
    }
  }

  @override
  bool shouldRepaint(HybridTtsHighlightPainter oldDelegate) {
    return !_sameBoxes(oldDelegate.sentence, sentence) ||
        !_sameBoxes(oldDelegate.word, word) ||
        oldDelegate.highlightColor != highlightColor;
  }

  static bool _sameBoxes(List<HybridLineBox> a, List<HybridLineBox> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      final x = a[i];
      final y = b[i];
      if (x.left != y.left ||
          x.top != y.top ||
          x.right != y.right ||
          x.bottom != y.bottom) {
        return false;
      }
    }
    return true;
  }
}
