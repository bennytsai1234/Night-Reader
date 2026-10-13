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
    required this.wordStart,
    required this.wordEnd,
  });

  final int start;
  final int end;
  final double left;
  final double right;

  /// Unicode word boundary reported by the same native Paragraph that shaped
  /// this grapheme. VisualLineLayoutEngine may prefer this boundary for Latin
  /// words, but the final break decision remains Reader-owned.
  final int wordStart;
  final int wordEnd;
}

final class ReaderParagraphLayout {
  const ReaderParagraphLayout();

  static final Map<String, double> _cellWidthCache = <String, double>{};
  static final Map<String, double> _emojiScaleCache = <String, double>{};

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
    final cell = cellWidth != null && cellWidth.isFinite && cellWidth > 0
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
    );
    final unitWidth =
        textStyle.fontSize.abs() * 3 + textStyle.letterSpacing.abs() + 1;
    paragraph.layout(
      ui.ParagraphConstraints(width: math.max(1.0, text.length * unitWidth)),
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
        final word = paragraph.getWordBoundary(
          ui.TextPosition(
            offset: range.start,
            affinity: ui.TextAffinity.downstream,
          ),
        );
        result.add(
          ShapedGrapheme(
            start: range.start,
            end: range.end,
            left: bounds.left,
            right: bounds.right,
            wordStart: word.start.clamp(0, text.length).toInt(),
            wordEnd: word.end.clamp(0, text.length).toInt(),
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
  }) {
    if (!contentWidth.isFinite || contentWidth <= 0) {
      throw StateError('Paragraph width must be finite and positive.');
    }
    final builder = ui.ParagraphBuilder(_paragraphStyle(textStyle))
      ..pushStyle(_textStyle(textStyle, textColor));

    final indentCell = cellWidth != null && cellWidth.isFinite && cellWidth > 0
        ? cellWidth
        : textStyle.fontSize;
    for (var i = 0; i < textMap.indentLength; i += 1) {
      builder.addPlaceholder(
        indentCell,
        textStyle.fontSize,
        ui.PlaceholderAlignment.bottom,
      );
    }
    for (final piece in textMap.pieces(sourceText)) {
      final spacer = piece.spacerWidth;
      if (spacer != null) {
        // 零高度：補白只佔寬度，不參與行高。
        builder.addPlaceholder(spacer, 0, ui.PlaceholderAlignment.bottom);
      } else {
        _addStyledText(builder, piece.text!, textStyle, textColor);
      }
    }

    return builder.build()
      ..layout(ui.ParagraphConstraints(width: contentWidth));
  }

  /// emoji 的字級倍率：讓 emoji 的字寬等於一個漢字（不含字距），emoji
  /// 就和漢字一樣佔一格。
  double emojiScale(HybridBlockTextStyle style) {
    final key =
        '${style.fontSize}|${style.bold}|$kReaderV2CjkTypographyFeatureSignature';
    final cached = _emojiScaleCache[key];
    if (cached != null) return cached;
    final plain = HybridBlockTextStyle(
      fontSize: style.fontSize,
      lineHeight: 1.0,
      letterSpacing: 0,
      bold: style.bold,
    );
    double advance(String text) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle())
        ..pushStyle(_textStyle(plain, const ui.Color(0xFF000000)))
        ..addText(text);
      final paragraph = builder.build()
        ..layout(ui.ParagraphConstraints(width: style.fontSize * 8));
      final boxes = paragraph.getBoxesForRange(0, text.length);
      paragraph.dispose();
      if (boxes.isEmpty) return 0;
      return boxes.last.right - boxes.first.left;
    }

    final cjk = advance('一');
    final emoji = advance('\u{1F600}');
    final scale = cjk > 0 && emoji > 0 ? cjk / emoji : 1.0;
    _emojiScaleCache[key] = scale;
    return scale;
  }

  /// 依序加入文字；emoji 改用 [emojiScale] 縮放後的字級。行高由
  /// [_paragraphStyle] 的 strut 固定，縮放不影響行距。
  void _addStyledText(
    ui.ParagraphBuilder builder,
    String text,
    HybridBlockTextStyle style,
    ui.Color color,
  ) {
    final runs = emojiRuns(text);
    if (runs.isEmpty) {
      builder.addText(text);
      return;
    }
    final emojiStyle = _textStyle(style, color, fontScale: emojiScale(style));
    var cursor = 0;
    for (final run in runs) {
      if (run.start > cursor) {
        builder.addText(text.substring(cursor, run.start));
      }
      builder
        ..pushStyle(emojiStyle)
        ..addText(text.substring(run.start, run.end))
        ..pop();
      cursor = run.end;
    }
    if (cursor < text.length) builder.addText(text.substring(cursor));
  }

  /// 每一行都用同一個 strut 定行高：標點字型的垂直度量與 Noto Sans CJK
  /// 相同，所以純中文行的行高不變；夾著英數字（Roboto）或 emoji 的行
  /// 也不會因為字型的上下比例不同而多出零點幾像素。
  ui.ParagraphStyle _paragraphStyle(HybridBlockTextStyle style) {
    return ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      fontSize: style.fontSize,
      height: style.lineHeight,
      strutStyle: ui.StrutStyle(
        fontFamily: kReaderV2PunctFontFamily,
        fontFamilyFallback: kReaderV2FontFamilyFallback,
        fontSize: style.fontSize,
        height: style.lineHeight,
        fontWeight: style.bold ? ui.FontWeight.bold : ui.FontWeight.normal,
        forceStrutHeight: true,
      ),
    );
  }

  ui.Paragraph _nativeParagraph({
    required String text,
    required HybridBlockTextStyle textStyle,
    required ui.Color textColor,
  }) {
    final builder = ui.ParagraphBuilder(_paragraphStyle(textStyle))
      ..pushStyle(_textStyle(textStyle, textColor));
    _addStyledText(builder, text, textStyle, textColor);
    return builder.build();
  }

  ui.TextStyle _textStyle(
    HybridBlockTextStyle style,
    ui.Color color, {
    double fontScale = 1.0,
  }) {
    return ui.TextStyle(
      color: color,
      fontSize: style.fontSize * fontScale,
      height: style.lineHeight,
      letterSpacing: style.letterSpacing,
      fontWeight: style.bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      fontFamily: kReaderV2PunctFontFamily,
      fontFamilyFallback: kReaderV2FontFamilyFallback,
      fontFeatures: kReaderV2CjkFontFeatures,
      locale: kReaderV2TextLocale,
    );
  }
}

