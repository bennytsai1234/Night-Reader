import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

final class ShapedGrapheme {
  const ShapedGrapheme({
    required this.start,
    required this.end,
    required this.left,
    required this.right,
  });

  final int start;
  final int end;
  final double left;
  final double right;
}

final class ReaderParagraphLayout {
  const ReaderParagraphLayout();

  static final Map<String, double> _cellWidthCache = <String, double>{};

  double? measureCellWidth({
    required double fontSize,
    required double letterSpacing,
    required bool bold,
  }) {
    if (!fontSize.isFinite || fontSize <= 0 || !letterSpacing.isFinite) {
      return null;
    }
    final key =
        '$fontSize|$letterSpacing|$bold|$kReaderV2CjkTypographyFeatureSignature';
    final cached = _cellWidthCache[key];
    if (cached != null) return cached;

    final paragraph = _nativeParagraph(
      text: '一一',
      textStyle: HybridBlockTextStyle(
        fontSize: fontSize,
        lineHeight: 1.0,
        letterSpacing: letterSpacing,
        bold: bold,
      ),
      textColor: const ui.Color(0xFF000000),
      textAlign: ui.TextAlign.start,
    )..layout(ui.ParagraphConstraints(width: fontSize * 8));

    double? cell;
    final first = paragraph.getBoxesForRange(0, 1);
    final second = paragraph.getBoxesForRange(1, 2);
    if (first.isNotEmpty && second.isNotEmpty) {
      final advance = second.first.left - first.first.left;
      if (advance.isFinite && advance > 0) cell = advance;
    }
    paragraph.dispose();
    if (cell != null) _cellWidthCache[key] = cell;
    return cell;
  }

  double indentWidth({
    required int indentChars,
    required double fontSize,
    required double? cellWidth,
  }) {
    if (indentChars <= 0) return 0.0;
    final cell =
        cellWidth != null && cellWidth.isFinite && cellWidth > 0
        ? cellWidth
        : fontSize;
    return indentChars.clamp(0, 8) * cell;
  }

  List<ShapedGrapheme> shapeGraphemes({
    required String text,
    required HybridBlockTextStyle textStyle,
  }) {
    if (text.isEmpty) return const <ShapedGrapheme>[];

    final paragraph = _nativeParagraph(
      text: text,
      textStyle: textStyle,
      textColor: const ui.Color(0xFF000000),
      textAlign: ui.TextAlign.start,
    );
    final unitWidth =
        textStyle.fontSize.abs() * 3 + textStyle.letterSpacing.abs() + 1;
    paragraph.layout(
      ui.ParagraphConstraints(
        width: math.max(1.0, text.length * unitWidth),
      ),
    );

    final result = <ShapedGrapheme>[];
    var offset = 0;
    try {
      while (offset < text.length) {
        final glyph = paragraph.getGlyphInfoAt(offset);
        if (glyph == null) {
          throw StateError(
            'Native shaper returned no grapheme at UTF-16 offset $offset.',
          );
        }
        final range = glyph.graphemeClusterCodeUnitRange;
        if (range.start > offset ||
            range.end <= offset ||
            range.end > text.length) {
          throw StateError(
            'Native shaper returned invalid grapheme range '
            '[${range.start}, ${range.end}) for offset $offset.',
          );
        }
        final bounds = glyph.graphemeClusterLayoutBounds;
        if (!bounds.left.isFinite ||
            !bounds.right.isFinite ||
            bounds.right < bounds.left) {
          throw StateError('Native shaper returned invalid glyph geometry.');
        }
        result.add(
          ShapedGrapheme(
            start: range.start,
            end: range.end,
            left: bounds.left,
            right: bounds.right,
          ),
        );
        offset = range.end;
      }
    } finally {
      paragraph.dispose();
    }
    return result;
  }

  ui.Paragraph build({
    required String sourceText,
    required ParagraphTextMap textMap,
    required HybridBlockTextStyle textStyle,
    required double contentWidth,
    required double? cellWidth,
    required ui.Color textColor,
    required ui.TextAlign textAlign,
  }) {
    if (!contentWidth.isFinite || contentWidth <= 0) {
      throw StateError('Paragraph width must be finite and positive.');
    }
    final body = textMap.layoutBody(sourceText);
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: textAlign,
      textDirection: ui.TextDirection.ltr,
      fontSize: textStyle.fontSize,
      height: textStyle.lineHeight,
    );
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(_textStyle(textStyle, textColor));

    final indentCell =
        cellWidth != null && cellWidth.isFinite && cellWidth > 0
        ? cellWidth
        : textStyle.fontSize;
    for (var i = 0; i < textMap.indentLength; i += 1) {
      builder.addPlaceholder(
        indentCell,
        textStyle.fontSize,
        ui.PlaceholderAlignment.bottom,
      );
    }
    builder.addText(body);

    return builder.build()
      ..layout(ui.ParagraphConstraints(width: contentWidth));
  }

  ui.Paragraph _nativeParagraph({
    required String text,
    required HybridBlockTextStyle textStyle,
    required ui.Color textColor,
    required ui.TextAlign textAlign,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: textAlign,
              textDirection: ui.TextDirection.ltr,
              fontSize: textStyle.fontSize,
              height: textStyle.lineHeight,
            ),
          )
          ..pushStyle(_textStyle(textStyle, textColor))
          ..addText(text);
    return builder.build();
  }

  ui.TextStyle _textStyle(
    HybridBlockTextStyle style,
    ui.Color color,
  ) {
    return ui.TextStyle(
      color: color,
      fontSize: style.fontSize,
      height: style.lineHeight,
      letterSpacing: style.letterSpacing,
      fontWeight: style.bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      fontFeatures: kReaderV2CjkFontFeatures,
    );
  }
}