/// [text] 裡以 emoji 呈現的字元範圍（UTF-16，遞增、不重疊）。
///
/// 包含預設以 emoji 呈現的符號、帶 U+FE0F 的符號、國旗（兩個區域指示
/// 符號）、鍵帽（數字或 #* 接 U+20E3）、膚色修飾與以 ZWJ 串起的組合。
/// 預設以文字呈現的符號（例如 ©）不算。
List<({int start, int end})> emojiRuns(String text) {
  final result = <({int start, int end})>[];
  var index = 0;
  while (index < text.length) {
    final start = index;
    final rune = _runeAt(text, index);
    final next = index + _runeLength(rune);
    final following = next < text.length ? _runeAt(text, next) : null;
    final keycap =
        _isKeycapBase(rune) &&
        (following == 0x20E3 ||
            (following == 0xFE0F &&
                next + 1 < text.length &&
                _runeAt(text, next + 1) == 0x20E3));
    if (!keycap && !_startsEmoji(rune, following)) {
      index = next;
      continue;
    }
    index = next;
    var flagPaired = false;
    // 吸收這個 emoji 後面的修飾、國旗的第二個區域指示符號，以及以 ZWJ
    // 串起的下一個 emoji。
    while (index < text.length) {
      final r = _runeAt(text, index);
      if (r == 0xFE0F ||
          r == 0x20E3 ||
          (r >= 0x1F3FB && r <= 0x1F3FF) ||
          (r >= 0xE0020 && r <= 0xE007F)) {
        index += _runeLength(r);
        continue;
      }
      if (!flagPaired &&
          _isRegionalIndicator(rune) &&
          _isRegionalIndicator(r) &&
          index == next) {
        flagPaired = true;
        index += _runeLength(r);
        continue;
      }
      if (r == 0x200D && index + 1 < text.length) {
        final joined = _runeAt(text, index + 1);
        if (_isPictographic(joined)) {
          index += 1 + _runeLength(joined);
          continue;
        }
      }
      break;
    }
    if (result.isNotEmpty && result.last.end == start) {
      result[result.length - 1] = (start: result.last.start, end: index);
    } else {
      result.add((start: start, end: index));
    }
  }
  return result;
}

int _runeAt(String text, int index) {
  final unit = text.codeUnitAt(index);
  if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) {
    final low = text.codeUnitAt(index + 1);
    if (low >= 0xDC00 && low <= 0xDFFF) {
      return 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00);
    }
  }
  return unit;
}

int _runeLength(int rune) => rune > 0xFFFF ? 2 : 1;

bool _isKeycapBase(int rune) =>
    (rune >= 0x30 && rune <= 0x39) || rune == 0x23 || rune == 0x2A;

bool _isRegionalIndicator(int rune) => rune >= 0x1F1E6 && rune <= 0x1F1FF;

bool _startsEmoji(int rune, int? following) {
  if (following == 0xFE0F && _isPictographic(rune)) return true;
  return _isRegionalIndicator(rune) || _hasEmojiPresentation(rune);
}

/// 可以當 emoji 的符號（Extended_Pictographic 的常用範圍）。
bool _isPictographic(int rune) =>
    _hasEmojiPresentation(rune) ||
    rune == 0xA9 ||
    rune == 0xAE ||
    rune == 0x203C ||
    rune == 0x2049 ||
    rune == 0x2122 ||
    rune == 0x2139 ||
    (rune >= 0x2194 && rune <= 0x21AA) ||
    (rune >= 0x2300 && rune <= 0x23FF) ||
    (rune >= 0x24C2 && rune <= 0x25FF) ||
    (rune >= 0x2600 && rune <= 0x27BF) ||
    (rune >= 0x2934 && rune <= 0x2935) ||
    (rune >= 0x2B05 && rune <= 0x2B55) ||
    rune == 0x3030 ||
    rune == 0x303D ||
    rune == 0x3297 ||
    rune == 0x3299 ||
    (rune >= 0x1F000 && rune <= 0x1FAFF);

const Set<int> _bmpEmojiPresentation = <int>{
  0x231A, 0x231B, 0x23E9, 0x23EA, 0x23EB, 0x23EC, 0x23F0, 0x23F3, //
  0x25FD, 0x25FE, 0x2614, 0x2615, 0x267F, 0x2693, 0x26A1, 0x26AA,
  0x26AB, 0x26BD, 0x26BE, 0x26C4, 0x26C5, 0x26CE, 0x26D4, 0x26EA,
  0x26F2, 0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705, 0x270A, 0x270B,
  0x2728, 0x274C, 0x274E, 0x2753, 0x2754, 0x2755, 0x2757, 0x2795,
  0x2796, 0x2797, 0x27B0, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B55,
};

/// 預設就以 emoji 呈現（Emoji_Presentation=Yes）的符號。
bool _hasEmojiPresentation(int rune) {
  if (rune >= 0x1F300 && rune <= 0x1F64F) return true;
  if (rune >= 0x1F680 && rune <= 0x1F6FF) return true;
  if (rune >= 0x1F7E0 && rune <= 0x1F7FF) return true;
  if (rune >= 0x1F900 && rune <= 0x1FAFF) return true;
  if (rune == 0x1F004 || rune == 0x1F0CF || rune == 0x1F18E) return true;
  if (rune >= 0x1F191 && rune <= 0x1F19A) return true;
  if (rune >= 0x1F201 && rune <= 0x1F251) return true;
  if (rune >= 0x2648 && rune <= 0x2653) return true;
  return _bmpEmojiPresentation.contains(rune);
}
